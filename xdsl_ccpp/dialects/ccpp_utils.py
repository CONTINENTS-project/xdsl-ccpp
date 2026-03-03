from xdsl.dialects.builtin import IntegerAttr, StringAttr, i1, i64
from xdsl.ir import Dialect, SSAValue
from xdsl.irdl import (
    AttrSizedOperandSegments,
    IRDLOperation,
    irdl_op_definition,
    operand_def,
    prop_def,
    result_def,
    var_operand_def,
)


@irdl_op_definition
class StrCmpOp(IRDLOperation):
    name = "ccpp_utils.strcmp"

    lhs = operand_def()  # !llvm.array<N x i8>
    rhs = operand_def()  # !llvm.array<M x i8>
    length = prop_def(IntegerAttr)  # number of bytes to compare
    res = result_def(i1)  # 1 if equal, 0 if not

    def __init__(self, lhs, rhs, length: int):
        super().__init__(
            operands=[lhs, rhs],
            properties={"length": IntegerAttr.from_int_and_width(length, 64)},
            result_types=[i1],
        )


@irdl_op_definition
class StringEqOp(IRDLOperation):
    """Compare an assumed-length string memref against a compile-time literal.

    lhs is a memref<?xi8> (Fortran character(len=*) buffer).
    literal is the string constant to compare against.
    Returns i1: 1 if equal (after trimming whitespace), 0 if not.

    Printed as: trim(lhs) .eq. 'literal'
    """

    name = "ccpp_utils.string_eq"

    lhs = operand_def()  # memref<?xi8>
    literal = prop_def(StringAttr)
    res = result_def(i1)

    def __init__(self, lhs, literal: str | StringAttr):
        if isinstance(literal, str):
            literal = StringAttr(literal)
        super().__init__(
            operands=[lhs],
            properties={"literal": literal},
            result_types=[i1],
        )


@irdl_op_definition
class HostVarRefOp(IRDLOperation):
    """SSA reference to a host model module variable.

    Produces an SSA value of the given result type representing `var_name`
    from `module_name`.  No Fortran code is emitted — the printer registers
    `var_name` as the variable name for the result so that downstream ops
    (e.g. call arguments) print the correct host variable name.

    A corresponding llvm.GlobalOp stub (with a 'module' attribute) is placed
    at the enclosing module level to drive 'use module, only: var' generation.
    """

    name = "ccpp_utils.host_var_ref"

    var_name = prop_def(StringAttr)
    module_name = prop_def(StringAttr)
    res = result_def()  # type set at construction to match callee expectation

    def __init__(self, var_name: str | StringAttr, module_name: str | StringAttr, result_type):
        if isinstance(var_name, str):
            var_name = StringAttr(var_name)
        if isinstance(module_name, str):
            module_name = StringAttr(module_name)
        super().__init__(
            properties={"var_name": var_name, "module_name": module_name},
            result_types=[result_type],
        )


@irdl_op_definition
class WriteErrMsgOp(IRDLOperation):
    """Write a formatted error message into an errmsg buffer.

    dest is a memref<512xi8> (errmsg buffer).
    var is a memref<?xi8> (the dynamic string part, will be trim()-ed).
    prefix and suffix are compile-time string literals.

    Printed as: write(dest, '(3a)') "prefix", trim(var), "suffix"
    """

    name = "ccpp_utils.write_errmsg"

    dest = operand_def()  # memref<512xi8>
    var = operand_def()   # memref<?xi8>
    prefix = prop_def(StringAttr)
    suffix = prop_def(StringAttr)

    def __init__(self, dest, var, prefix: str | StringAttr, suffix: str | StringAttr):
        if isinstance(prefix, str):
            prefix = StringAttr(prefix)
        if isinstance(suffix, str):
            suffix = StringAttr(suffix)
        super().__init__(
            operands=[dest, var],
            properties={"prefix": prefix, "suffix": suffix},
        )


@irdl_op_definition
class ArraySectionOp(IRDLOperation):
    """Represent a Fortran array section: source(lower0:upper0, lower1:upper1, ...).

    Used purely for Fortran code generation — no transformation semantics.
    The result type matches the source type.  The Fortran printer resolves the
    result to 'source_name(lower0:upper0, lower1:upper1)' so that downstream
    call ops emit the correct Fortran array-section notation.

    lowers and uppers must have the same length (one pair per dimension).
    """

    name = "ccpp_utils.array_section"

    source = operand_def()
    lowers = var_operand_def()
    uppers = var_operand_def()
    res = result_def()

    irdl_options = [AttrSizedOperandSegments()]

    def __init__(self, source, lowers, uppers):
        source_val = SSAValue.get(source)
        super().__init__(
            operands=[source, list(lowers), list(uppers)],
            result_types=[source_val.type],
        )


CCPPUtils = Dialect(
    "ccpp_utils",
    [StrCmpOp, StringEqOp, HostVarRefOp, WriteErrMsgOp, ArraySectionOp],
    [],
)
