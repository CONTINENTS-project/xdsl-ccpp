"""Python equivalent of hello_world_suite.xml + hello_scheme.meta + temp_adjust.meta.

Run to emit MLIR IR:
    python3 examples/helloworld/helloworld_py.py

Full pipeline (MLIR → Fortran):
    python3 examples/helloworld/helloworld_py.py | \\
        python3 -m xdsl_ccpp.tools.ccpp_opt \\
        -p generate-meta-cap,generate-meta-kinds,generate-suite-cap,generate-ccpp-cap,generate-kinds,strip-ccpp \\
        -t ftn
"""

from xdsl_ccpp.frontend.py_api import Arg, ccpp_scheme, ccpp_suite, emit_ir

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


@ccpp_suite("hello_world_suite", version="1.0")
class hello_world:
    physics = [hello_scheme, temp_adjust]


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    emit_ir(hello_world)
