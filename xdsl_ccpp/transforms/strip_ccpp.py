from dataclasses import dataclass

from xdsl.dialects import builtin, memref, func, arith, scf
from xdsl.context import Context
from xdsl.passes import ModulePass
from xdsl.pattern_rewriter import (
    GreedyRewritePatternApplier,
    PatternRewriter,
    PatternRewriteWalker,
    RewritePattern,
    InsertPoint,
    op_type_rewrite_pattern,
)
from xdsl.ir import Block, Region


class EraseCCPP(RewritePattern):
    """Rewrite pattern that removes the dedicated 'ccpp' named module.

    After `generate-meta-cap` and `generate-suite-cap` have consumed the CCPP
    dialect ops and produced the final cap subroutines, the intermediate 'ccpp'
    module (which holds the original suite and metadata ops) is no longer needed.
    This pattern matches any `ModuleOp` whose `sym_name` is ``"ccpp"`` and erases
    it unconditionally.
    """

    @op_type_rewrite_pattern
    def match_and_rewrite(self, op: builtin.ModuleOp, rewriter: PatternRewriter):
        # Only erase the module that was created specifically to hold CCPP IR
        if op.sym_name is not None and op.sym_name.data == "ccpp":
            rewriter.erase_op(op)


@dataclass(frozen=True)
class StripCCPP(ModulePass):
    """Pass that strips the intermediate CCPP module from the IR.

    This is the final cleanup pass in the CCPP compilation pipeline.  It runs
    after `generate-meta-cap` (which creates external function declarations) and
    `generate-suite-cap` (which creates the suite cap subroutines), at which point
    the 'ccpp' named module containing the original dialect ops is redundant and
    should be removed before Fortran code generation.

    Pipeline position: generate-meta-cap → generate-suite-cap → **strip-ccpp** → ftn
    """

    name = "strip-ccpp"

    def apply(self, ctx: Context, op: builtin.ModuleOp) -> None:
        # Walk the top-level module and erase any ModuleOp named 'ccpp'
        PatternRewriteWalker(
            GreedyRewritePatternApplier(
                [
                    EraseCCPP(),
                ]
            ),
            apply_recursively=False,
        ).rewrite_module(op)
