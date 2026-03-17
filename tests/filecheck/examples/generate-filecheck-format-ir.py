#!/usr/bin/env python3
"""Generate // CHECK directives from ccpp pipeline MLIR IR output.

Reads MLIR IR produced by the ccpp frontend or optimizer from stdin (or a
file) and prints a set of filecheck directives suitable for pasting into a
``.mlir`` test file.

Directive mapping
-----------------
- Lines matching key structural boundaries become ``// CHECK-LABEL:`` so that
  filecheck can seek forward to them independently:

    ``builtin.module @<name> {``  — named sub-module
    ``  func.func public @<name>``  — public function definition
    ``  func.func private @<name>`` — private function declaration

- The first non-label line after a label becomes ``// CHECK:``; subsequent
  consecutive lines become ``// CHECK-NEXT:``.

Trailing whitespace is stripped from all lines before emitting directives.

Usage::

    pipeline-command | python3 generate-filecheck-format-ir.py
    pipeline-command | python3 generate-filecheck-format-ir.py - output.mlir
    python3 generate-filecheck-format-ir.py input.mlir [output.mlir]
"""

import re
import sys
from pathlib import Path

# Patterns whose matching lines become CHECK-LABEL (structural boundaries).
_LABEL_PATTERNS: list[re.Pattern] = [
    re.compile(r"^  builtin\.module @\w+"),
    re.compile(r"^    func\.func public @\w+"),
    re.compile(r"^    func\.func private @\w+"),
]


def _is_label(line: str) -> bool:
    return any(p.match(line) for p in _LABEL_PATTERNS)


def generate(lines: list[str]) -> str:
    """Convert a list of MLIR IR lines to filecheck directives."""
    out: list[str] = []
    after_reset = True  # True immediately after a label or start-of-file

    for raw in lines:
        line = raw.rstrip()  # strip trailing whitespace
        if not line:
            continue  # MLIR IR has no meaningful blank lines; skip silently

        if _is_label(line):
            out.append(f"// CHECK-LABEL: {line}")
            after_reset = True
        elif after_reset:
            out.append(f"// CHECK:       {line}")
            after_reset = False
        else:
            out.append(f"// CHECK-NEXT:  {line}")

    return "\n".join(out) + "\n"


def main() -> None:
    args = sys.argv[1:]

    in_path: Path | None = None
    out_path: Path | None = None

    for arg in args:
        if arg == "-":
            in_path = None
        elif in_path is None and out_path is None and not arg.startswith("-"):
            in_path = Path(arg)
        elif out_path is None and not arg.startswith("-"):
            out_path = Path(arg)

    if in_path is not None:
        lines = in_path.read_text().splitlines(keepends=True)
    else:
        lines = sys.stdin.readlines()

    result = generate(lines)

    if out_path is not None:
        out_path.write_text(result)
    else:
        sys.stdout.write(result)


if __name__ == "__main__":
    main()
