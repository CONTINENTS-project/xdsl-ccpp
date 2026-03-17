# helloworld

A minimal two-scheme example demonstrating the complete `ccpp_xdsl` compilation flow.

## Schemes

| Scheme | Entry points | Description |
|--------|-------------|-------------|
| `hello_scheme` | `_run`, `_init`, `_finalize` | Sets temperature at layer interfaces and levels |
| `temp_adjust` | `_run`, `_init`, `_finalize` | Adjusts layer temperatures |

Suite `hello_world_suite` runs both schemes sequentially in a single `physics` group.

## Files

| File | Description |
|------|-------------|
| `hello_world_suite.xml` | Suite definition (XML frontend) |
| `hello_scheme.meta` | Metadata for `hello_scheme` |
| `temp_adjust.meta` | Metadata for `temp_adjust` |
| `hello_world_mod.meta` | Host model metadata |
| `helloworld_py.py` | Suite definition using the Python API |

## Running with ccpp_xdsl

### XML frontend

```bash
ccpp_xdsl \
  --suites examples/helloworld/hello_world_suite.xml \
  --scheme-files examples/helloworld/hello_scheme.meta,examples/helloworld/temp_adjust.meta \
  --host-files examples/helloworld/hello_world_mod.meta \
  -o output/
```

### Python frontend

```bash
ccpp_xdsl \
  --py examples/helloworld/helloworld_py.py \
  -o output/
```

Or run the Python script directly and pipe through the optimizer:

```bash
python3 examples/helloworld/helloworld_py.py | \
  python3 -m xdsl_ccpp.tools.ccpp_opt \
  -p generate-meta-cap,generate-meta-kinds,generate-suite-cap,generate-ccpp-cap,generate-kinds,strip-ccpp \
  -t ftn
```

## Generated output

| File | Description |
|------|-------------|
| `ccpp_kinds.F90` | Kind parameter definitions (`kind_phys` via ISO_FORTRAN_ENV) |
| `hello_world_suite_cap.F90` | Suite cap: `_initialize`, `_physics`, `_finalize` subroutines |
| `hello_world_ccpp_cap.F90` | Host-facing cap: `ccpp_physics_initialize`, `ccpp_physics_run`, etc. |

## Python API features

`helloworld_py.py` demonstrates two Python API features:

**`ccpp_param` — compile-time parameters overridable from the CLI:**

```python
hello_repeats = ccpp_param("hello_repeats", default=1)
```

Override at IR-generation time:

```bash
python3 examples/helloworld/helloworld_py.py hello_repeats=3 | \
  python3 -m xdsl_ccpp.tools.ccpp_opt \
  -p generate-meta-cap,generate-meta-kinds,generate-suite-cap,generate-ccpp-cap,generate-kinds,strip-ccpp \
  -t ftn
```

**Loops in `run()` — repeat scheme calls:**

```python
def run():
    for i in range(0, hello_repeats):
        hello_scheme()
    temp_adjust()
```

The loop executes at IR-generation time; the generated suite cap contains `hello_repeats` calls to `hello_scheme_run`.
