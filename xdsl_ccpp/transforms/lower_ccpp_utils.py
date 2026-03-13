from dataclasses import dataclass

from xdsl.context import Context
from xdsl.dialects import arith, builtin, llvm, memref, scf
from xdsl.dialects.builtin import DenseArrayBase, IndexType, IntegerAttr, i1, i8, i64
from xdsl.ir import Block
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
    """Lower rhs/length-mode ``ccpp_utils.strcmp`` to byte-wise LLVM extractvalue + arith.

    This handles the two-buffer mode where both ``lhs`` and ``rhs`` are
    ``!llvm.array<N x i8>`` values and ``length`` gives the byte count.
    Each pair of bytes is compared with ``arith.cmpi eq`` and all results
    are AND-ed together.
    """

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


class LowerStrCmpLiteral(RewritePattern):
    """Lower literal-mode ``ccpp_utils.strcmp`` to ``memref.load`` + ``scf.for``.

    This handles the case where ``lhs`` is a ``memref<?xi8>`` (a Fortran
    CHARACTER argument, padded with spaces to its declared length) and
    ``literal`` is a compile-time string constant.  The comparison semantics
    follow Fortran ``trim(lhs) .eq. 'literal'``:

    1. **Prefix match**: the first ``len(literal)`` bytes of ``lhs`` must
       equal the corresponding bytes of the literal (``memref.load`` +
       ``arith.cmpi eq`` for each byte, AND-ed together).

    2. **Trailing-spaces check**: every byte from position ``len(literal)``
       to the end of the buffer must be a space (0x20).  This is implemented
       as an ``scf.for`` loop with an ``i1`` iter-arg accumulator.

    The final result is the AND of both checks.

    .. code-block:: mlir

        // trim(lhs) .eq. 'hi' where lhs = memref<?xi8>  →
        %c0 = arith.constant 0 : index
        %b0 = memref.load %lhs[%c0] : memref<?xi8>
        %l0 = arith.constant 104 : i8   // 'h'
        %e0 = arith.cmpi eq, %b0, %l0 : i8
        %c1 = arith.constant 1 : index
        %b1 = memref.load %lhs[%c1] : memref<?xi8>
        %l1 = arith.constant 105 : i8   // 'i'
        %e1 = arith.cmpi eq, %b1, %l1 : i8
        %prefix = arith.andi %e0, %e1 : i1
        %dim_idx = arith.constant 0 : index
        %lhs_len = memref.dim %lhs, %dim_idx : memref<?xi8>
        %lit_len = arith.constant 2 : index
        %step   = arith.constant 1 : index
        %true   = arith.constant 1 : i1
        %trailing = scf.for %i = %lit_len to %lhs_len step %step
                        iter_args(%acc = %true) -> i1 {
            %byte  = memref.load %lhs[%i] : memref<?xi8>
            %space = arith.constant 32 : i8
            %sp_eq = arith.cmpi eq, %byte, %space : i8
            %new   = arith.andi %acc, %sp_eq : i1
            scf.yield %new : i1
        }
        %result = arith.andi %prefix, %trailing : i1
    """

    @op_type_rewrite_pattern
    def match_and_rewrite(self, op: StrCmpOp, rewriter: PatternRewriter):
        if op.literal is None:
            return

        lit_bytes = op.literal.data.encode("ascii")
        lit_len = len(lit_bytes)

        new_ops = []

        # ── 1. Prefix comparison ─────────────────────────────────────────────
        prefix_result = None
        for i, byte_val in enumerate(lit_bytes):
            idx_op = arith.ConstantOp(IntegerAttr(i, IndexType()), IndexType())
            load_op = memref.LoadOp.get(op.lhs, [idx_op.result])
            lit_byte_op = arith.ConstantOp.from_int_and_width(byte_val, 8)
            eq_op = arith.CmpiOp(load_op.res, lit_byte_op.result, 0)  # 0 = eq
            new_ops += [idx_op, load_op, lit_byte_op, eq_op]
            if prefix_result is None:
                prefix_result = eq_op
            else:
                and_op = arith.AndIOp(prefix_result.result, eq_op.result)
                new_ops.append(and_op)
                prefix_result = and_op

        if prefix_result is None:
            # Empty literal — prefix trivially matches
            true_op = arith.ConstantOp.from_int_and_width(1, 1)
            new_ops.append(true_op)
            prefix_result = true_op

        # ── 2. Trailing-spaces check via scf.for ─────────────────────────────
        dim_idx_op = arith.ConstantOp(IntegerAttr(0, IndexType()), IndexType())
        lhs_len_op = memref.DimOp.from_source_and_index(op.lhs, dim_idx_op.result)
        lit_len_op = arith.ConstantOp(IntegerAttr(lit_len, IndexType()), IndexType())
        step_op = arith.ConstantOp(IntegerAttr(1, IndexType()), IndexType())
        true_init_op = arith.ConstantOp.from_int_and_width(1, 1)
        new_ops += [dim_idx_op, lhs_len_op, lit_len_op, step_op, true_init_op]

        # Body block: (iv: index, acc: i1) → scf.yield(new_acc: i1)
        body_block = Block(arg_types=[IndexType(), i1])
        iv, acc_arg = body_block.args[0], body_block.args[1]
        byte_op = memref.LoadOp.get(op.lhs, [iv])
        space_op = arith.ConstantOp.from_int_and_width(0x20, 8)
        is_space_op = arith.CmpiOp(byte_op.res, space_op.result, 0)  # 0 = eq
        new_acc_op = arith.AndIOp(acc_arg, is_space_op.result)
        body_block.add_ops(
            [byte_op, space_op, is_space_op, new_acc_op, scf.YieldOp(new_acc_op.result)]
        )

        for_op = scf.ForOp(
            lit_len_op.result,
            lhs_len_op.result,
            step_op.result,
            [true_init_op.result],
            body_block,
        )
        new_ops.append(for_op)

        # ── 3. Combine prefix and trailing ───────────────────────────────────
        result_op = arith.AndIOp(prefix_result.result, for_op.res[0])
        new_ops.append(result_op)

        rewriter.replace_matched_op(new_ops, [result_op.result])


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
            GreedyRewritePatternApplier(
                [LowerStrCmp(), LowerStrCmpLiteral(), LowerSetString()]
            )
        ).rewrite_module(op)
