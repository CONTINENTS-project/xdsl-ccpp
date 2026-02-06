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
    @op_type_rewrite_pattern
    def match_and_rewrite(self, op: builtin.ModuleOp, rewriter: PatternRewriter):
        if op.sym_name is not None and op.sym_name.data == "ccpp":
            rewriter.erase_op(op)

@dataclass(frozen=True)
class StripCCPP(ModulePass):
    name = "strip-ccpp"

    def apply(self, ctx: Context, op: builtin.ModuleOp) -> None:
        PatternRewriteWalker(
            GreedyRewritePatternApplier(
                [
                    EraseCCPP(),
                ]
            ),
            apply_recursively=False,
        ).rewrite_module(op)
