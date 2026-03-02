from xdsl.dialects.builtin import IntegerAttr, StringAttr, i1, i64
from xdsl.ir import Dialect
from xdsl.irdl import (
    IRDLOperation,
    irdl_op_definition,
    operand_def,
    prop_def,
    result_def,
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


CCPPUtils = Dialect(
    "ccpp_utils",
    [StrCmpOp, StringEqOp],
    [],
)
