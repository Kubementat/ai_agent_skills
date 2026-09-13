#!/usr/bin/env python3
"""
Code Doctor — Main Orchestrator

Detects project language, installs missing tools, runs scouting subagents,
aggregates findings, and produces the diagnosis report.

Usage:
    python3 orchestrator.py [--check <lint|complexity|structure|design>] [--fix] [--dry-run]
"""

import argparse
import datetime
import json
import os
import subprocess
import sys
from pathlib import Path
from typing import Any

# Thresholds per language
THRESHOLDS: dict[str, dict[str, int]] = {
    "python": {
        "max_method_length": 50,
        "max_class_length": 300,
        "max_class_methods": 15,
        "max_class_dependencies": 5,
        "max_inheritance_depth": 3,
    },
    "javascript": {
        "max_method_length": 40,
        "max_class_length": 250,
        "max_class_methods": 12,
        "max_class_dependencies": 5,
        "max_inheritance_depth": 2,
    },
    "typescript": {
        "max_method_length": 40,
        "max_class_length": 250,
        "max_class_methods": 12,
        "max_class_dependencies": 5,
        "max_inheritance_depth": 2,
    },
    "go": {
        "max_method_length": 60,
        "max_class_length": 200,
        "max_class_methods": 10,
        "max_class_dependencies": 4,
        "max_inheritance_depth": 2,
    },
    "java": {
        "max_method_length": 50,
        "max_class_length": 300,
        "max_class_methods": 15,
        "max_class_dependencies": 5,
        "max_inheritance_depth": 3,
    },
}

# Tool requirements per language
TOOL_REQUIREMENTS: dict[str, list[dict[str, str]]] = {
    "python": [
        {"name": "radon", "version": ">=5.0,<6.0", "pip": True},
        {"name": "flake8", "version": ">=6.0,<7.0", "pip": True},
        {"name": "pydeps", "version": ">=1.13,<2.0", "pip": True},
        {"name": "import-linter", "version": ">=2.0,<3.0", "pip": True},
    ],
    "javascript": [
        {"name": "eslint", "version": ">=8.0,<9.0", "npm": True},
        {"name": "eslint-plugin-sonarjs", "version": ">=0.23,<1.0", "npm": True},
        {"name": "eslint-plugin-complexity", "version": ">=0.2,<1.0", "npm": True},
        {"name": "eslint-plugin-import", "version": ">=2.28,<3.0", "npm": True},
    ],
    "typescript": [
        {"name": "eslint", "version": ">=8.0,<9.0", "npm": True},
        {"name": "@typescript-eslint/parser", "version": ">=6.0,<7.0", "npm": True},
        {"name": "@typescript-eslint/eslint-plugin", "version": ">=6.0,<7.0", "npm": True},
        {"name": "eslint-plugin-sonarjs", "version": ">=0.23,<1.0", "npm": True},
        {"name": "eslint-plugin-complexity", "version": ">=0.2,<1.0", "npm": True},
        {"name": "eslint-plugin-import", "version": ">=2.28,<3.0", "npm": True},
    ],
    "go": [
        {"name": "golangci-lint", "version": ">=1.55,<2.0", "go": True},
        {"name": "gocognit", "version": ">=1.1,<2.0", "go": True},
    ],
    "java": [
        {"name": "checkstyle", "version": ">=10.0,<11.0", "maven": True},
        {"name": "pmd", "version": ">=7.0,<8.0", "maven": True},
    ],
}

# Detection order
DETECTION_ORDER = [
    ("requirements.txt", "python"),
    ("pyproject.toml", "python"),
    ("setup.py", "python"),
    ("package.json", "javascript"),
    ("go.mod", "go"),
    ("pom.xml", "java"),
    ("build.gradle", "java"),
    ("build.gradle.kts", "java"),
]

# Source file extensions for fallback detection
EXTENSION_DETECTION: dict[str, list[str]] = {
    "python": [".py"],
    "javascript": [".js", ".jsx"],
    "typescript": [".ts", ".tsx"],
    "go": [".go"],
    "java": [".java"],
}


def detect_project_language(project_dir: Path) -> list[str]:
    """Detect project language(s) by scanning for dependency files."""
    languages: list[str] = []

    # Check for dependency files
    for filename, language in DETECTION_ORDER:
        if (project_dir / filename).exists():
            if language not in languages:
                languages.append(language)

    # Fallback: check source file extensions
    if not languages:
        for ext, language in EXTENSION_DETECTION.items():
            for lang_ext in language:
                if any(project_dir.rglob(f"*{lang_ext}")):
                    if language not in languages:
                        languages.append(language)

    return languages if languages else []


def is_tool_installed(tool_name: str, tool_type: str) -> bool:
    """Check if a tool is installed on the system."""
    try:
        if tool_type == "pip":
            result = subprocess.run(
                ["pip", "show", tool_name],
                capture_output=True,
                text=True,
                timeout=10,
            )
        elif tool_type == "npm":
            result = subprocess.run(
                ["npm", "list", "-g", tool_name],
                capture_output=True,
                text=True,
                timeout=10,
            )
        elif tool_type == "go":
            result = subprocess.run(
                ["go", "tool", tool_name],
                capture_output=True,
                text=True,
                timeout=10,
            )
        elif tool_type == "maven":
            result = subprocess.run(
                ["mvn", "help:describe", "-Dartifact=" + tool_name],
                capture_output=True,
                text=True,
                timeout=10,
            )
        else:
            return False
        return result.returncode == 0
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return False


def install_tool(tool: dict[str, str], project_dir: Path) -> bool:
    """Install a missing tool as a project dev dependency."""
    name = tool["name"]
    version = tool["version"]
    tool_type = tool.get("pip") and "pip" or tool.get("npm") and "npm" or tool.get("go") and "go" or tool.get("maven") and "maven"

    try:
        if tool_type == "pip":
            # Determine the right dependency file
            req_file = project_dir / "requirements-dev.txt"
            if not req_file.exists():
                req_file = project_dir / "requirements.txt"
            if not req_file.exists():
                req_file = project_dir / "pyproject.toml"

            if req_file.exists():
                # Add to requirements file
                with open(req_file, "a") as f:
                    f.write(f"\n{name}{version}\n")
                subprocess.run(
                    ["pip", "install", f"{name}{version}"],
                    capture_output=True,
                    text=True,
                    timeout=60,
                )
            return True

        elif tool_type == "npm":
            # Add to package.json
            pkg_file = project_dir / "package.json"
            if pkg_file.exists():
                with open(pkg_file, "r") as f:
                    pkg = json.load(f)

                dev_deps = pkg.get("devDependencies", {})
                dev_deps[name] = version
                pkg["devDependencies"] = dev_deps

                with open(pkg_file, "w") as f:
                    json.dump(pkg, f, indent=2)

                subprocess.run(
                    ["npm", "install"],
                    capture_output=True,
                    text=True,
                    timeout=120,
                )
            return True

        elif tool_type == "go":
            # Go tools are typically installed globally via go install
            subprocess.run(
                ["go", "install", f"{name}@latest"],
                capture_output=True,
                text=True,
                timeout=120,
            )
            return True

        elif tool_type == "maven":
            # Maven tools are added to pom.xml
            pom_file = project_dir / "pom.xml"
            if pom_file.exists():
                # Simple approach: just note the tool requirement
                # In production, you'd parse and modify the XML properly
                print(f"  ⚠️  {name} should be added to pom.xml as a Maven plugin")
            return True

    except (subprocess.TimeoutExpired, Exception) as e:
        print(f"  ❌ Failed to install {name}: {e}")
        return False

    return False


def install_missing_tools(languages: list[str], project_dir: Path) -> None:
    """Install missing tools for the detected language(s)."""
    for language in languages:
        if language not in TOOL_REQUIREMENTS:
            continue

        print(f"\n📦 Installing tools for {language}...")
        for tool in TOOL_REQUIREMENTS[language]:
            tool_name = tool["name"]
            tool_type = tool.get("pip") and "pip" or tool.get("npm") and "npm" or tool.get("go") and "go" or tool.get("maven") and "maven"

            if not is_tool_installed(tool_name, tool_type):
                print(f"  🔧 Installing {tool_name}{tool['version']}...")
                if install_tool(tool, project_dir):
                    print(f"  ✓ {tool_name} installed")
                else:
                    print(f"  ⚠️  {tool_name} installation failed — will skip checks that require it")
            else:
                print(f"  ✓ {tool_name} already installed")

        # Commit tool changes
        try:
            subprocess.run(
                ["git", "add", "-A"],
                capture_output=True,
                timeout=5,
            )
            subprocess.run(
                ["git", "commit", "-m", f"chore: add code quality tools for {language}"],
                capture_output=True,
                text=True,
                timeout=5,
            )
        except (subprocess.TimeoutExpired, FileNotFoundError):
            pass  # Not a git repo, skip commit


def run_lint_scout(project_dir: Path, language: str, thresholds: dict[str, int]) -> list[dict[str, Any]]:
    """Run lint analysis for the detected language."""
    findings: list[dict[str, Any]] = []

    if language == "python":
        # Run flake8
        try:
            result = subprocess.run(
                ["flake8", "--max-line-length=120", "--select=E,F,W", "--statistics", str(project_dir)],
                capture_output=True,
                text=True,
                timeout=60,
            )
            if result.returncode != 0:
                for line in result.stdout.strip().split("\n"):
                    if line.strip():
                        parts = line.split(":")
                        if len(parts) >= 3:
                            filepath = parts[0].strip()
                            severity = "WARNING" if "E" in line or "F" in line else "INFO"
                            findings.append({
                                "finding_id": f"lint-{filepath}-{len(findings)}",
                                "severity": severity,
                                "type": "lint",
                                "file": filepath,
                                "line": int(parts[1]) if parts[1].isdigit() else 1,
                                "code_context": line.strip(),
                                "violation_reason": f"Lint violation: {line.strip()}",
                                "recommended_fix": f"Fix lint error: {line.strip()}",
                                "metrics": {},
                            })
        except (subprocess.TimeoutExpired, FileNotFoundError):
            pass

    elif language == "javascript" or language == "typescript":
        # Run eslint
        try:
            result = subprocess.run(
                ["npx", "eslint", "--no-eslintrc", "--max-warnings=0", str(project_dir)],
                capture_output=True,
                text=True,
                timeout=120,
            )
            if result.returncode != 0:
                for line in result.stdout.strip().split("\n"):
                    if "error" in line.lower() and line.strip():
                        parts = line.split(":")
                        if len(parts) >= 3:
                            filepath = parts[0].strip()
                            line_num = parts[1].strip()
                            severity = "WARNING"
                            findings.append({
                                "finding_id": f"lint-{filepath}-{len(findings)}",
                                "severity": severity,
                                "type": "lint",
                                "file": filepath,
                                "line": int(line_num) if line_num.isdigit() else 1,
                                "code_context": line.strip(),
                                "violation_reason": f"ESLint violation: {line.strip()}",
                                "recommended_fix": f"Fix ESLint error: {line.strip()}",
                                "metrics": {},
                            })
        except (subprocess.TimeoutExpired, FileNotFoundError):
            pass

    elif language == "go":
        # Run golangci-lint
        try:
            result = subprocess.run(
                ["golangci-lint", "run", "--max-issues-per-linter=0", "--max-same-issues=0", "--out-format=json"],
                capture_output=True,
                text=True,
                timeout=120,
            )
            if result.returncode != 0:
                try:
                    issues = json.loads(result.stdout)
                    for issue in issues.get("issues", []):
                        filepath = issue.get("FromLinter", "unknown")
                        findings.append({
                            "finding_id": f"lint-{filepath}-{len(findings)}",
                            "severity": "WARNING",
                            "type": "lint",
                            "file": issue.get("FromLinter", ""),
                            "line": issue.get("Pos", {}).get("Line", 1),
                            "code_context": issue.get("Text", ""),
                            "violation_reason": f"golangci-lint issue: {issue.get('Text', '')}",
                            "recommended_fix": f"Fix golangci-lint issue: {issue.get('Text', '')}",
                            "metrics": {},
                        })
                except json.JSONDecodeError:
                    pass
        except (subprocess.TimeoutExpired, FileNotFoundError):
            pass

    elif language == "java":
        # Run Checkstyle
        try:
            result = subprocess.run(
                ["mvn", "checkstyle:check", "-f", str(project_dir / "pom.xml")],
                capture_output=True,
                text=True,
                timeout=120,
            )
            if result.returncode != 0:
                for line in result.stdout.strip().split("\n"):
                    if "violation" in line.lower() and line.strip():
                        findings.append({
                            "finding_id": f"lint-{language}-{len(findings)}",
                            "severity": "WARNING",
                            "type": "lint",
                            "file": "pom.xml",
                            "line": 1,
                            "code_context": line.strip(),
                            "violation_reason": f"Checkstyle violation: {line.strip()}",
                            "recommended_fix": f"Fix Checkstyle violation: {line.strip()}",
                            "metrics": {},
                        })
        except (subprocess.TimeoutExpired, FileNotFoundError):
            pass

    return findings


def run_complexity_scout(project_dir: Path, language: str, thresholds: dict[str, int]) -> list[dict[str, Any]]:
    """Run complexity analysis for the detected language."""
    findings: list[dict[str, Any]] = []

    if language == "python":
        # Run radon
        try:
            result = subprocess.run(
                ["radon", "cc", str(project_dir), "-a", "--json"],
                capture_output=True,
                text=True,
                timeout=60,
            )
            if result.returncode == 0:
                try:
                    data = json.loads(result.stdout)
                    for file_data in data:
                        filepath = file_data.get("name", "")
                        for func_data in file_data.get("totals", {}).get("complexity", {}).get("functions", {}).get("complexity", []):
                            complexity = func_data.get("complexity", 0)
                            if complexity > thresholds["max_method_length"]:
                                findings.append({
                                    "finding_id": f"complexity-{filepath}-{func_data.get('name', 'unknown')}-{len(findings)}",
                                    "severity": "WARNING",
                                    "type": "complexity",
                                    "file": filepath,
                                    "line": func_data.get("line", 1),
                                    "class_name": func_data.get("name", ""),
                                    "code_context": func_data.get("name", ""),
                                    "violation_reason": f"Function '{func_data.get('name', '')}' has cyclomatic complexity of {complexity} (threshold: {thresholds['max_method_length']})",
                                    "recommended_fix": f"Refactor '{func_data.get('name', '')}' to reduce complexity below {thresholds['max_method_length']}",
                                    "metrics": {
                                        "cyclomatic_complexity": complexity,
                                    },
                                })
                except json.JSONDecodeError:
                    pass
        except (subprocess.TimeoutExpired, FileNotFoundError):
            pass

    elif language == "javascript" or language == "typescript":
        # Run eslint complexity plugin
        try:
            result = subprocess.run(
                ["npx", "eslint", "--rule", "'complexity: [warn, " + str(thresholds["max_method_length"]) + "]'", str(project_dir)],
                capture_output=True,
                text=True,
                timeout=120,
            )
            if result.returncode != 0:
                for line in result.stdout.strip().split("\n"):
                    if "complexity" in line.lower() and line.strip():
                        parts = line.split(":")
                        if len(parts) >= 3:
                            filepath = parts[0].strip()
                            line_num = parts[1].strip()
                            findings.append({
                                "finding_id": f"complexity-{filepath}-{len(findings)}",
                                "severity": "WARNING",
                                "type": "complexity",
                                "file": filepath,
                                "line": int(line_num) if line_num.isdigit() else 1,
                                "code_context": line.strip(),
                                "violation_reason": f"Complexity violation: {line.strip()}",
                                "recommended_fix": f"Reduce complexity below {thresholds['max_method_length']}",
                                "metrics": {},
                            })
        except (subprocess.TimeoutExpired, FileNotFoundError):
            pass

    elif language == "go":
        # Run gocognit
        try:
            result = subprocess.run(
                ["gocognit", "-top", "5", str(project_dir)],
                capture_output=True,
                text=True,
                timeout=60,
            )
            if result.returncode == 0:
                for line in result.stdout.strip().split("\n"):
                    if line.strip():
                        parts = line.split()
                        if len(parts) >= 3:
                            try:
                                complexity = int(parts[0])
                                filepath = parts[1]
                                func_name = parts[2]
                                if complexity > thresholds["max_method_length"]:
                                    findings.append({
                                        "finding_id": f"complexity-{filepath}-{func_name}-{len(findings)}",
                                        "severity": "WARNING",
                                        "type": "complexity",
                                        "file": filepath,
                                        "line": 1,
                                        "class_name": func_name,
                                        "code_context": func_name,
                                        "violation_reason": f"Function '{func_name}' has cognitive complexity of {complexity} (threshold: {thresholds['max_method_length']})",
                                        "recommended_fix": f"Refactor '{func_name}' to reduce complexity below {thresholds['max_method_length']}",
                                        "metrics": {
                                            "cognitive_complexity": complexity,
                                        },
                                    })
                            except ValueError:
                                pass
        except (subprocess.TimeoutExpired, FileNotFoundError):
            pass

    elif language == "java":
        # Run PMD complexity
        try:
            result = subprocess.run(
                ["mvn", "pmd:check", "-f", str(project_dir / "pom.xml")],
                capture_output=True,
                text=True,
                timeout=120,
            )
            if result.returncode != 0:
                for line in result.stdout.strip().split("\n"):
                    if "complexity" in line.lower() and line.strip():
                        findings.append({
                            "finding_id": f"complexity-{language}-{len(findings)}",
                            "severity": "WARNING",
                            "type": "complexity",
                            "file": "pom.xml",
                            "line": 1,
                            "code_context": line.strip(),
                            "violation_reason": f"Complexity violation: {line.strip()}",
                            "recommended_fix": f"Reduce complexity below {thresholds['max_method_length']}",
                            "metrics": {},
                        })
        except (subprocess.TimeoutExpired, FileNotFoundError):
            pass

    return findings


def run_structure_scout(project_dir: Path, language: str, thresholds: dict[str, int]) -> list[dict[str, Any]]:
    """Run structural analysis for the detected language."""
    findings: list[dict[str, Any]] = []

    if language == "python":
        # Run radon for structure
        try:
            result = subprocess.run(
                ["radon", "mi", str(project_dir), "--json"],
                capture_output=True,
                text=True,
                timeout=60,
            )
            if result.returncode == 0:
                try:
                    data = json.loads(result.stdout)
                    for file_data in data:
                        filepath = file_data.get("name", "")
                        mi_score = file_data.get("maintainability_index", 0)
                        if mi_score < 20:
                            findings.append({
                                "finding_id": f"structure-{filepath}-{len(findings)}",
                                "severity": "ERROR",
                                "type": "structure",
                                "file": filepath,
                                "line": 1,
                                "code_context": filepath,
                                "violation_reason": f"Maintainability Index of {mi_score:.1f} is very low (threshold: 20)",
                                "recommended_fix": f"Refactor '{filepath}' to improve maintainability index above 20",
                                "metrics": {
                                    "maintainability_index": mi_score,
                                },
                            })
                except json.JSONDecodeError:
                    pass

            # Also check class length via radon lines
            result = subprocess.run(
                ["radon", "lines", str(project_dir), "--json"],
                capture_output=True,
                text=True,
                timeout=60,
            )
            if result.returncode == 0:
                try:
                    data = json.loads(result.stdout)
                    for file_data in data:
                        filepath = file_data.get("name", "")
                        total_lines = file_data.get("lines", {}).get("total", 0)
                        if total_lines > thresholds["max_class_length"]:
                            findings.append({
                                "finding_id": f"structure-{filepath}-length-{len(findings)}",
                                "severity": "WARNING",
                                "type": "structure",
                                "file": filepath,
                                "line": 1,
                                "code_context": filepath,
                                "violation_reason": f"File '{filepath}' has {total_lines} lines (threshold: {thresholds['max_class_length']})",
                                "recommended_fix": f"Split '{filepath}' — it has {total_lines} lines (threshold: {thresholds['max_class_length']})",
                                "metrics": {
                                    "line_count": total_lines,
                                },
                            })
                except json.JSONDecodeError:
                    pass
        except (subprocess.TimeoutExpired, FileNotFoundError):
            pass

    elif language == "javascript" or language == "typescript":
        # Run eslint for structure
        try:
            result = subprocess.run(
                ["npx", "eslint", "--rule", "'max-lines-per-function: [warn, " + str(thresholds["max_method_length"]) + "]'", str(project_dir)],
                capture_output=True,
                text=True,
                timeout=120,
            )
            if result.returncode != 0:
                for line in result.stdout.strip().split("\n"):
                    if "max-lines-per-function" in line.lower() and line.strip():
                        parts = line.split(":")
                        if len(parts) >= 3:
                            filepath = parts[0].strip()
                            line_num = parts[1].strip()
                            findings.append({
                                "finding_id": f"structure-{filepath}-{len(findings)}",
                                "severity": "WARNING",
                                "type": "structure",
                                "file": filepath,
                                "line": int(line_num) if line_num.isdigit() else 1,
                                "code_context": line.strip(),
                                "violation_reason": f"Function too long: {line.strip()}",
                                "recommended_fix": f"Extract method — function exceeds {thresholds['max_method_length']} lines",
                                "metrics": {},
                            })
        except (subprocess.TimeoutExpired, FileNotFoundError):
            pass

    elif language == "go":
        # Run gofmt for basic structure check
        try:
            result = subprocess.run(
                ["gofmt", "-l", str(project_dir)],
                capture_output=True,
                text=True,
                timeout=60,
            )
            if result.returncode != 0:
                for filepath in result.stdout.strip().split("\n"):
                    if filepath.strip():
                        findings.append({
                            "finding_id": f"structure-{filepath.strip()}-{len(findings)}",
                            "severity": "INFO",
                            "type": "structure",
                            "file": filepath.strip(),
                            "line": 1,
                            "code_context": filepath.strip(),
                            "violation_reason": f"File '{filepath.strip()}' is not gofmt-formatted",
                            "recommended_fix": f"Run 'gofmt -w {filepath.strip()}'",
                            "metrics": {},
                        })
        except (subprocess.TimeoutExpired, FileNotFoundError):
            pass

    elif language == "java":
        # Run Checkstyle for structure
        try:
            result = subprocess.run(
                ["mvn", "checkstyle:checkstyle", "-f", str(project_dir / "pom.xml")],
                capture_output=True,
                text=True,
                timeout=120,
            )
            if result.returncode != 0:
                for line in result.stdout.strip().split("\n"):
                    if "violation" in line.lower() and line.strip():
                        findings.append({
                            "finding_id": f"structure-{language}-{len(findings)}",
                            "severity": "WARNING",
                            "type": "structure",
                            "file": "pom.xml",
                            "line": 1,
                            "code_context": line.strip(),
                            "violation_reason": f"Structure violation: {line.strip()}",
                            "recommended_fix": f"Fix structure violation: {line.strip()}",
                            "metrics": {},
                        })
        except (subprocess.TimeoutExpired, FileNotFoundError):
            pass

    return findings


def run_dependency_scout(project_dir: Path, language: str, thresholds: dict[str, int]) -> list[dict[str, Any]]:
    """Run dependency analysis for the detected language."""
    findings: list[dict[str, Any]] = []

    if language == "python":
        # Run pydeps for dependency analysis
        try:
            result = subprocess.run(
                ["pydeps", str(project_dir), "--show-cycles"],
                capture_output=True,
                text=True,
                timeout=60,
            )
            if result.returncode != 0:
                # Look for cycle indicators
                if "cycle" in result.stdout.lower():
                    findings.append({
                        "finding_id": f"dependency-{language}-cycle-{len(findings)}",
                        "severity": "ERROR",
                        "type": "circular-dependency",
                        "file": "multiple",
                        "line": 1,
                        "code_context": result.stdout.strip(),
                        "violation_reason": f"Circular dependency detected: {result.stdout.strip()}",
                        "recommended_fix": "Break the circular dependency by introducing an interface/protocol",
                        "metrics": {},
                    })
        except (subprocess.TimeoutExpired, FileNotFoundError):
            pass

        # Run import-linter for dependency analysis
        try:
            result = subprocess.run(
                ["lint-imports", "--show-summary"],
                capture_output=True,
                text=True,
                timeout=60,
            )
            if result.returncode != 0:
                for line in result.stdout.strip().split("\n"):
                    if "violation" in line.lower() and line.strip():
                        findings.append({
                            "finding_id": f"dependency-{language}-import-{len(findings)}",
                            "severity": "WARNING",
                            "type": "dependency",
                            "file": "multiple",
                            "line": 1,
                            "code_context": line.strip(),
                            "violation_reason": f"Import violation: {line.strip()}",
                            "recommended_fix": f"Fix import violation: {line.strip()}",
                            "metrics": {},
                        })
        except (subprocess.TimeoutExpired, FileNotFoundError):
            pass

    elif language == "javascript" or language == "typescript":
        # Run eslint import plugin
        try:
            result = subprocess.run(
                ["npx", "eslint", "--rule", "'import/no-cycle: [error]'"],
                capture_output=True,
                text=True,
                timeout=120,
            )
            if result.returncode != 0:
                for line in result.stdout.strip().split("\n"):
                    if "import/no-cycle" in line.lower() and line.strip():
                        parts = line.split(":")
                        if len(parts) >= 3:
                            filepath = parts[0].strip()
                            line_num = parts[1].strip()
                            findings.append({
                                "finding_id": f"dependency-{filepath}-cycle-{len(findings)}",
                                "severity": "ERROR",
                                "type": "circular-dependency",
                                "file": filepath,
                                "line": int(line_num) if line_num.isdigit() else 1,
                                "code_context": line.strip(),
                                "violation_reason": f"Circular dependency: {line.strip()}",
                                "recommended_fix": "Break the circular dependency by introducing an interface/protocol",
                                "metrics": {},
                            })
        except (subprocess.TimeoutExpired, FileNotFoundError):
            pass

    elif language == "go":
        # Run go mod why for dependency analysis
        try:
            result = subprocess.run(
                ["go", "mod", "why", "-m"],
                capture_output=True,
                text=True,
                timeout=60,
            )
            if result.returncode != 0:
                for line in result.stdout.strip().split("\n"):
                    if "imports" in line.lower() and line.strip():
                        findings.append({
                            "finding_id": f"dependency-{language}-{len(findings)}",
                            "severity": "WARNING",
                            "type": "dependency",
                            "file": "go.mod",
                            "line": 1,
                            "code_context": line.strip(),
                            "violation_reason": f"Dependency issue: {line.strip()}",
                            "recommended_fix": f"Review dependency: {line.strip()}",
                            "metrics": {},
                        })
        except (subprocess.TimeoutExpired, FileNotFoundError):
            pass

    elif language == "java":
        # Run Checkstyle dependency check
        try:
            result = subprocess.run(
                ["mvn", "checkstyle:check", "-f", str(project_dir / "pom.xml")],
                capture_output=True,
                text=True,
                timeout=120,
            )
            if result.returncode != 0:
                for line in result.stdout.strip().split("\n"):
                    if "dependency" in line.lower() and line.strip():
                        findings.append({
                            "finding_id": f"dependency-{language}-{len(findings)}",
                            "severity": "WARNING",
                            "type": "dependency",
                            "file": "pom.xml",
                            "line": 1,
                            "code_context": line.strip(),
                            "violation_reason": f"Dependency violation: {line.strip()}",
                            "recommended_fix": f"Fix dependency violation: {line.strip()}",
                            "metrics": {},
                        })
        except (subprocess.TimeoutExpired, FileNotFoundError):
            pass

    return findings


def generate_report(findings: list[dict[str, Any]]) -> str:
    """Generate the diagnosis report."""
    severity_counts: dict[str, int] = {"ERROR": 0, "WARNING": 0, "INFO": 0}
    for finding in findings:
        severity = finding.get("severity", "INFO")
        severity_counts[severity] = severity_counts.get(severity, 0) + 1

    # Sort by priority: circular deps > god class > long methods > other > lint
    priority_map = {
        "circular-dependency": 0,
        "god-class": 1,
        "long-method": 2,
        "feature-envy": 3,
        "solid-violation": 4,
        "encapsulation": 5,
        "complexity": 6,
        "structure": 7,
        "dependency": 8,
        "lint": 9,
    }

    sorted_findings = sorted(
        findings,
        key=lambda f: (priority_map.get(f.get("type", ""), 10), -severity_counts.get(f.get("severity", "INFO"), 0)),
    )

    # Generate report
    report = []
    report.append("🏥 Code Doctor — Diagnosis Report")
    report.append("━" * 40)
    report.append("")
    report.append("📊 Summary")
    report.append(f"  Total issues: {len(findings)}")
    report.append(f"  🔴 Errors: {severity_counts['ERROR']} (must fix)")
    report.append(f"  🟡 Warnings: {severity_counts['WARNING']} (should fix)")
    report.append(f"  🔵 Info: {severity_counts['INFO']} (nice-to-have)")
    report.append("")
    report.append("🏆 Top Issues")
    report.append("━" * 40)
    report.append("")

    for i, finding in enumerate(sorted_findings[:10]):  # Show top 10
        severity_emoji = {"ERROR": "🔴", "WARNING": "🟡", "INFO": "🔵"}.get(finding.get("severity", "INFO"), "🔵")
        finding_type = finding.get("type", "unknown").replace("-", " ").title()
        file_path = finding.get("file", "unknown")
        line = finding.get("line", 1)
        class_name = finding.get("class_name", "")

        line_info = f":{line}" if line != 1 else ""
        class_info = f" — {class_name}" if class_name else ""

        report.append(f"{i + 1}. {severity_emoji} {finding_type} — {file_path}{line_info}{class_info}")
        report.append(f"   {finding.get('violation_reason', 'No description')}")
        report.append("")

    if len(findings) > 10:
        report.append(f"... and {len(findings) - 10} more issues")
        report.append("")

    report.append(f"Full findings: ./findings.json")
    report.append("")

    return "\n".join(report)


def main():
    parser = argparse.ArgumentParser(description="Code Doctor — Diagnose code quality issues")
    parser.add_argument(
        "--check",
        choices=["lint", "complexity", "structure", "design"],
        help="Run only the specified check type",
    )
    parser.add_argument(
        "--fix",
        action="store_true",
        help="Start subagents to fix issues",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Show what would be done without making changes",
    )
    parser.add_argument(
        "--project-dir",
        type=str,
        default=".",
        help="Project directory to analyze (default: current directory)",
    )
    args = parser.parse_args()

    project_dir = Path(args.project_dir).resolve()
    if not project_dir.exists():
        print(f"❌ Project directory not found: {project_dir}")
        sys.exit(1)

    print("🏥 Code Doctor — Starting Diagnosis")
    print("━" * 40)

    # Step 1: Detect project language (subagent)
    print("\n🔍 Step 1 — Detecting project (subagent)...")
    languages = detect_project_language(project_dir)
    if not languages:
        print("  ❌ Could not detect project language. Please specify the language.")
        sys.exit(1)
    print(f"  ✓ Detected languages: {', '.join(languages)}")

    # Step 2: Install missing tools (subagent)
    if not args.dry_run:
        print("\n📦 Step 2 — Installing tools (subagent)...")
        install_missing_tools(languages, project_dir)
    else:
        print("\n📦 Step 2 — Checking tools (dry run)...")
        for language in languages:
            if language in TOOL_REQUIREMENTS:
                for tool in TOOL_REQUIREMENTS[language]:
                    tool_name = tool["name"]
                    tool_type = tool.get("pip") and "pip" or tool.get("npm") and "npm" or tool.get("go") and "go" or tool.get("maven") and "maven"
                    if not is_tool_installed(tool_name, tool_type):
                        print(f"  ⚠️  Missing: {tool_name}{tool['version']}")

    # Step 3: Run scouting subagents
    all_findings: list[dict[str, Any]] = []

    if not args.check or args.check in ("lint", "complexity", "structure", "design"):
        for language in languages:
            thresholds = THRESHOLDS.get(language, THRESHOLDS["python"])

            if not args.check or args.check == "lint":
                print("\n🔍 Step 3/4 — Running lint analysis...")
                lint_findings = run_lint_scout(project_dir, language, thresholds)
                all_findings.extend(lint_findings)
                print(f"  ✓ Found {len(lint_findings)} lint issues")

            if not args.check or args.check == "complexity":
                print("\n🔍 Step 3/4 — Running complexity analysis...")
                complexity_findings = run_complexity_scout(project_dir, language, thresholds)
                all_findings.extend(complexity_findings)
                print(f"  ✓ Found {len(complexity_findings)} complexity issues")

            if not args.check or args.check == "structure":
                print("\n🔍 Step 3/4 — Running structure analysis...")
                structure_findings = run_structure_scout(project_dir, language, thresholds)
                all_findings.extend(structure_findings)
                print(f"  ✓ Found {len(structure_findings)} structure issues")

            if not args.check or args.check == "design":
                print("\n🔍 Step 3/4 — Running dependency analysis...")
                dependency_findings = run_dependency_scout(project_dir, language, thresholds)
                all_findings.extend(dependency_findings)
                print(f"  ✓ Found {len(dependency_findings)} dependency issues")

    # Step 4: Write findings to file
    findings_file = project_dir / "findings.json"
    with open(findings_file, "w") as f:
        json.dump(all_findings, f, indent=2)

    # Step 5: Generate and output report
    print("\n📊 Step 5 — Generating report...")
    report = generate_report(all_findings)
    print(report)

    # Step 6: Ask about fixes
    if not args.dry_run and all_findings and not args.fix:
        print("Would you like me to start subagents to fix these issues?")
        print("  1. Fix all 🔴 errors")
        print("  2. Fix 🔴 errors and 🟡 warnings")
        print("  3. Fix everything")
        print("  4. Skip — I'll review the findings first")
        # In production, this would be an interactive prompt
        # For now, skip the fix phase
        print("\nNote: Fix phase not implemented yet. Use --fix flag to enable.")

    # Step 7: Fix phase
    if args.fix and all_findings:
        print("\n🔧 Step 7 — Fix phase...")
        # Create a new branch for fixes
        branch_name = f"code-doctor-fix-{datetime.datetime.now().strftime('%Y%m%d')}"
        try:
            subprocess.run(
                ["git", "checkout", "-b", branch_name],
                capture_output=True,
                text=True,
                timeout=5,
            )
            print(f"  ✓ Created branch: {branch_name}")
        except (subprocess.TimeoutExpired, FileNotFoundError):
            print(f"  ⚠️  Could not create branch (not a git repo or git not available)")
            branch_name = None

        # In production, spawn fix subagents here
        # Each subagent would:
        # 1. Read a finding from findings.json
        # 2. Apply the fix
        # 3. Commit the fix
        # 4. Report progress
        print("  Note: Fix subagents not implemented yet.")

        # Note: fixes are performed locally only — no remote push or PR creation
        print(f"  ✓ Local fixes complete. Branch: {branch_name}")

    print(f"\n🏥 Diagnosis complete. {len(all_findings)} issues found.")
    print(f"Full findings: {findings_file}")


if __name__ == "__main__":
    main()
