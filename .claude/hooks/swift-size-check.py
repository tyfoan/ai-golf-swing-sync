#!/usr/bin/env python3
"""PostToolUse hook: warn when an edited Swift file exceeds CLAUDE.md size limits.

Limits (from CLAUDE.md):
  classes/structs/enums/actors <= 200 lines
  func bodies <= 15 lines
  func params <= 5

Output goes to stdout, which Claude Code feeds back into the model's context.
Stays silent on clean files (no noise).
"""
import json
import re
import sys


def parse_params(raw: str) -> list[str]:
    raw = raw.strip()
    if not raw:
        return []
    return [p for p in re.split(r",(?![^<]*>)", raw) if p.strip()]


TYPE_RE = re.compile(
    r"^\s*(?:public\s+|private\s+|internal\s+|fileprivate\s+|final\s+|open\s+|@[\w(),\s]+\s+)*"
    r"(class|struct|enum|actor)\s+(\w+)"
)
FUNC_RE = re.compile(
    r"^\s*(?:public\s+|private\s+|internal\s+|fileprivate\s+|static\s+|class\s+|final\s+|"
    r"override\s+|mutating\s+|@[\w(),\s]+\s+)*func\s+(\w+)\s*(?:<[^>]*>)?\s*\(([^)]*)\)"
)


def lint(path: str) -> list[str]:
    try:
        src = open(path).read().splitlines()
    except OSError:
        return []

    viol: list[str] = []
    depth = 0
    stack: list[tuple[str, str, int, int]] = []  # (kind, name, start_line, expected_close_depth)

    for idx, line in enumerate(src):
        pre = depth
        m = TYPE_RE.match(line)
        if m and "{" in line:
            stack.append(("type", f"{m.group(1)} {m.group(2)}", idx + 1, pre))
        else:
            m = FUNC_RE.match(line)
            if m:
                params = parse_params(m.group(2))
                if len(params) > 5:
                    viol.append(f"func {m.group(1)} has {len(params)} params (>5) at L{idx + 1}")
                if "{" in line:
                    stack.append(("func", m.group(1), idx + 1, pre))

        depth += line.count("{") - line.count("}")

        while stack and depth <= stack[-1][3]:
            kind, name, start, _ = stack.pop()
            size = (idx + 1) - start
            if kind == "type" and size > 200:
                viol.append(f"{name} is {size} lines (>200) at L{start}-{idx + 1}")
            elif kind == "func" and (size - 1) > 15:
                viol.append(f"func {name} body is {size - 1} lines (>15) at L{start}-{idx + 1}")

    return viol


def main() -> int:
    try:
        data = json.load(sys.stdin)
    except json.JSONDecodeError:
        return 0
    tool_input = data.get("tool_input") or {}
    tool_response = data.get("tool_response") or {}
    path = tool_input.get("file_path") or tool_response.get("filePath") or ""
    if not path.endswith(".swift"):
        return 0

    viol = lint(path)
    if viol:
        print(f"⚠️  CLAUDE.md size limits exceeded in {path}:")
        for v in viol:
            print(f"  - {v}")
        print("Consider extracting helpers or splitting the type (Sandi Metz: small things, single responsibility).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
