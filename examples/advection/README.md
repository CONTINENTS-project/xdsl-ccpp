# advection

A cloud advection example with four schemes, including one scheme (`apply_constituent_tendencies`) that appears twice in the suite to demonstrate repeated scheme calls.

## Schemes

| Scheme | Entry points | Description |
|--------|-------------|-------------|
| `const_indices` | `_run` | Sets constituent array indices |
| `cld_liq` | `_run`, `_init` | Liquid cloud scheme |
| `apply_constituent_tendencies` | `_run` | Applies constituent tendencies (called twice in the suite) |
| `cld_ice` | `_run`, `_init` | Ice cloud scheme |

Suite `cld_suite` runs all schemes in a single `physics` group, with `apply_constituent_tendencies` appearing after both `cld_liq` and `cld_ice`.

## Files

| File | Description |
|------|-------------|
| `cld_suite.xml` | Suite definition |
| `const_indices.meta` | Metadata for `const_indices` |
| `cld_liq.meta` | Metadata for `cld_liq` |
| `cld_ice.meta` | Metadata for `cld_ice` |
| `apply_constituent_tendencies.meta` | Metadata for `apply_constituent_tendencies` |
| `test_host_data.meta` | Host DDT metadata (`physics_state`) |
| `test_host.meta` | Host DDT metadata (`suite_info`) |
| `test_host_mod.meta` | Host module metadata |

## Running with ccpp_xdsl

```bash
ccpp_xdsl \
  --suites examples/advection/cld_suite.xml \
  --scheme-files examples/advection/const_indices.meta,examples/advection/cld_liq.meta,examples/advection/cld_ice.meta,examples/advection/apply_constituent_tendencies.meta \
  --host-files examples/advection/test_host_data.meta,examples/advection/test_host.meta,examples/advection/test_host_mod.meta \
  -o output/
```

## Generated output

| File | Description |
|------|-------------|
| `ccpp_kinds.F90` | Kind parameter definitions (`kind_phys` via ISO_FORTRAN_ENV) |
| `cld_suite_cap.F90` | Suite cap: `_initialize`, `_physics`, `_finalize` subroutines |
| `cld_ccpp_cap.F90` | Host-facing cap: `ccpp_physics_initialize`, `ccpp_physics_run`, etc. |
