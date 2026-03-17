#!/usr/bin/env python3
"""Regenerate the CHECK directives in a filecheck ``.mlir`` test file.

Reads the ``// RUN:`` line from the given ``.mlir`` file, strips the trailing
``| python3 -m filecheck %s`` stage, runs the resulting pipeline, converts the
output to filecheck directives via ``generate-filecheck-format.py``, and
rewrites the CHECK section of the test file in place.

The file is expected to have a structure like::

    // <header comments>
    //
    // RUN: <pipeline> | python3 -m filecheck %s
    //
    // CHECK-LABEL: ...
    // CHECK: ...
    ...

Everything before the first ``// CHECK`` directive is preserved verbatim; the
CHECK section is replaced with freshly generated directives.

Usage::

    python3 tests/filecheck/examples/update-filecheck-test.py <test.mlir> [<test2.mlir> ...]
"""

import re
import subprocess
import sys
from pathlib import Path

_FILECHECK_SUFFIX_RE = re.compile(
    r"\s*\|\s*python3\s+-m\s+filecheck\s+%s\s*$"
)
_RUN_RE = re.compile(r"^//\s*RUN:\s*(.+)$")
_CHECK_RE = re.compile(r"^//\s*CHECK")

_SCRIPT_DIR = Path(__file__).parent
_FORMAT_SCRIPT_FTN = _SCRIPT_DIR / "generate-filecheck-format.py"
_FORMAT_SCRIPT_IR = _SCRIPT_DIR / "generate-filecheck-format-ir.py"
_REPO_ROOT = _SCRIPT_DIR.parent.parent.parent  # tests/filecheck/examples → repo root


def _extract_run_command(lines: list[str]) -> str | None:
    """Return the pipeline command from the first ``// RUN:`` line, or None."""
    for line in lines:
        m = _RUN_RE.match(line.rstrip())
        if m:
            cmd = m.group(1)
            cmd = _FILECHECK_SUFFIX_RE.sub("", cmd)
            return cmd.rstrip()
    return None


def _split_at_checks(lines: list[str]) -> tuple[list[str], list[str]]:
    """Split *lines* into (header, checks) at the first ``// CHECK`` line."""
    for i, line in enumerate(lines):
        if _CHECK_RE.match(line):
            return lines[:i], lines[i:]
    # No CHECK lines yet — everything is the header.
    return lines, []


def _run_pipeline(cmd: str) -> str:
    """Run *cmd* in the repo root and return stdout."""
    result = subprocess.run(
        cmd,
        shell=True,
        cwd=_REPO_ROOT,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        raise RuntimeError(
            f"Pipeline failed (exit {result.returncode}):\n{result.stderr}"
        )
    return result.stdout


def _generate_checks(pipeline_output: str, cmd: str) -> str:
    """Convert pipeline output to filecheck directives.

    Selects the Fortran formatter when the command ends with ``-t ftn``,
    otherwise uses the MLIR IR formatter.
    """
    is_ftn = "-t ftn" in cmd
    format_script = _FORMAT_SCRIPT_FTN if is_ftn else _FORMAT_SCRIPT_IR
    result = subprocess.run(
        [sys.executable, str(format_script)],
        input=pipeline_output,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        raise RuntimeError(
            f"{format_script.name} failed:\n{result.stderr}"
        )
    return result.stdout


def update_file(path: Path) -> None:
    text = path.read_text()
    lines = text.splitlines(keepends=True)

    cmd = _extract_run_command(lines)
    if cmd is None:
        print(f"WARNING: no // RUN: line found in {path}, skipping.", file=sys.stderr)
        return

    print(f"Running pipeline for {path.name}…", file=sys.stderr)
    try:
        pipeline_output = _run_pipeline(cmd)
    except RuntimeError as e:
        print(f"ERROR: {e}", file=sys.stderr)
        sys.exit(1)

    new_checks = _generate_checks(pipeline_output, cmd)

    header, _old_checks = _split_at_checks(lines)
    header_text = "".join(header)
    # Ensure the header ends with exactly one blank line before CHECK directives.
    header_text = header_text.rstrip("\n") + "\n\n"

    path.write_text(header_text + new_checks)
    print(f"Updated {path}", file=sys.stderr)


def main() -> None:
    if not sys.argv[1:]:
        print(__doc__, file=sys.stderr)
        sys.exit(1)

    for arg in sys.argv[1:]:
        update_file(Path(arg))


if __name__ == "__main__":
    main()
