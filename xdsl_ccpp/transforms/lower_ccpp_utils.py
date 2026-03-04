from dataclasses import dataclass

from xdsl.context import Context
from xdsl.dialects import arith, builtin, llvm
from xdsl.dialects.builtin import DenseArrayBase, i8, i64
from xdsl.passes import ModulePass
from xdsl.pattern_rewriter import (
    GreedyRewritePatternApplier,
    PatternRewriter,
    PatternRewriteWalker,
    RewritePattern,
    op_type_rewrite_pattern,
)

from xdsl_ccpp.dialects.ccpp_utils import StrCmpOp


class LowerStrCmp(RewritePattern):
    @op_type_rewrite_pattern
    def match_and_rewrite(self, op: StrCmpOp, rewriter: PatternRewriter):
        if op.rhs is None or op.length is None:
            return
        length = op.length.value.data

        new_ops = []
        prev = None
        for idx in range(length):
            lhs_byte = llvm.ExtractValueOp(DenseArrayBase.from_list(i64, [idx]), op.lhs, i8)
            rhs_byte = llvm.ExtractValueOp(DenseArrayBase.from_list(i64, [idx]), op.rhs, i8)
            eq = arith.CmpiOp(lhs_byte.res, rhs_byte.res, 0)  # 0 = eq
            new_ops += [lhs_byte, rhs_byte, eq]
            if prev is None:
                prev = eq
            else:
                and_op = arith.AndIOp(prev.result, eq.result)
                new_ops.append(and_op)
                prev = and_op

        rewriter.replace_matched_op(new_ops, [prev.result])


@dataclass(frozen=True)
class LowerCCPPUtils(ModulePass):
    name = "lower-ccpp-utils"

    def apply(self, ctx: Context, op: builtin.ModuleOp) -> None:
        PatternRewriteWalker(
            GreedyRewritePatternApplier([LowerStrCmp()])
        ).rewrite_module(op)
