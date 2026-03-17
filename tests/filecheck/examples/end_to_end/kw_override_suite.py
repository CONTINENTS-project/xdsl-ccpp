"""Helper script for the keyword-argument override filecheck test.

Emits IR for a minimal suite where hello_scheme is called with ncol=5 as a
compile-time literal override.  The generated Fortran should use keyword
argument syntax: call hello_scheme_run(ncol=5, lev=lev, ...).
"""

from xdsl_ccpp.frontend.py_api import Arg, ccpp_scheme, ccpp_suite, emit_ir

errmsg = Arg(
    "errmsg",
    standard_name="ccpp_error_message",
    type="character",
    kind="len=512",
    intent="out",
    units="none",
)
errflg = Arg(
    "errflg",
    standard_name="ccpp_error_code",
    type="integer",
    intent="out",
    units="1",
)


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
        errmsg,
        errflg,
    ]
    init = [errmsg, errflg]
    finalize = [errmsg, errflg]


@ccpp_suite("kw_suite", version="1.0")
class kw_suite:
    physics = [hello_scheme]

    def run():
        hello_scheme(ncol=5)


if __name__ == "__main__":
    emit_ir(kw_suite)
