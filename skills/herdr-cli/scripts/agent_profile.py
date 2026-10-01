#!/usr/bin/env python3
"""agent_profile.py — parse, resolve, and compose named agent profiles for runagent.

Profiles live in ~/.pi/agent/agents/<name>.md (YAML frontmatter + system-prompt body).
This module is stdlib-only (no pyyaml). It implements a small YAML subset:

  key: value
  key: [a, b, c]
  key:
    subkey: value        # one level of nesting (used by `sandbox:`)

CLI:
  agent_profile.py compose <agent> [--model M] [--workspace DIR] [--cwd DIR]
                           [--env K=V]... [--json]
  agent_profile.py list

Exit codes: 0 ok, 2 usage, 12 profile resolution failure.
"""

import json
import os
import re
import shlex
import sys
from pathlib import Path

PI_AGENT = Path.home() / ".pi" / "agent"
AGENT_DIR = PI_AGENT / "agents"
SKILL_DIRS_DEFAULT = [
    PI_AGENT / "skills",
    Path.home() / ".agents" / "skills",
]
NPM_DIR = PI_AGENT / "npm" / "node_modules"
SETTINGS_JSON = PI_AGENT / "settings.json"
MCP_ADAPTER_JSON = PI_AGENT / "mcp-adapter.json"


class ProfileError(Exception):
    """Any profile resolution failure (maps to exit 12)."""


# ── Frontmatter parsing (YAML subset) ─────────────────────────────────────

def _parse_scalar(raw):
    raw = raw.strip()
    if raw == "":
        return None
    if (raw.startswith('"') and raw.endswith('"')) or (raw.startswith("'") and raw.endswith("'")):
        return raw[1:-1]
    if raw.startswith("[") and raw.endswith("]"):
        inner = raw[1:-1].strip()
        if not inner:
            return []
        items = []
        for part in _split_top_level(inner):
            items.append(_parse_scalar(part))
        return items
    low = raw.lower()
    if low in ("on", "true", "yes"):
        return True
    if low in ("off", "false", "no"):
        return False
    if low in ("null", "none", "~"):
        return None
    return raw


def _split_top_level(s):
    parts, depth, cur, quote = [], 0, "", None
    for ch in s:
        if quote:
            cur += ch
            if ch == quote:
                quote = None
            continue
        if ch in "\"'":
            quote = ch
            cur += ch
        elif ch in "[{":
            depth += 1
            cur += ch
        elif ch in "]}":
            depth -= 1
            cur += ch
        elif ch == "," and depth == 0:
            parts.append(cur)
            cur = ""
        else:
            cur += ch
    if cur.strip():
        parts.append(cur)
    return parts


def parse_frontmatter(text):
    """Parse '---' delimited frontmatter into (dict, body). Stdlib-only YAML subset."""
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        raise ProfileError("file has no frontmatter (missing leading '---')")
    end = None
    for i in range(1, len(lines)):
        if lines[i].strip() == "---":
            end = i
            break
    if end is None:
        raise ProfileError("frontmatter is not terminated with '---'")
    data = {}
    current_nested = None
    prev_key = None
    for raw in lines[1:end]:
        line = raw.rstrip()
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        stripped = line.strip()
        indented = line[:1] in (" ", "\t")
        if indented and ":" in stripped:
            # nested mapping line. If the preceding key held a scalar
            # (e.g. `sandbox: on` followed by indented `workspace:`),
            # convert it to a dict in place.
            if current_nested is None:
                if prev_key is None or not isinstance(data.get(prev_key), dict):
                    if prev_key is not None:
                        data[prev_key] = {prev_key: data.get(prev_key)}
                    current_nested = prev_key
                else:
                    raise ProfileError(f"unexpected indented line without mapping: {raw!r}")
            key, _, val = stripped.partition(":")
            data[current_nested][key.strip()] = _parse_scalar(val)
            continue
        if ":" not in stripped:
            raise ProfileError(f"unparseable frontmatter line: {raw!r}")
        key, _, val = stripped.partition(":")
        key = key.strip()
        val = val.strip()
        if val == "":
            # start of a nested mapping (e.g. sandbox:)
            data[key] = {}
            current_nested = key
        else:
            data[key] = _parse_scalar(val)
            current_nested = None
        prev_key = key
    body = "\n".join(lines[end + 1:]).strip("\n")
    return data, body


# ── Profile loading ───────────────────────────────────────────────────────

def load_profile(name, cwd=None):
    """Load a profile by name. Returns (profile_dict, body, path)."""
    path = AGENT_DIR / f"{name}.md"
    if not path.is_file():
        available = sorted(p.stem for p in AGENT_DIR.glob("*.md") if not p.stem.endswith(".chain"))
        raise ProfileError(f"unknown agent profile '{name}'. Available: {', '.join(available)}")
    text = path.read_text(encoding="utf-8")
    fm, body = parse_frontmatter(text)
    fm_name = fm.get("name")
    if fm_name and fm_name != name:
        print(f"WARNING: profile name '{fm_name}' does not match filename stem '{name}'", file=sys.stderr)
    harness = fm.get("harness", "pi")
    if harness != "pi":
        raise ProfileError(f"unsupported harness '{harness}' (only 'pi' supported in v1)")
    if not body.strip():
        raise ProfileError(f"profile '{name}' has no system prompt body")
    return fm, body, path


# ── Resolvers ─────────────────────────────────────────────────────────────

def _npm_skills_dirs():
    dirs = []
    if NPM_DIR.is_dir():
        for pkg in sorted(NPM_DIR.iterdir()):
            sd = pkg / "skills"
            if sd.is_dir():
                dirs.append(sd)
    return dirs


def _package_skill_dirs():
    """Skill dirs declared by local directory sources in settings.json packages."""
    dirs = []
    try:
        settings = json.loads(SETTINGS_JSON.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return dirs
    for entry in settings.get("packages", []):
        if not isinstance(entry, str):
            continue
        if entry.startswith("npm:") or entry.startswith("http"):
            continue
        base = Path(entry)
        if not base.is_absolute():
            base = AGENT_DIR / base
        base = base.resolve()
        sd = base / "skills"
        if sd.is_dir():
            dirs.append(sd)
    return dirs


def resolve_skills(names, cwd):
    """Resolve skill names to SKILL.md paths. First match wins; unknown → ProfileError."""
    if names is None:
        return None  # absent → no skills
    if names == ["all"]:
        return "all"
    if not isinstance(names, list):
        raise ProfileError(f"skills must be a list, got {names!r}")
    search = []
    if cwd:
        proj = Path(cwd) / ".pi" / "skills"
        if proj.is_dir():
            search.append(proj)
    search.extend(SKILL_DIRS_DEFAULT)
    search.extend(_npm_skills_dirs())
    search.extend(_package_skill_dirs())
    out = []
    for name in names:
        found = None
        for base in search:
            cand = base / name / "SKILL.md"
            if cand.is_file():
                found = cand
                break
        if found is None:
            raise ProfileError(f"unknown skill '{name}' (searched: "
                               + ", ".join(str(b) for b in search) + ")")
        out.append(str(found))
    return out


def _resolve_entry_file(pkg_dir, rel):
    """Resolve a package entry (file or directory) to a concrete entry file.

    pi's --extension takes a file; some packages declare a directory (e.g.
    pi-web-access: pi.extensions = ['./dist']). For directories, use the
    sub-package's package.json 'main' if present, else index.js/index.ts.
    Returns None if no entry file can be found.
    """
    p = (pkg_dir / rel).resolve()
    if p.is_file():
        return str(p)
    if p.is_dir():
        sub_json = p / "package.json"
        if sub_json.is_file():
            try:
                main = json.loads(sub_json.read_text(encoding="utf-8")).get("main")
            except json.JSONDecodeError:
                main = None
            if main:
                mp = (p / main).resolve()
                if mp.is_file():
                    return str(mp)
        for cand in ("index.js", "index.ts"):
            f = p / cand
            if f.is_file():
                return str(f)
    return None


def _extension_entries_from_package(pkg_dir):
    """Resolve a package's pi extension entry FILES from its package.json.

    Directory entries are resolved to their entry file (see _resolve_entry_file);
    pi's --extension flag requires files, not directories.
    """
    pkg_json = pkg_dir / "package.json"
    entries = []
    if pkg_json.is_file():
        try:
            pj = json.loads(pkg_json.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            pj = {}
        pi_exts = (pj.get("pi") or {}).get("extensions")
        if isinstance(pi_exts, list):
            for rel in pi_exts:
                f = _resolve_entry_file(pkg_dir, rel)
                if f:
                    entries.append(f)
            if entries:
                return entries
        main = pj.get("main")
        if main:
            f = _resolve_entry_file(pkg_dir, main)
            if f:
                entries.append(f)
    for cand in ("index.ts", "index.js"):
        p = pkg_dir / cand
        if p.is_file():
            entries.append(str(p))
            break
    return entries


def _installed_extensions():
    """Build name → [entry paths] from settings.json packages. Returns (npm_map, local_map, all)."""
    npm_map, local_map = {}, {}
    try:
        settings = json.loads(SETTINGS_JSON.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        raise ProfileError(f"cannot read {SETTINGS_JSON} (needed to resolve extensions)")
    for entry in settings.get("packages", []):
        if not isinstance(entry, str):
            continue
        if entry.startswith("npm:"):
            pkg_name = entry[4:]
            pkg_dir = NPM_DIR / pkg_name
            if pkg_dir.is_dir():
                npm_map[pkg_name] = _extension_entries_from_package(pkg_dir)
        elif entry.startswith("http"):
            continue  # remote sources cannot be resolved locally
        else:
            base = Path(entry)
            if not base.is_absolute():
                base = AGENT_DIR / base
            base = base.resolve()
            if base.is_dir():
                entries = _extension_entries_from_package(base)
                if not entries and (base / "index.ts").is_file():
                    entries = [str(base / "index.ts")]
                local_map[base.name] = entries
    return npm_map, local_map


def resolve_extensions(names):
    """Resolve extension names to file paths. First match: npm:<name>, then local /name. Unknown → ProfileError."""
    if names is None:
        return None  # absent → no extensions
    if names == ["all"]:
        return "all"
    if not isinstance(names, list):
        raise ProfileError(f"extensions must be a list, got {names!r}")
    npm_map, local_map = _installed_extensions()
    out, seen = [], set()
    for name in names:
        entries = None
        if name in npm_map:
            entries = npm_map[name]
        elif name in local_map:
            entries = local_map[name]
        if not entries:
            raise ProfileError(
                f"unknown extension '{name}' (installed npm packages: {', '.join(sorted(npm_map))}; "
                f"local sources: {', '.join(sorted(local_map))})")
        for e in entries:
            if e not in seen:
                seen.add(e)
                out.append(e)
    return out


def resolve_mcp(names):
    """Resolve MCP server names to a filtered config dict. Unknown server → ProfileError.
    Returns (config_dict, mode) where mode is 'filtered' | 'all' | 'none'."""
    if names is None:
        return {"mcpServers": {}}, "none"
    if names == ["all"]:
        return None, "all"
    if not isinstance(names, list):
        raise ProfileError(f"mcp must be a list, got {names!r}")
    try:
        full = json.loads(MCP_ADAPTER_JSON.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        raise ProfileError(f"cannot read {MCP_ADAPTER_JSON}")
    servers = full.get("mcpServers", {})
    filtered = {}
    for name in names:
        if name not in servers:
            raise ProfileError(f"unknown mcp server '{name}' (available: {', '.join(sorted(servers))})")
        filtered[name] = servers[name]
    return {"mcpServers": filtered}, "filtered"


def translate_tools(tools):
    """Translate profile tools list to pi's --tools string. mcp:server/tool → mcp__server__tool.
    Returns None for absent/[all] (no --tools flag)."""
    if tools is None or tools == "all" or tools == ["all"]:
        return None
    if isinstance(tools, list):
        items = [str(t).strip() for t in tools if str(t).strip()]
    else:
        items = [t.strip() for t in str(tools).split(",") if t.strip()]
    out = []
    for t in items:
        if t.startswith("mcp:"):
            rest = t[4:]
            server, _, tool = rest.partition("/")
            if not server or not tool:
                raise ProfileError(f"malformed mcp tool reference: {t!r} (want mcp:server/tool)")
            norm = lambda s: re.sub(r"[-.]", "_", s)
            out.append(f"mcp__{norm(server)}__{norm(tool)}")
        else:
            out.append(t)
    return ",".join(out)


# ── Composer ──────────────────────────────────────────────────────────────

def compose_launch(name, cwd=None, model=None, workspace=None, extra_env=None, sandbox_override=None):
    """Compose the launch for a profile. Returns (argv, meta) — pure, no side effects
    other than writing the filtered MCP config temp file (path in meta['mcp_config']).

    argv is the full command line (starting with 'asb' when sandbox is on).
    meta: {workspace, cwd, mcp_config, model, agent, sandbox}
    """
    cwd = str(Path(cwd or os.getcwd()).resolve())
    fm, body, path = load_profile(name, cwd)
    extra_env = list(extra_env or [])

    model = model or fm.get("model")
    if not model:
        raise ProfileError(f"profile '{name}' has no model and no -m override given")

    sandbox = fm.get("sandbox", "on")
    if isinstance(sandbox, str):
        sandbox = {"on": sandbox.lower() in ("on", "true"), "workspace": None, "env": []}
    elif isinstance(sandbox, bool):
        sandbox = {"on": sandbox, "workspace": None, "env": []}
    else:
        sandbox = dict(sandbox)
        if "on" not in sandbox and "off" in sandbox:
            sandbox["on"] = bool(sandbox["off"])
        sandbox["on"] = bool(sandbox.get("on", True))
    if sandbox_override is not None:
        sandbox["on"] = sandbox_override

    # workspace
    ws = workspace
    if not ws:
        ws = sandbox.get("workspace")
    if not ws:
        ws = cwd
    ws = str(Path(ws).resolve())
    Path(ws).mkdir(parents=True, exist_ok=True)

    tools_str = translate_tools(fm.get("tools"))
    skills = resolve_skills(fm.get("skills"), cwd)
    extensions = resolve_extensions(fm.get("extensions"))
    mcp_config, mcp_mode = resolve_mcp(fm.get("mcp"))

    # The asb sandbox bind-mounts the workspace dir (read-write) at its host
    # path, but /tmp is a private tmpfs — host /tmp files are NOT visible
    # inside. So the system-prompt and filtered-MCP-config files must live in
    # the workspace dir to be readable by pi in-sandbox. They also keep the
    # pane-run command line short (a ~5KB inline body gets broken by the pane
    # terminal's line-length limit and corrupts the shell quoting).
    ra_dir = Path(ws) / ".runagent"
    ra_dir.mkdir(parents=True, exist_ok=True)
    sp_path = ra_dir / "sysprompt.md"
    sp_path.write_text(body, encoding="utf-8")

    mcp_config_path = None
    if mcp_mode == "filtered":
        mcp_config_path = ra_dir / "mcp.json"
        mcp_config_path.write_text(json.dumps(mcp_config, indent=2), encoding="utf-8")
        mcp_config_path = str(mcp_config_path)

    # NOTE: no positional args for pi — pi treats bare positionals as chat
    # messages. asb already receives the workspace as its own arg and the pane
    # cwd is the workspace.
    pi_argv = ["pi"]
    pi_argv += ["--model", model]
    # --append-system-prompt reads the file contents (pi --system-prompt takes
    # literal text only). The default pi system prompt is composed with the
    # profile body via append.
    pi_argv += ["--append-system-prompt", str(sp_path)]
    if tools_str:
        pi_argv += ["--tools", tools_str]
    if skills is None:
        pi_argv += ["--no-skills"]
    elif skills != "all":
        pi_argv += ["--no-skills"]
        for s in skills:
            pi_argv += ["--skill", s]
    if extensions is None:
        pi_argv += ["--no-extensions"]
    elif extensions != "all":
        pi_argv += ["--no-extensions"]
        for e in extensions:
            pi_argv += ["--extension", e]
    if mcp_mode == "filtered":
        pi_argv += ["--mcp-config", mcp_config_path]
    # mcp_mode == "all" → omit --mcp-config (pi uses global config)

    # env forwarding: profile sandbox.env names (values from host env) + explicit --env
    env_args = []
    for key in sandbox.get("env") or []:
        val = os.environ.get(key)
        if val is None:
            print(f"WARNING: sandbox env var '{key}' not set in host environment; skipping", file=sys.stderr)
            continue
        env_args.append(f"{key}={val}")
    env_args += extra_env

    if sandbox["on"]:
        argv = ["asb", "pi", ws]
        for ev in env_args:
            argv += ["--env", ev]
        argv += pi_argv[1:]
    else:
        argv = list(pi_argv)

    meta = {
        "agent": name,
        "model": model,
        "cwd": cwd,
        "workspace": ws,
        "mcp_config": mcp_config_path,
        "system_prompt_file": str(sp_path),
        "ra_dir": str(ra_dir),
        "sandbox": sandbox["on"],
        "profile_path": str(path),
        "command_string": shlex.join(argv),
    }
    return argv, meta


# ── CLI ───────────────────────────────────────────────────────────────────

def cmd_list(_args):
    rows = []
    for path in sorted(AGENT_DIR.glob("*.md")):
        if path.stem.endswith(".chain"):
            continue
        try:
            fm, body, _ = load_profile(path.stem)
        except ProfileError:
            continue
        sandbox = fm.get("sandbox", "on")
        sandbox_str = "off" if isinstance(sandbox, str) and sandbox.lower() in ("off", "false") else "on"
        tools = fm.get("tools", "all")
        tools_str = ",".join(tools) if isinstance(tools, list) else str(tools)
        mcp = fm.get("mcp", "none")
        mcp_str = ",".join(mcp) if isinstance(mcp, list) else str(mcp)
        rows.append([path.stem, fm.get("harness", "pi"), fm.get("model", "-"), sandbox_str,
                     tools_str[:40], mcp_str[:24]])
    headers = ["NAME", "HARNESS", "MODEL", "SANDBOX", "TOOLS", "MCP"]
    widths = [max(len(h), *(len(r[i]) for r in rows)) if rows else len(h) for i, h in enumerate(headers)]
    fmt = "  ".join(f"{{:<{w}}}" for w in widths)
    print(fmt.format(*headers))
    print(fmt.format(*("-" * w for w in widths)))
    for r in rows:
        print(fmt.format(*r))
    return 0


def cmd_compose(args):
    if not args:
        print("usage: agent_profile.py compose <agent> [--model M] [--workspace DIR] [--cwd DIR] [--env K=V]", file=sys.stderr)
        return 2
    name = args[0]
    kw = {}
    i = 1
    while i < len(args):
        a = args[i]
        if a == "--model":
            kw["model"] = args[i + 1]; i += 2
        elif a == "--workspace":
            kw["workspace"] = args[i + 1]; i += 2
        elif a == "--cwd":
            kw["cwd"] = args[i + 1]; i += 2
        elif a == "--env":
            kw.setdefault("extra_env", []).append(args[i + 1]); i += 2
        else:
            print(f"unknown option: {a}", file=sys.stderr)
            return 2
    argv, meta = compose_launch(name, **kw)
    print(json.dumps({"argv": argv, **meta}, indent=2))
    return 0


def main(argv):
    if not argv or argv[0] in ("-h", "--help"):
        print(__doc__)
        return 2
    cmd, rest = argv[0], argv[1:]
    try:
        if cmd == "list":
            return cmd_list(rest)
        if cmd == "compose":
            return cmd_compose(rest)
        print(f"unknown command: {cmd}", file=sys.stderr)
        return 2
    except ProfileError as e:
        print(f"ERROR: {e}", file=sys.stderr)
        return 12


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
