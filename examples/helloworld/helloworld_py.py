"""Python equivalent of hello_world_suite.xml + hello_scheme.meta + temp_adjust.meta.

Run to emit MLIR IR:
    python3 examples/helloworld/helloworld_py.py

Full pipeline (MLIR → Fortran):
    python3 examples/helloworld/helloworld_py.py | \\
        python3 -m xdsl_ccpp.tools.ccpp_opt \\
        -p generate-meta-cap,generate-meta-kinds,generate-suite-cap,generate-ccpp-cap,generate-kinds,strip-ccpp \\
        -t ftn

CLI override — repeat hello_scheme N times (N resolved at IR-generation time):
    python3 examples/helloworld/helloworld_py.py hello_repeats=3 | ...

Keyword argument override — compile-time literal for a specific argument:
    Calls inside run() accept keyword arguments, e.g. hello_scheme(ncol=5), which
    generates Fortran with named-argument syntax: call hello_scheme_run(ncol=5, ...).
"""

from xdsl_ccpp.frontend.py_api import Arg, ccpp_param, ccpp_scheme, ccpp_suite, emit_ir

# ---------------------------------------------------------------------------
# Shared standard arguments (reused across schemes and entry points)
# ---------------------------------------------------------------------------

errmsg = Arg(
    "errmsg",
    standard_name="ccpp_error_message",
    long_name="Error message for error handling in CCPP",
    type="character",
    kind="len=512",
    intent="out",
    units="none",
)

errflg = Arg(
    "errflg",
    standard_name="ccpp_error_code",
    long_name="Error flag for error handling in CCPP",
    type="integer",
    intent="out",
    units="1",
)

# ---------------------------------------------------------------------------
# hello_scheme
# ---------------------------------------------------------------------------


@ccpp_scheme
class hello_scheme:
    run = [
        Arg(
            "ncol",
            standard_name="horizontal_loop_extent",
            type="integer",
            units="count",
            intent="in",
        ),
        Arg(
            "lev",
            standard_name="vertical_layer_dimension",
            type="integer",
            units="count",
            intent="in",
        ),
        Arg(
            "ilev",
            standard_name="vertical_interface_dimension",
            type="integer",
            units="count",
            intent="in",
        ),
        Arg(
            "timestep",
            standard_name="time_step_for_physics",
            long_name="time step",
            type="real",
            kind="kind_phys",
            intent="in",
            units="s",
        ),
        Arg(
            "temp_level",
            standard_name="potential_temperature_at_interface",
            type="real",
            kind="kind_phys",
            intent="inout",
            units="K",
            dimensions=("horizontal_loop_extent", "vertical_interface_dimension"),
        ),
        Arg(
            "temp_layer",
            standard_name="potential_temperature",
            type="real",
            kind="kind_phys",
            intent="out",
            units="K",
            dimensions=("horizontal_loop_extent", "vertical_layer_dimension"),
        ),
        errmsg,
        errflg,
    ]
    init = [errmsg, errflg]
    finalize = [errmsg, errflg]


# ---------------------------------------------------------------------------
# temp_adjust
# ---------------------------------------------------------------------------


@ccpp_scheme
class temp_adjust:
    run = [
        Arg(
            "nbox",
            standard_name="horizontal_loop_extent",
            type="integer",
            units="count",
            intent="in",
        ),
        Arg(
            "lev",
            standard_name="vertical_layer_dimension",
            type="integer",
            units="count",
            intent="in",
        ),
        Arg(
            "temp_layer",
            standard_name="potential_temperature",
            type="real",
            kind="kind_phys",
            intent="inout",
            units="K",
            dimensions=("horizontal_loop_extent", "vertical_layer_dimension"),
        ),
        Arg(
            "timestep",
            standard_name="time_step_for_physics",
            long_name="time step",
            type="real",
            kind="kind_phys",
            intent="in",
            units="s",
        ),
        errmsg,
        errflg,
    ]
    init = [errmsg, errflg]
    finalize = [errmsg, errflg]


# ---------------------------------------------------------------------------
# Suite
# ---------------------------------------------------------------------------


# Number of times to repeat hello_scheme in the run group.
# Default: 1 (equivalent to the non-loop version).
# Override from CLI: python3 helloworld_py.py hello_repeats=3
hello_repeats = ccpp_param("hello_repeats", default=1)


@ccpp_suite("hello_world_suite", version="1.0")
class hello_world:
    physics = [hello_scheme, temp_adjust]

    def run():
        # Repeat hello_scheme `hello_repeats` times, then run temp_adjust once.
        # hello_repeats is resolved at IR-generation time (from the module-level
        # variable above, optionally overridden via CLI).
        for i in range(0, hello_repeats):
            hello_scheme()
        temp_adjust()


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    emit_ir(hello_world)
