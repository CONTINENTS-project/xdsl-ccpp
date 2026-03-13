from dataclasses import dataclass

from xdsl.context import Context
from xdsl.dialects import arith, builtin, llvm, memref, scf
from xdsl.dialects import func as func_dialect
from xdsl.dialects.builtin import (
    ArrayAttr,
    DenseArrayBase,
    FunctionType,
    IndexType,
    IntegerAttr,
    MemRefType,
    f64,
    i1,
    i8,
    i64,
)
from xdsl.dialects.llvm import LLVMArrayType
from xdsl.ir import Attribute, Block
from xdsl.passes import ModulePass
from xdsl.pattern_rewriter import (
    GreedyRewritePatternApplier,
    PatternRewriter,
    PatternRewriteWalker,
    RewritePattern,
    op_type_rewrite_pattern,
)

from xdsl_ccpp.dialects.ccpp_utils import (
    RealKindType,
    SetStringOp,
    StrCmpOp,
    WriteErrMsgOp,
)


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


class LowerWriteErrMsg(RewritePattern):
    """Lower ``ccpp_utils.write_errmsg`` to byte-wise stores.

    Semantics: ``dest = prefix + var + suffix``

    ``prefix`` and ``suffix`` are compile-time string literals.  ``var`` is
    either a ``memref<?xi8>`` (dynamic length, copied with an ``scf.for``
    loop) or an ``!llvm.array<N x i8>`` (static length, copied with
    ``llvm.extractvalue`` per byte).

    The suffix start offset is ``len(prefix) + len(var)``; for the memref
    case this is computed at runtime with ``arith.addi``.
    """

    @op_type_rewrite_pattern
    def match_and_rewrite(self, op: WriteErrMsgOp, rewriter: PatternRewriter):
        prefix_bytes = op.prefix.data.encode("ascii")
        suffix_bytes = op.suffix.data.encode("ascii")
        prefix_len = len(prefix_bytes)
        suffix_len = len(suffix_bytes)

        new_ops = []

        # ── 1. Store prefix bytes ─────────────────────────────────────────────
        for i, byte_val in enumerate(prefix_bytes):
            idx = arith.ConstantOp(IntegerAttr(i, IndexType()), IndexType())
            byte_op = arith.ConstantOp.from_int_and_width(byte_val, 8)
            store = memref.StoreOp.get(byte_op.result, op.dest, [idx.result])
            new_ops += [idx, byte_op, store]

        # ── 2. Copy var bytes ─────────────────────────────────────────────────
        if isinstance(op.var.type, LLVMArrayType):
            # Static-length LLVM array — emit one extractvalue + store per byte
            n = op.var.type.size.data
            for i in range(n):
                extract = llvm.ExtractValueOp(
                    DenseArrayBase.from_list(i64, [i]), op.var, i8
                )
                idx = arith.ConstantOp(
                    IntegerAttr(prefix_len + i, IndexType()), IndexType()
                )
                store = memref.StoreOp.get(extract.res, op.dest, [idx.result])
                new_ops += [extract, idx, store]
            var_len_op = arith.ConstantOp(IntegerAttr(n, IndexType()), IndexType())
            new_ops.append(var_len_op)
            prefix_len_op = arith.ConstantOp(
                IntegerAttr(prefix_len, IndexType()), IndexType()
            )
            new_ops.append(prefix_len_op)
            suffix_start_op = arith.AddiOp(prefix_len_op.result, var_len_op.result)
            new_ops.append(suffix_start_op)
            suffix_start = suffix_start_op.result
        else:
            # Dynamic memref<?xi8> — use scf.for to copy bytes
            dim_idx_op = arith.ConstantOp(IntegerAttr(0, IndexType()), IndexType())
            var_dim_op = memref.DimOp.from_source_and_index(op.var, dim_idx_op.result)
            prefix_len_op = arith.ConstantOp(
                IntegerAttr(prefix_len, IndexType()), IndexType()
            )
            step_op = arith.ConstantOp(IntegerAttr(1, IndexType()), IndexType())
            new_ops += [dim_idx_op, var_dim_op, prefix_len_op, step_op]

            # Body: load var[iv - prefix_len], store to dest[iv]
            body_block = Block(arg_types=[IndexType()])
            iv = body_block.args[0]
            load_op = memref.LoadOp.get(op.var, [iv])
            # Compute dest index = prefix_len_op.result + iv
            # Actually iv runs from 0 to var_dim, and dest offset = prefix_len + iv
            # We need to add prefix_len to iv inside the loop body.
            prefix_offset_op = arith.ConstantOp(
                IntegerAttr(prefix_len, IndexType()), IndexType()
            )
            dest_idx_op = arith.AddiOp(prefix_offset_op.result, iv)
            store_op = memref.StoreOp.get(load_op.res, op.dest, [dest_idx_op.result])
            body_block.add_ops(
                [load_op, prefix_offset_op, dest_idx_op, store_op, scf.YieldOp()]
            )

            zero_op = arith.ConstantOp(IntegerAttr(0, IndexType()), IndexType())
            new_ops.append(zero_op)
            for_op = scf.ForOp(
                zero_op.result,
                var_dim_op.result,
                step_op.result,
                [],
                body_block,
            )
            new_ops.append(for_op)

            # suffix_start = prefix_len + var_dim
            suffix_start_op = arith.AddiOp(prefix_len_op.result, var_dim_op.result)
            new_ops.append(suffix_start_op)
            suffix_start = suffix_start_op.result

        # ── 3. Store suffix bytes ─────────────────────────────────────────────
        if suffix_len > 0:
            for i, byte_val in enumerate(suffix_bytes):
                i_op = arith.ConstantOp(IntegerAttr(i, IndexType()), IndexType())
                dest_idx_op = arith.AddiOp(suffix_start, i_op.result)
                byte_op = arith.ConstantOp.from_int_and_width(byte_val, 8)
                store = memref.StoreOp.get(
                    byte_op.result, op.dest, [dest_idx_op.result]
                )
                new_ops += [i_op, dest_idx_op, byte_op, store]

        rewriter.replace_matched_op(new_ops, [])


def _replace_real_kind(t: Attribute) -> Attribute:
    """Recursively replace ``!ccpp_utils.real_kind<*>`` with ``f64``."""
    if isinstance(t, RealKindType):
        return f64
    if isinstance(t, MemRefType) and isinstance(t.element_type, RealKindType):
        return MemRefType(f64, t.shape, t.layout, t.memory_space)
    if isinstance(t, FunctionType):
        new_inputs = [_replace_real_kind(i) for i in t.inputs.data]
        new_outputs = [_replace_real_kind(o) for o in t.outputs.data]
        if new_inputs != list(t.inputs.data) or new_outputs != list(t.outputs.data):
            return FunctionType(
                ArrayAttr(new_inputs),
                ArrayAttr(new_outputs),
            )
    return t


def _lower_real_kind_types(module: builtin.ModuleOp) -> None:
    """Walk the entire module and replace ``RealKindType`` with ``f64`` in all
    SSA value types, block argument types, and ``func.func`` function types."""
    for inner_op in module.walk():
        for result in inner_op.results:
            new_t = _replace_real_kind(result._type)
            if new_t is not result._type:
                result._type = new_t  # type: ignore[misc]
        if isinstance(inner_op, func_dialect.FuncOp):
            new_ft = _replace_real_kind(inner_op.function_type)
            if new_ft is not inner_op.function_type:
                inner_op.properties["function_type"] = new_ft
        for region in inner_op.regions:
            for block in region.blocks:
                for arg in block.args:
                    new_t = _replace_real_kind(arg._type)
                    if new_t is not arg._type:
                        arg._type = new_t  # type: ignore[misc]


@dataclass(frozen=True)
class LowerCCPPUtils(ModulePass):
    name = "lower-ccpp-utils"

    def apply(self, ctx: Context, op: builtin.ModuleOp) -> None:
        PatternRewriteWalker(
            GreedyRewritePatternApplier(
                [
                    LowerStrCmp(),
                    LowerStrCmpLiteral(),
                    LowerSetString(),
                    LowerWriteErrMsg(),
                ]
            )
        ).rewrite_module(op)
        _lower_real_kind_types(op)
