#!/usr/bin/env python3
"""Validate YAML frontmatter on agent and skill markdown files.

Schemas:
    agent (agents/*.md):       name, description, model
    skill (skills/*/SKILL.md): name, description
"""

from __future__ import annotations

import sys
from pathlib import Path

import yaml

KINDS = {
    "agent": {
        "pattern": "agents/*.md",
        "required": ("name", "description", "model"),
    },
    "skill": {
        "pattern": "skills/*/SKILL.md",
        "required": ("name", "description"),
    },
}


def split_frontmatter(text: str) -> str | None:
    if not text.startswith("---\n"):
        return None
    end = text.find("\n---\n", 4)
    if end == -1:
        if text.rstrip().endswith("\n---"):
            end = text.rstrip().rfind("\n---")
        else:
            return None
    return text[4:end]


def check(path: Path, required: tuple[str, ...]) -> list[str]:
    errors: list[str] = []
    text = path.read_text(encoding="utf-8")
    fm = split_frontmatter(text)
    if fm is None:
        errors.append(f"{path}: missing YAML frontmatter block")
        return errors
    try:
        data = yaml.safe_load(fm)
    except yaml.YAMLError as exc:
        errors.append(f"{path}: invalid YAML frontmatter: {exc}")
        return errors
    if not isinstance(data, dict):
        errors.append(f"{path}: frontmatter is not a mapping")
        return errors
    for field in required:
        if field not in data or data[field] in (None, ""):
            errors.append(f"{path}: missing required field '{field}'")
    return errors


def main() -> int:
    all_errors: list[str] = []
    total = 0
    root = Path()
    for cfg in KINDS.values():
        paths = sorted(root.glob(cfg["pattern"]))
        total += len(paths)
        for path in paths:
            all_errors.extend(check(path, cfg["required"]))
    if all_errors:
        for err in all_errors:
            print(err, file=sys.stderr)
        print(f"\n{len(all_errors)} frontmatter issue(s) across {total} file(s)", file=sys.stderr)
        return 1
    print(f"ok: {total} file(s) validated")
    return 0


if __name__ == "__main__":
    sys.exit(main())
