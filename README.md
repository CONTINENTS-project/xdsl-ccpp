# xdsl-ccpp

An implementation of the [CCPP](https://github.com/NCAR/ccpp-framework) (Common Community Physics Package) framework using [xDSL](https://github.com/xdslproject/xdsl), a Python-based MLIR framework. It reads CCPP suite XML and scheme metadata files and compiles them to Fortran cap subroutines.

## Installation

```bash
pip install .
```

This installs the `ccpp_xdsl` command-line driver and the `xdsl-ccpp` Python package. Requires Python 3.12+ and installs xDSL 0.56.1 as a dependency.

For development (linting, testing):

```bash
pip install -e ".[dev]"
```

## Hello World Example

The `examples/helloworld/` directory contains a complete example with two physics schemes (`hello_scheme` and `temp_adjust`) and a host model.

Run the full compilation flow with the driver script:

```bash
ccpp_xdsl \
  --suites examples/helloworld/hello_world_suite.xml \
  --scheme-files examples/helloworld/hello_scheme.meta,examples/helloworld/temp_adjust.meta \
  --host-files examples/helloworld/hello_world_mod.meta \
  -o output/
```

This generates three Fortran files in `output/`:

| File | Description |
|------|-------------|
| `ccpp_kinds.F90` | Kind parameter definitions (`kind_phys`, etc.) |
| `hello_world_suite_cap.F90` | Suite cap subroutines for `hello_world_suite` |
| `hello_world_ccpp_cap.F90` | Host-facing cap (`ccpp_physics_initialize`, `ccpp_physics_run`, etc.) |

### Driver Options

```
ccpp_xdsl --suites <xml,...> --scheme-files <meta,...> [options]

Required:
  --suites              Comma-separated suite XML files
  --scheme-files        Comma-separated scheme .meta files

Optional:
  --host-files          Comma-separated host model .meta files
  -o, --out             Output directory for .F90 files (default: .)
  --stdout              Print generated Fortran to stdout instead of files
  --host-name           Override the CamelCase host name prefix (e.g. HelloWorld);
                        derived from the suite name when not set
  -t, --tempdir         Temporary directory for intermediate files (default: tmp)
  -v, --verbose         Verbosity level: 0=quiet, 1=normal, 2=detailed (default: 1)
```

## Examples

The `examples/` directory contains several complete examples:

| Directory | Description |
|-----------|-------------|
| `helloworld/` | Two schemes (`hello_scheme`, `temp_adjust`) with XML and Python frontends |
| `advection/` | Advection scheme example with XML frontend |
| `ddthost/` | Example using Fortran derived data types (DDTs) and optional entry points |

Each example can be driven via the XML frontend, the Python API (`@ccpp_suite`), or both.

### Running the Pipeline Manually

**Frontend only** (parse → MLIR IR):

```bash
python3 -m xdsl_ccpp.frontend.ccpp_xml \
  --suites examples/helloworld/hello_world_suite.xml \
  --scheme-files examples/helloworld/hello_scheme.meta,examples/helloworld/temp_adjust.meta
```

**Frontend → optimizer** (MLIR IR after all passes, before Fortran):

```bash
python3 -m xdsl_ccpp.frontend.ccpp_xml \
  --suites examples/helloworld/hello_world_suite.xml \
  --scheme-files examples/helloworld/hello_scheme.meta,examples/helloworld/temp_adjust.meta | \
  python3 -m xdsl_ccpp.tools.ccpp_opt \
  -p generate-meta-cap,generate-meta-kinds,generate-suite-cap,generate-ccpp-cap,generate-kinds,strip-ccpp
```

**Full pipeline** (frontend → optimizer → Fortran):

```bash
python3 -m xdsl_ccpp.frontend.ccpp_xml \
  --suites examples/helloworld/hello_world_suite.xml \
  --scheme-files examples/helloworld/hello_scheme.meta,examples/helloworld/temp_adjust.meta | \
  python3 -m xdsl_ccpp.tools.ccpp_opt \
  -p generate-meta-cap,generate-meta-kinds,generate-suite-cap,generate-ccpp-cap,generate-kinds,strip-ccpp \
  -t ftn
```

**Python API frontend** (using `@ccpp_suite`):

```bash
python3 examples/helloworld/helloworld_py.py | \
  python3 -m xdsl_ccpp.tools.ccpp_opt \
  -p generate-meta-cap,generate-meta-kinds,generate-suite-cap,generate-ccpp-cap,generate-kinds,strip-ccpp \
  -t ftn
```

## Testing

Tests use [pytest](https://pytest.org) with [LLVM-style FileCheck](https://llvm.org/docs/CommandGuide/FileCheck.html) via the Python `filecheck` package.

Install test dependencies:

```bash
pip install -e ".[dev]"
```

Run all tests:

```bash
pytest tests/
```

Run a specific test file:

```bash
pytest tests/filecheck/examples/end_to_end/helloworld-xml.mlir
```

### Test Structure

FileCheck tests live under `tests/filecheck/examples/` in three subdirectories:

```
tests/filecheck/examples/
├── end_to_end/    ← full pipeline: frontend + optimizer + Fortran backend
├── frontend/      ← frontend only: raw MLIR IR emitted by the parser
└── completed_ir/  ← frontend + optimizer passes, before Fortran backend
```

Each `.mlir` file contains a `// RUN:` directive specifying the command to execute, followed by `// CHECK:` / `// CHECK-NEXT:` / `// CHECK-LABEL:` directives that the output must match. The `conftest.py` in `tests/` discovers and runs all `.mlir` files automatically.

### Updating Tests

If the compiler output changes, regenerate the CHECK directives for a test file using:

```bash
python3 tests/filecheck/examples/update-filecheck-test.py \
  tests/filecheck/examples/end_to_end/helloworld-xml.mlir
```

This runs the pipeline from the file's `// RUN:` line, converts the output to CHECK directives, and rewrites the file in place.

### Linting

```bash
ruff check xdsl_ccpp/
ruff format xdsl_ccpp/
```
