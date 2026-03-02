from __future__ import annotations

import warnings
from collections.abc import Iterable
from contextlib import contextmanager
from dataclasses import dataclass, field
from typing import IO, Literal, cast

from xdsl.dialects import arith, csl, memref, scf, builtin, func, llvm
from xdsl_ccpp.dialects.ccpp_utils import StrCmpOp as CCPPStrCmpOp
from xdsl.dialects.builtin import (
    DYNAMIC_INDEX,
    ArrayAttr,
    DenseIntOrFPElementsAttr,
    DictionaryAttr,
    Float64Type,
    Float32Type,
    FloatAttr,
    FunctionType,
    IndexType,
    IntAttr,
    IntegerAttr,
    IntegerType,
    MemRefType,
    ModuleOp,
    Signedness,
    SignednessAttr,
    StringAttr,
    TypeAttribute,
    UnitAttr,
    i1,
)
from xdsl.ir import Attribute, Block, Operation, OpResult, Region, SSAValue
from xdsl.ir.affine import AffineMap
from xdsl.irdl import Operand
from xdsl.traits import is_side_effect_free
from xdsl.utils.comparisons import to_unsigned
from xdsl.utils.hints import isa

@dataclass
class ftnPrintContext:
    _INDEX = "i32"
    _INDENT = "  "
    output: IO[str]

    _prefix: str = field(default="")

    variables: dict[SSAValue, str] = field(default_factory=dict[SSAValue, str])

    _counter: int = field(default=0)

    _binops: dict[str, str] = field(default_factory=dict[str, str])

    _cmp_ops: dict[str, dict[str, str | None]] = field(
        default_factory=dict[str, dict[str, str | None]]
    )

    def register_binops(self):
        self._binops.update(
            {
                arith.AddfOp.name: "+",
                arith.AddiOp.name: "+",
                arith.MulfOp.name: "*",
                arith.MuliOp.name: "*",
                arith.DivfOp.name: "/",
                arith.DivSIOp.name: "/",
                arith.DivUIOp.name: "/",
                arith.SubfOp.name: "-",
                arith.SubiOp.name: "-",
                arith.RemSIOp.name: "%",
                arith.RemUIOp.name: "%",
                arith.ShLIOp.name: "<<",
                arith.AndIOp.name: "&",
                arith.OrIOp.name: "|",
            }
        )
        self._cmp_ops.update(
            {
                arith.CmpiOp.name: {
                    "eq": ".eq.",
                    "ne": ".ne.",
                    "slt": ".lt.",
                    "sle": ".le.",
                    "sgt": ".gt.",
                    "sge": ".ge.",
                    "ult": ".lt.",
                    "ule": ".le.",
                    "ugt": ".gt.",
                    "uge": ".ge.",
                },
                arith.CmpfOp.name: {
                    "false": None,
                    "oeq": "==",
                    "ogt": ">",
                    "oge": ">=",
                    "olt": "<",
                    "ole": "<=",
                    "one": "!=",
                    "ord": None,
                    "ueq": "==",
                    "ugt": ">",
                    "uge": ">=",
                    "ult": "<",
                    "ule": "<=",
                    "une": "!=",
                    "uno": None,
                    "true": None,
                },
            }
        )

    def _get_variable_name_for(self, val: SSAValue, hint: str | None = None) -> str:
        """
        Get an assigned variable name for a given SSA Value
        """
        if val in self.variables:
            return self.variables[val]

        taken_names = set(self.variables.values())

        if hint is None:
            hint = val.name_hint

        if hint is not None and hint not in taken_names:
            name = hint
        else:
            prefix = "v" if val.name_hint is None else val.name_hint

            name = f"{prefix}{self._counter}"
            self._counter += 1

            while name in taken_names:
                name = f"{prefix}{self._counter}"
                self._counter += 1

        self.variables[val] = name
        return name

    def mlir_type_to_ftn_type(self, type_attr: Attribute) -> str:
        """
        Convert an MLR type to a csl type. CSL supports a very limited set of types:

        - integer types: i16, u16, i32, u32
        - float types: f16, f32
        - pointers: [*]f32
        - arrays: [64]f32
        - function: fn(i32) f16
        - color
        - comptime_struct
        - imported_module
        - type
        - comptime_string

        This method supports all of these except type and comptime_string
        """
        match type_attr:
            case Float32Type():
                return "real(kind=4)"
            case Float64Type():
                return "real(kind=8)"
            case IntegerType(width=IntAttr(1)):
                return "logical"
            case IntegerType(width=IntAttr(8)):
                return "character"
            case IntegerType():
                assert cast(IntegerType, type_attr).width.data == 32
                return f"integer"
            case MemRefType(element_type=Attribute() as elem_t, shape=shape):
                if any(dim.data == DYNAMIC_INDEX for dim in shape):
                    raise ValueError(
                        "Can't print memrefs to ftn if they have dynamic sizes. "
                    )
                shape_str = ", ".join(str(s.data) for s in shape)
                type_str = self.mlir_type_to_ftn_type(elem_t)
                if not shape_str:
                    return type_str
                elif type_str == "character":
                    return f"{type_str}(len={shape_str})"
                else:
                    return f"{type_str}({shape_str})"

    def attribute_value_to_str(self, attr: Attribute) -> str:
        """
        Takes a value-carrying attribute (IntegerAttr, FloatAttr, etc.)
        and converts it to a csl expression representing that value literal (0, 3.14, ...)
        """
        match attr:
            case IntAttr():
                return str(cast(IntAttr[int], attr).data)
            case IntegerAttr(value=val, type=IntegerType(width=IntAttr(data=1))):
                return str(bool(val.data)).lower()
            case IntegerAttr(value=val):
                return str(val.data)
            case FloatAttr(value=val) if val.data == 0:
                return "0.0"
            case FloatAttr(value=val):
                return str(val.data)
            case StringAttr() as s:
                return f'"{s.data}"'
            case DenseIntOrFPElementsAttr():
                return f"{self.mlir_type_to_ftn_type(attr.get_type())} {{ {', '.join(self.attribute_value_to_str(a) for a in attr.iter_attrs())} }}"  # noqa: E501
            case _:
                return f"<!unknown value {attr}>"

    def _print_or_promote_to_inline_expr(
        self, var: OpResult, value_expr: str, brackets: bool = False
    ):
        """
        Given an SSA value (op result) and a string representing its value.

        Check that the result can be promoted to an expression, or if not
        assign it to a new variable.

        Optionally adds brackets around the value when promoting to expression.
        """
        # prevent exploding expression sizes
        # also check that the expression is safe to promote
        #if len(value_expr) < 50 and self._can_promote_result_to_inline_expr(var):
        #    if brackets:
        #        value_expr = f"({value_expr})"
        #    self.variables[var] = value_expr
        #else:

        self.print(f"{value_expr}", end="", use_prefix=False)

    def find_ret_ssa_idx(self, ret_op, ssa):
        for idx, arg in enumerate(ret_op.arguments):
            if arg == ssa:
                return idx
        return None

    def print_expr(self, op:Operation):
        match op:
            case arith.ConstantOp(value=v, result=r):
                self._print_or_promote_to_inline_expr(r, self.attribute_value_to_str(v))
            case memref.LoadOp(memref=arr, indices=idxs, res=res):
                self.print(self._get_variable_name_for(arr), end="", use_prefix=False)
            case arith.CmpiOp(predicate=v, lhs=l, rhs=r):
                str_pred=arith.CMPI_COMPARISON_OPERATIONS[v.value.data]

                self.print_expr(l.owner)
                self.print(f" {self._cmp_ops[op.name][str_pred]} ", end="", use_prefix=False)
                self.print_expr(r.owner)
            case arith.XOrIOp():
                l, r = op.lhs, op.rhs
                if isa(r.owner, arith.ConstantOp):
                    self.print(".NOT. (", end="", use_prefix=False)
                    self.print_expr(l.owner)
                    self.print(")", end="", use_prefix=False)
                elif isa(l.owner, arith.ConstantOp):
                    self.print(".NOT. (", end="", use_prefix=False)
                    self.print_expr(r.owner)
                    self.print(")", end="", use_prefix=False)
                else:
                    self.print_expr(l.owner)
                    self.print(" .neqv. ", end="", use_prefix=False)
                    self.print_expr(r.owner)
            case CCPPStrCmpOp():
                lhs_name = self._get_variable_name_for(op.lhs)
                rhs_name = self._get_variable_name_for(op.rhs)
                self.print(f"{lhs_name} .eq. {rhs_name}", end="", use_prefix=False)
            case _:
                print(type(op))
                assert False

    def print_op(self, op: Operation):
        match op:
            case builtin.ModuleOp(sym_name=name, body=bdy):
                self._print_module(name, bdy)
            case memref.AllocaOp():
                pass  # Registration handled in _print_fn
            case llvm.GlobalOp():
                pass  # Declarations handled in _print_module
            case llvm.AddressOfOp():
                self.variables[op.result] = op.global_name.root_reference.data
            case llvm.LoadOp():
                self.variables[op.dereferenced_value] = self._get_variable_name_for(op.ptr)
            case llvm.StoreOp():
                dst_name = self._get_variable_name_for(op.ptr)
                src_name = self._get_variable_name_for(op.value)
                self.print(f"{dst_name} = {src_name}")
            case func.FuncOp(sym_name=name, body=bdy, function_type=ftyp):
                if not op.is_declaration:
                    self._print_fn(name, bdy, ftyp)
            case func.CallOp(callee=tgt, arguments=args, res=results):
                self._print_call(tgt, args, results)
            case scf.IfOp(cond=conditional, true_region=true_bdy, false_region=false_bdy):
                self._print_if(conditional, true_bdy, false_bdy)

            case memref.StoreOp(value=val, memref=arr, indices=idxs):
                arr_name = self._get_variable_name_for(arr)
                idx_args = ", ".join(map(self._get_variable_name_for, idxs))

                if len(idx_args) > 0:
                    self.print(f"{arr_name}[{idx_args}] = ", end="")
                else:
                    self.print(f"{arr_name} = ", end="")
                self.print_expr(val.owner)
                self.print("")

    def _print_module(self, module_name, body):
        assert module_name is not None

        self.print(f"module {module_name.data}")
        self.print("\nuse ccpp_kinds", prefix="  ")
        self.print("\nimplicit none", prefix="  ")
        self.print("private", prefix="  ")
        self.print("")

        for op in body.ops:
            if isa(op, llvm.GlobalOp):
                name = op.sym_name.data
                val = op.value.data if isa(op.value, StringAttr) else ""
                is_const = op.constant is not None
                if is_const:
                    self.print(f"character(len=16), parameter :: {name} = '{val}'", prefix="  ")
                else:
                    self.print(f"character(len=16) :: {name} = '{val}'", prefix="  ")

        self.print("\nCONTAINS")

        with self.descend() as inner:
            inner.print_block(body)

        self.print(f"end module {module_name.data}")

    def get_call_result_var_ssa(self, res_ssa):
        for use in res_ssa.uses:
            if isa(use.operation, memref.CopyOp):
                return self._get_variable_name_for(use.operation.destination)

    def _print_call(self, tgt, args, results):
        self.print(f"call {tgt.string_value()}(", end="")
        for idx, arg in enumerate(args):
            if idx > 0: self.print(", ", end="", use_prefix=False)
            self.print(self._get_variable_name_for(arg), end="", use_prefix=False)

        for idx, res in enumerate(results, start=len(args)):
            if idx > 0: self.print(", ", end="", use_prefix=False)
            self.print(self.get_call_result_var_ssa(res), end="", use_prefix=False)

        self.print(")", use_prefix=False)

    def _print_if(
        self,
        conditional,
        true_bdy: Region,
        false_bdy: Region,
    ):
        self.print("if (", end="")
        self.print_expr(conditional.owner)
        self.print(") then", use_prefix=False)

        with self.descend() as inner:
            inner.print_block(true_bdy)

        if len(false_bdy.blocks) > 0:
            self.print("else")
            with self.descend() as inner:
                inner.print_block(false_bdy)

        self.print("end if")

    def _print_fn(
        self,
        name: StringAttr,
        bdy: Region,
        ftyp: FunctionType,
    ):
        """
        Shared printing logic for printing tasks and functions.
        """
        args = ", ".join(
            f"arg_{idx}"
            for idx, arg in enumerate(ftyp.inputs.data + ftyp.outputs.data)
        )
        ret = (
            "void"
            #if len(ftyp.outputs) == 0
            #else self.mlir_type_to_csl_type(ftyp.outputs.data[0])
        )
        start_signature = f"\nsubroutine {name.data}({args})"
        end_signature = f"end subroutine {name.data}"
        with self.descend(start_signature, end_signature) as inner:
            # Register block args (in/inout args) as arg_0, arg_1, ...
            for idx, arg in enumerate(bdy.block.args):
                inner.variables[arg] = f"arg_{idx}"

            # Register alloca results (out args) by scanning ReturnOp
            n_inputs = len(ftyp.inputs.data)
            for op in bdy.block.ops:
                if isa(op, func.ReturnOp):
                    for ret_idx, ret_val in enumerate(op.arguments):
                        if isa(ret_val.owner, memref.AllocaOp):
                            inner.variables[ret_val] = f"arg_{n_inputs + ret_idx}"
                    break

            for idx, in_arg in enumerate(ftyp.inputs.data):
                inner.print(f"{self.mlir_type_to_ftn_type(in_arg)}, intent(in) :: arg_{idx}")

            for idx, out_arg in enumerate(ftyp.outputs.data, start=len(ftyp.inputs.data)):
                inner.print(f"{self.mlir_type_to_ftn_type(out_arg)}, intent(out) :: arg_{idx}")

            inner.print("")

            inner.print_block(bdy.block)

    @contextmanager
    def descend(self, block_start: str = None, block_end: str = None):
        """
        Get a sub-context for descending into nested structures.

        Variables defined outside are valid inside, but inside varaibles will be
        available outside.

        The code printed in this context will be surrounded by curly braces and
        can optionally start with a `block_start` statement (e.g. function
        siganture or the `comptime` keyword).

        To be used in a `with` statement like so:
        ```
        with self.descend() as inner_context:
            inner_context.print()
        ```

        NOTE: `_symbols_to_export` is passed as a reference, so the sub-context
        could in theory modify the parent's list of exported symbols, in
        practice this should not happen as `SymbolExportOp` has been verified to
        only be present at module scope.
        """
        if block_start is not None:
            self.print(f"{block_start} ")
        yield ftnPrintContext(
            output=self.output,
            variables=self.variables.copy(),
            #_symbols_to_export=self._symbols_to_export,
            _cmp_ops=self._cmp_ops,
            _binops=self._binops,
            _counter=self._counter,
            _prefix=self._prefix + self._INDENT,
        )
        if block_end is not None:
            self.print(f"{block_end} ")

    def print(self, text: str, prefix: str = "", end: str = "\n", use_prefix=True):
        """
        Print `text` line by line, prefixed by self._prefix and prefix.
        """
        for l in text.split("\n"):
            print((self._prefix + prefix if use_prefix else "") + l, file=self.output, end=end)

    def print_block(self, body: Block):
        """
        Walks over a block and prints every operation in the block.
        """
        for op in body.ops:
            self.print_op(op)

def get_modules_in_module_op(module: ModuleOp):
    for op in module.body.ops:
        if isinstance(op, builtin.ModuleOp):
            yield op


def print_to_ftn(
    prog: ModuleOp, output: IO[str], Ctx: type[ftnPrintContext] = ftnPrintContext
):
    ctx = Ctx(output)
    ctx.register_binops()
    divider = False
    for module in get_modules_in_module_op(prog):
        if divider:
            ctx.print("// -----")
        divider = True
        ctx.print("// FILE: " + module.sym_name.data+".F90")
        ctx.print_op(module)
