# xdsl-ccpp

An implementation of the [CCPP](https://github.com/NCAR/ccpp-framework) (Common Community Physics Package) framework using [xDSL](https://github.com/xdslproject/xdsl), a Python-based MLIR framework. It reads CCPP suite XML and scheme metadata files and compiles them to Fortran cap subroutines.

## Installation

```bash
pip install .
```

This installs the `ccpp_xdsl` command-line driver and the `xdsl-ccpp` Python package. Requires Python 3.12+ and installs xDSL 0.56.1 as a dependency.

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
