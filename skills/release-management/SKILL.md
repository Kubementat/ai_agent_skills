---
name: release-management
description: "Cut a release with an annotated git tag: tests green, changelog, version bump, tag, fast-forward main, push with tags. Use for tag-based releases."
---

A release = one commit, tagged `vX.Y.Z` (annotated), present on `main`. Tag + changelog + version bump in the same commit. Untagged version ≠ release. Never move a pushed tag.

Semver: MAJOR breaking contract/CLI, MINOR new flag/subcommand/error code/key, PATCH fixes only.

```bash
uv run tests/unit_test.py && uv run tests/integration_test.py   # 1. both suites green
# 2. changelog: [Unreleased] entries -> ## [X.Y.Z] - YYYY-MM-DD, leave empty [Unreleased]
# 3. version in pyproject.toml, then uv sync
git commit -am "release vX.Y.Z"
git tag -a vX.Y.Z -m "release vX.Y.Z"                            # 4. tag on develop
git branch -f main develop                                       # 5. ff main, no checkout churn
git push remote main develop --follow-tags                       # all remotes, same command shape
```

Changelog wording: reuse the feature commits' text.
