from dataclasses import dataclass

from xdsl.context import Context
from xdsl.dialects import arith, builtin, llvm, memref
from xdsl.dialects.builtin import DenseArrayBase, IndexType, IntegerAttr, i8, i64
from xdsl.passes import ModulePass
from xdsl.pattern_rewriter import (
    GreedyRewritePatternApplier,
    PatternRewriter,
    PatternRewriteWalker,
    RewritePattern,
    op_type_rewrite_pattern,
)

from xdsl_ccpp.dialects.ccpp_utils import SetStringOp, StrCmpOp


class LowerStrCmp(RewritePattern):
    @op_type_rewrite_pattern
    def match_and_rewrite(self, op: StrCmpOp, rewriter: PatternRewriter):
        if op.rhs is None or op.length is None:
            return
        length = op.length.value.data

        new_ops = []
        prev = None
        for idx in range(length):
            lhs_byte = llvm.ExtractValueOp(
                DenseArrayBase.from_list(i64, [idx]), op.lhs, i8
            )
            rhs_byte = llvm.ExtractValueOp(
                DenseArrayBase.from_list(i64, [idx]), op.rhs, i8
            )
            eq = arith.CmpiOp(lhs_byte.res, rhs_byte.res, 0)  # 0 = eq
            new_ops += [lhs_byte, rhs_byte, eq]
            if prev is None:
                prev = eq
            else:
                and_op = arith.AndIOp(prev.result, eq.result)
                new_ops.append(and_op)
                prev = and_op

        rewriter.replace_matched_op(new_ops, [prev.result])


class LowerSetString(RewritePattern):
    """Lower ``ccpp_utils.set_string`` to byte-wise ``memref.store`` ops.

    The op copies an ``!llvm.array<N x i8>`` source into a ``memref<?xi8>``
    destination.  The length N is read from the LLVM array type.  For each
    byte position ``i`` the lowering emits:

    .. code-block:: mlir

        %byte_i = llvm.extractvalue %src[i] : !llvm.array<N x i8> -> i8
        %idx_i  = arith.constant i : index
        memref.store %byte_i, %dest[%idx_i] : memref<?xi8>
    """

    @op_type_rewrite_pattern
    def match_and_rewrite(self, op: SetStringOp, rewriter: PatternRewriter):
        n = op.src.type.size.data

        new_ops = []
        for i in range(n):
            extract = llvm.ExtractValueOp(
                DenseArrayBase.from_list(i64, [i]), op.src, i8
            )
            idx = arith.ConstantOp(IntegerAttr(i, IndexType()), IndexType())
            store = memref.StoreOp.get(extract.res, op.dest, [idx.result])
            new_ops += [extract, idx, store]

        rewriter.replace_matched_op(new_ops, [])


@dataclass(frozen=True)
class LowerCCPPUtils(ModulePass):
    name = "lower-ccpp-utils"

    def apply(self, ctx: Context, op: builtin.ModuleOp) -> None:
        PatternRewriteWalker(
            GreedyRewritePatternApplier([LowerStrCmp(), LowerSetString()])
        ).rewrite_module(op)
