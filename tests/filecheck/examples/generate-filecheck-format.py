#!/usr/bin/env python3
"""Generate // CHECK directives from ccpp pipeline (Fortran) output.

Reads Fortran text produced by the ccpp pipeline from stdin (or a file) and
prints a set of filecheck directives suitable for pasting into a ``.mlir``
test file.

Directive mapping
-----------------
- Lines matching key structural boundaries become ``// CHECK-LABEL:``
  so that filecheck can seek forward to them independently:

    ``// FILE: <name>.F90``    — file-split marker
    ``module <name>``          — module definition
    ``  subroutine <name>(…)`` — subroutine definition

- Whitespace-only lines are skipped (they reset the ``CHECK``/``CHECK-NEXT``
  run so the next content line uses ``// CHECK:`` instead of
  ``// CHECK-NEXT:``), but no directive is emitted.  The Fortran printer
  indents blank lines with spaces, which ``CHECK-EMPTY:`` (requiring a
  truly-empty line) would not match.
- The ``// -----`` module separator becomes ``// CHECK: // -----``.
- The first non-empty, non-label line after a label or empty line becomes
  ``// CHECK:``; subsequent consecutive lines become ``// CHECK-NEXT:``.

Trailing whitespace is stripped from all lines before emitting directives,
so that the generated tests are not sensitive to the printer's padding.

Usage::

    pipeline-command | python3 generate-filecheck-format.py
    pipeline-command | python3 generate-filecheck-format.py - output.mlir
    python3 generate-filecheck-format.py input.ftn [output.mlir]
"""

import re
import sys
from pathlib import Path

# Patterns whose matching lines become CHECK-LABEL (structural boundaries).
_LABEL_PATTERNS: list[re.Pattern] = [
    re.compile(r"^// FILE:"),
    re.compile(r"^module "),
    re.compile(r"^  subroutine "),
]


def _is_label(line: str) -> bool:
    return any(p.match(line) for p in _LABEL_PATTERNS)


def generate(lines: list[str]) -> str:
    """Convert a list of Fortran output lines to filecheck directives."""
    out: list[str] = []
    after_reset = True  # True immediately after a label, empty, or start-of-file

    for raw in lines:
        line = raw.rstrip()  # strip trailing whitespace

        if not line:  # blank or whitespace-only — reset run, emit nothing
            after_reset = True
        elif line == "// -----":  # xDSL module separator
            out.append("// CHECK:       // -----")
            after_reset = True
        elif _is_label(line):
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

    # Argument parsing: optional input file (or "-" for stdin) and output file.
    in_path: Path | None = None
    out_path: Path | None = None

    for arg in args:
        if arg == "-":
            in_path = None  # explicit stdin
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
