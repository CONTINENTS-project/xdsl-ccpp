from __future__ import annotations

from contextlib import contextmanager
from dataclasses import dataclass, field
from typing import IO, cast

from xdsl.dialects import arith, builtin, func, llvm, memref, scf
from xdsl.dialects.builtin import (
    DYNAMIC_INDEX,
    DenseIntOrFPElementsAttr,
    Float32Type,
    Float64Type,
    FloatAttr,
    FunctionType,
    IntAttr,
    IntegerAttr,
    IntegerType,
    MemRefType,
    ModuleOp,
    StringAttr,
)
from xdsl.ir import (
    Attribute,
    Block,
    BlockArgument,
    Operation,
    OpResult,
    Region,
    SSAValue,
)
from xdsl.utils.hints import isa

from xdsl_ccpp.backend import print_constituents
from xdsl_ccpp.dialects.ccpp_utils import AllocateOp as CCPPAllocateOp
from xdsl_ccpp.dialects.ccpp_utils import ArraySectionOp as CCPPArraySectionOp
from xdsl_ccpp.dialects.ccpp_utils import DeallocateOp as CCPPDeallocateOp
from xdsl_ccpp.dialects.ccpp_utils import DerivedType as CCPPDerivedType
from xdsl_ccpp.dialects.ccpp_utils import FortranExprOp as CCPPFortranExprOp
from xdsl_ccpp.dialects.ccpp_utils import HostConstituentsOp as CCPPHostConstituentsOp
from xdsl_ccpp.dialects.ccpp_utils import HostVarRefOp as CCPPHostVarRefOp
from xdsl_ccpp.dialects.ccpp_utils import KeywordCallOp as CCPPKeywordCallOp
from xdsl_ccpp.dialects.ccpp_utils import KindDefOp as CCPPKindDefOp
from xdsl_ccpp.dialects.ccpp_utils import PackConstituentsOp as CCPPPackConstituentsOp
from xdsl_ccpp.dialects.ccpp_utils import PointerAssociateOp as CCPPPointerAssociateOp
from xdsl_ccpp.dialects.ccpp_utils import PointerDeclOp as CCPPPointerDeclOp
from xdsl_ccpp.dialects.ccpp_utils import PointerNullifyOp as CCPPPointerNullifyOp
from xdsl_ccpp.dialects.ccpp_utils import RealKindType as CCPPRealKindType
from xdsl_ccpp.dialects.ccpp_utils import SetStringOp as CCPPSetStringOp
from xdsl_ccpp.dialects.ccpp_utils import StrCmpOp as CCPPStrCmpOp
from xdsl_ccpp.dialects.ccpp_utils import SuiteConstituentsOp as CCPPSuiteConstituentsOp
from xdsl_ccpp.dialects.ccpp_utils import SuiteVariablesFnOp as CCPPSuiteVariablesFnOp
from xdsl_ccpp.dialects.ccpp_utils import SuiteVarOp as CCPPSuiteVarOp
from xdsl_ccpp.dialects.ccpp_utils import TrimOp as CCPPTrimOp
from xdsl_ccpp.dialects.ccpp_utils import WriteErrMsgOp as CCPPWriteErrMsgOp

_MAX_LINE_LEN = 99
_OPERATORS = (" .or. ", " .and. ")


@dataclass
class ftnPrintContext:
    """Stateful context for printing MLIR IR as Fortran source text.

    Each context owns an indentation prefix and a mapping from SSA values to
    Fortran variable names.  Nested structures (subroutines, if-blocks, etc.)
    are handled by creating a child context via `descend`, which inherits the
    current variable map and adds one level of indentation.
    """

    _INDEX = "i32"
    _INDENT = "  "
    output: IO[str]

    # Current indentation string prepended to every line
    _prefix: str = field(default="")

    # Map from SSA value to its Fortran variable name
    variables: dict[SSAValue, str] = field(default_factory=dict[SSAValue, str])

    # Counter used to generate unique fallback variable names
    _counter: int = field(default=0)

    # Buffer accumulating the current line being built via partial print() calls
    _line_buf: str = field(default="")

    # Maps arith op names to their Fortran infix operator strings
    _binops: dict[str, str] = field(default_factory=dict[str, str])

    # Maps comparison op names to a predicate-string → Fortran-operator dict
    _cmp_ops: dict[str, dict[str, str | None]] = field(
        default_factory=dict[str, dict[str, str | None]]
    )

    # Tracks how many times each allocatable char array has been stored to.
    # Key: id of the SSA value; value: 1-based index of the next store.
    # Used to emit allocate(arr(N)) once and suites(i) = ... with correct indices.
    _allocatable_store_indices: dict = field(default_factory=dict)

    def register_binops(self):
        """Populate the binary-operator and comparison-operator lookup tables.

        Must be called once before printing begins.  Kept separate from
        __init__ so that child contexts created by `descend` can share the
        already-populated dicts without re-building them.
        """
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
        """Return the Fortran variable name assigned to an SSA value.

        If the value has already been assigned a name it is returned directly.
        Otherwise a new name is chosen, preferring the value's name_hint (or
        the caller-supplied hint), and falling back to a numbered prefix when
        the hint is absent or already taken.
        """
        if val in self.variables:
            return self.variables[val]

        taken_names = set(self.variables.values())

        if hint is None:
            hint = val.name_hint

        if hint is not None and hint not in taken_names:
            name = hint
        else:
            # Generate a unique name using a numeric suffix
            prefix = "v" if val.name_hint is None else val.name_hint

            name = f"{prefix}{self._counter}"
            self._counter += 1

            while name in taken_names:
                name = f"{prefix}{self._counter}"
                self._counter += 1

        self.variables[val] = name
        return name

    @staticmethod
    def _is_allocatable_char(type_attr: Attribute) -> bool:
        """Return True if type_attr is memref<memref<?xi8>> (allocatable character array)."""
        match type_attr:
            case MemRefType(
                element_type=MemRefType(element_type=IntegerType(width=IntAttr(data=8)))
            ):
                return True
            case _:
                return False

    def mlir_type_to_ftn_type(self, type_attr: Attribute) -> str:
        """Convert an MLIR type attribute to its Fortran type declaration string.

        Supported types:
          - f32 / f64       → real(kind=4) / real(kind=8)
          - i1              → logical
          - i8              → character
          - i32             → integer
          - memref<T>       → the Fortran type of T (scalar, no dimensions)
          - memref<NxT>     → character(len=N) for character, T(N) otherwise
        """
        match type_attr:
            case CCPPDerivedType() as dt:
                return f"type({dt.type_name.data})"
            case CCPPRealKindType() as rkt:
                return f"real(kind={rkt.kind_name.data})"
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
                return "integer"
            case MemRefType(
                element_type=IntegerType(width=IntAttr(data=8)), shape=shape
            ) if len(shape) >= 1:
                # The leading dimension of an i8 memref is the character length,
                # with any array dimensions after it. A dynamic length is an
                # assumed-length argument, declared as character(len=*).
                length = next(iter(shape)).data
                return f"character(len={'*' if length == DYNAMIC_INDEX else length})"
            case MemRefType(element_type=Attribute() as elem_t, shape=shape):
                if any(dim.data == DYNAMIC_INDEX for dim in shape):
                    # Dynamic-dimension array: return only the base type string.
                    # The caller uses _ftn_dim_suffix to append '(:, :)' etc. to
                    # the variable name in the declaration.
                    return self.mlir_type_to_ftn_type(elem_t)
                shape_str = ", ".join(str(s.data) for s in shape)
                type_str = self.mlir_type_to_ftn_type(elem_t)
                if not shape_str:
                    # Zero-dimensional memref — treat as a plain scalar
                    return type_str
                elif type_str == "character":
                    # Character length is expressed with len= rather than dimensions
                    return f"{type_str}(len={shape_str})"
                else:
                    return f"{type_str}({shape_str})"

    def _ftn_dim_suffix(self, type_attr: Attribute) -> str:
        """Return the Fortran assumed-shape array suffix for a memref type.

        For a memref with N dynamic dimensions this returns ``"(:, :, ...)"``
        (N colons), which is appended to the variable name in a declaration to
        produce e.g. ``real(kind=8), intent(inout) :: temp_level(:, :)``.

        Returns an empty string for scalar types and statically-sized memrefs
        (such as ``character(len=512)``).
        """
        if self._is_allocatable_char(type_attr):
            return "(:)"
        match type_attr:
            case MemRefType(
                element_type=IntegerType(width=IntAttr(data=8)), shape=shape
            ):
                # The character length is part of the type, so only the array
                # dimensions after it become a suffix
                rank = len(shape) - 1
                return (
                    "(" + ", ".join(":" for _ in range(rank)) + ")" if rank > 0 else ""
                )
            case MemRefType(shape=shape) if any(
                dim.data == DYNAMIC_INDEX for dim in shape
            ):
                # One ':' per dynamic dimension
                return "(" + ", ".join(":" for _ in shape) + ")"
            case _:
                return ""

    def attribute_value_to_str(self, attr: Attribute) -> str:
        """Convert a value-carrying attribute to a Fortran literal string.

        Handles integer, float, string, and dense element attributes.
        Returns a diagnostic placeholder for unrecognised attribute kinds.
        """
        match attr:
            case IntAttr():
                return str(cast(IntAttr[int], attr).data)
            case IntegerAttr(value=val, type=IntegerType(width=IntAttr(data=1))):
                # i1 values are printed as Fortran logical literals
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
        """Print value_expr directly as an inline expression (no newline)."""
        self.print(f"{value_expr}", end="", use_prefix=False)

    def _value_to_expr_str(self, val: SSAValue) -> str:
        """Return the Fortran expression string for an SSA value without printing.

        Checks the variable map first, then falls back to reading the literal
        value for arith.ConstantOp results, and finally generates a fresh name.
        """
        if val in self.variables:
            return self.variables[val]
        if isa(val.owner, arith.ConstantOp):
            return self.attribute_value_to_str(val.owner.value)
        return self._get_variable_name_for(val)

    def find_ret_ssa_idx(self, ret_op, ssa):
        """Return the index of ssa in ret_op's argument list, or None."""
        for idx, arg in enumerate(ret_op.arguments):
            if arg == ssa:
                return idx
        return None

    def print_expr(self, op: Operation):
        """Recursively print op as an inline Fortran expression (no newline).

        Only operations that can appear as sub-expressions are handled here.
        Statement-level operations are handled by print_op instead.
        """
        match op:
            case arith.ConstantOp(value=v, result=r):
                # Emit the literal value of the constant
                self._print_or_promote_to_inline_expr(r, self.attribute_value_to_str(v))
            case memref.LoadOp(memref=arr):
                # A load from a memref is represented by the variable name itself
                self.print(self._get_variable_name_for(arr), end="", use_prefix=False)
            case arith.CmpiOp(predicate=v, lhs=l, rhs=r):
                # Emit lhs <op> rhs using the Fortran comparison operator
                str_pred = arith.CMPI_COMPARISON_OPERATIONS[v.value.data]
                self.print_expr(l.owner)
                self.print(
                    f" {self._cmp_ops[op.name][str_pred]} ", end="", use_prefix=False
                )
                self.print_expr(r.owner)
            case arith.XOrIOp():
                # XOrI(x, 1_i1) is a logical NOT; detect which operand is the constant
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
                    # General XOR — emit as logical inequality
                    self.print_expr(l.owner)
                    self.print(" .neqv. ", end="", use_prefix=False)
                    self.print_expr(r.owner)
            case CCPPTrimOp():
                lhs_name = self._get_variable_name_for(op.lhs)
                self.print(f"trim({lhs_name})", end="", use_prefix=False)
            case CCPPFortranExprOp():
                self.print(op.text.data, end="", use_prefix=False)
            case CCPPStrCmpOp():
                if op.literal is not None:
                    self.print_expr(op.lhs.owner)
                    self.print(f" .eq. '{op.literal.data}'", end="", use_prefix=False)
                else:
                    lhs_name = self._get_variable_name_for(op.lhs)
                    rhs_name = self._get_variable_name_for(op.rhs)
                    self.print(f"{lhs_name} .eq. {rhs_name}", end="", use_prefix=False)
            case arith.AddiOp():
                self.print_expr(op.lhs.owner)
                self.print(" + ", end="", use_prefix=False)
                self.print_expr(op.rhs.owner)
            case arith.SubiOp():
                self.print_expr(op.lhs.owner)
                self.print(" - ", end="", use_prefix=False)
                self.print_expr(op.rhs.owner)
            case _:
                raise AssertionError(f"Unhandled op in print_expr: {type(op)}")

    def print_op(self, op: Operation):
        """Dispatch an MLIR operation to the appropriate Fortran printer.

        Operations that produce values but emit no Fortran statement (e.g.
        address-of, load) register names in the variables dict and return
        silently.  Operations that have no Fortran equivalent (e.g. alloca,
        global declarations, yield) are skipped with a pass.
        """
        match op:
            case builtin.ModuleOp(attributes={"ftn_source": StringAttr(data=text)}):
                # A module written out in full, such as a static API
                print(text.rstrip("\n"), file=self.output)
            case builtin.ModuleOp(sym_name=name, body=bdy):
                self._print_module(name, bdy)
            case memref.AllocaOp():
                pass  # Variable registration is handled up-front in _print_fn
            case llvm.GlobalOp():
                pass  # Module-level globals are declared in _print_module preamble
            case llvm.AddressOfOp():
                # Record the global's name as the variable name for this result
                self.variables[op.result] = op.global_name.root_reference.data
            case llvm.LoadOp():
                # Propagate the pointer's name to the loaded value
                self.variables[op.dereferenced_value] = self._get_variable_name_for(
                    op.ptr
                )
            case llvm.StoreOp():
                if isa(op.ptr.type, MemRefType):
                    # Storing a loaded string value into a memref<?xi8> buffer:
                    # suppress output here — the Fortran assignment is emitted by
                    # the memref.StoreOp that places the buffer into the allocatable.
                    pass
                else:
                    # Emit a Fortran assignment from the source value to the destination
                    dst_name = self._get_variable_name_for(op.ptr)
                    src_name = self._get_variable_name_for(op.value)
                    self.print(f"{dst_name} = {src_name}")
            case func.FuncOp(sym_name=name, body=bdy, function_type=ftyp):
                # Skip external declarations; only print subroutine definitions
                if not op.is_declaration:
                    self._print_fn(name, bdy, ftyp)
            case func.CallOp() if "ftn_arg_names" in op.attributes:
                self._print_named_call(op)
            case func.CallOp(callee=tgt, arguments=args, res=results):
                self._print_call(tgt, args, results)
            case CCPPKeywordCallOp():
                self._print_kw_call(op)
            case scf.IfOp(
                cond=conditional, true_region=true_bdy, false_region=false_bdy
            ):
                self._print_if(conditional, true_bdy, false_bdy)
            case scf.ForOp():
                self._print_for(op)
            case CCPPFortranExprOp():
                self.variables[op.res] = op.text.data
            case CCPPSuiteVarOp():
                pass  # Module variables are declared in _print_module preamble
            case CCPPAllocateOp():
                name = self._get_variable_name_for(op.var)
                bounds = ", ".join(
                    f"{self._value_to_expr_str(lower)}:{self._value_to_expr_str(upper)}"
                    for lower, upper in zip(op.lowers, op.uppers)
                )
                self.print(f"if (.not. allocated({name})) then")
                self.print(f"  allocate({name}({bounds}))")
                if op.initial_value is not None:
                    self.print(f"  {name} = {op.initial_value.data}")
                self.print("end if")
            case CCPPDeallocateOp():
                name = self._get_variable_name_for(op.var)
                self.print(f"if (allocated({name})) deallocate({name})")
            case CCPPSuiteVariablesFnOp():
                self._print_suite_variables_fn(op)
            case CCPPPointerDeclOp():
                pass  # Declared with the other locals in _print_fn
            case CCPPPointerAssociateOp():
                pointer = self._get_variable_name_for(op.pointer)
                self.print(f"{pointer} => {self._value_to_expr_str(op.target)}")
            case CCPPPointerNullifyOp():
                self.print(f"nullify({self._get_variable_name_for(op.pointer)})")
            case CCPPSuiteConstituentsOp():
                self._print_lines(print_constituents.suite_routines(op))
            case CCPPHostConstituentsOp():
                self._print_lines(print_constituents.host_routines(op))
            case CCPPPackConstituentsOp():
                self._print_lines(print_constituents.pack_lines(op))
            case memref.AllocOp():
                pass  # Heap allocations are emitted via the StoreOp that uses the result
            case CCPPKindDefOp():
                pass  # Kind definitions are declared in _print_module preamble
            case CCPPTrimOp():
                pass  # Used only as a sub-expression; printed inline by print_expr
            case CCPPSetStringOp():
                # Register the source global name as the variable name for dest
                # so that the memref.StoreOp into the allocatable can find it.
                src_name = self._get_variable_name_for(op.src)
                self.variables[op.dest] = src_name
            case memref.StoreOp(value=val, memref=arr, indices=idxs):
                if self._is_allocatable_char(arr.type) and isa(
                    val.owner, memref.AllocOp
                ):
                    # Storing a memref<?xi8> (string buffer) into memref<memref<?xi8>>
                    # (the allocatable out arg).  On the first store emit
                    # allocate(arr(N)) where N is the total number of such stores in
                    # this block; then emit arr(i) = string_src for each store.
                    arr_name = self._get_variable_name_for(arr)
                    string_src = self.variables.get(val)
                    key = id(arr)
                    if key not in self._allocatable_store_indices:
                        total = sum(
                            1
                            for sibling in op.parent.ops
                            if isa(sibling, memref.StoreOp)
                            and sibling.memref is arr
                            and isa(sibling.value.owner, memref.AllocOp)
                        )
                        self._allocatable_store_indices[key] = (1, total)
                        self.print(f"allocate({arr_name}({total}))")
                    idx, total = self._allocatable_store_indices[key]
                    self._allocatable_store_indices[key] = (idx + 1, total)
                    if string_src is not None:
                        self.print(f"{arr_name}({idx}) = {string_src}")
                else:
                    arr_name = self._get_variable_name_for(arr)
                    idx_args = ", ".join(map(self._get_variable_name_for, idxs))
                    if len(idx_args) > 0:
                        self.print(f"{arr_name}[{idx_args}] = ", end="")
                    else:
                        self.print(f"{arr_name} = ", end="")
                    if isinstance(val, BlockArgument):
                        # e.g. the index of a loop
                        self.print(
                            self._get_variable_name_for(val), end="", use_prefix=False
                        )
                    else:
                        self.print_expr(val.owner)
                    self.print("")
            case CCPPHostVarRefOp():
                # Register the host variable name for the result — no Fortran emitted
                self.variables[op.res] = op.var_name.data
            case CCPPWriteErrMsgOp():
                dest_name = self._get_variable_name_for(op.dest)
                self.print(f"write({dest_name}, '(3a)') \"{op.prefix.data}\", ", end="")
                self.print_expr(op.var.owner)
                self.print(f', "{op.suffix.data}"', use_prefix=False)
            case CCPPArraySectionOp():
                # Register the full Fortran array-section expression as the
                # result's variable name so call-site printing emits it inline.
                source_name = self._value_to_expr_str(op.source)
                parts = []
                for lower, upper in zip(op.lowers, op.uppers):
                    lower_str = self._value_to_expr_str(lower)
                    upper_str = self._value_to_expr_str(upper)
                    if lower is upper:
                        parts.append(lower_str)
                    else:
                        parts.append(f"{lower_str}:{upper_str}")
                self.variables[op.res] = f"{source_name}({', '.join(parts)})"
            case builtin.UnrealizedConversionCastOp():
                # Type annotation cast — transparent to Fortran; map each result
                # to the same variable name as the corresponding input operand.
                for result, operand in zip(op.results, op.inputs):
                    self.variables[result] = self._get_variable_name_for(operand)

    # ISO_FORTRAN_ENV named constants recognised as kind values
    _ISO_FORTRAN_ENV_KINDS: frozenset[str] = frozenset(
        {
            "REAL32",
            "REAL64",
            "REAL128",
            "INT8",
            "INT16",
            "INT32",
            "INT64",
        }
    )

    def _print_module(self, module_name, body):
        """Print a builtin.ModuleOp as a Fortran module block.

        The preamble contains:
          - use ccpp_kinds (skipped for the ccpp_kinds module itself)
          - use iso_fortran_env if any KindDefOp values are ISO constants
          - use <module>, only: <name> lines for external declarations
          - implicit none / private defaults
          - integer, parameter declarations for every KindDefOp
          - character variable declarations for every llvm.GlobalOp
          - a public :: line for each subroutine definition marked public
        The CONTAINS section follows only when subroutine definitions are present.
        """
        assert module_name is not None
        is_kinds_module = module_name.data == "ccpp_kinds"

        self.print(f"module {module_name.data}")

        # The ccpp_kinds module must not use itself (circular dependency), and is
        # not generated when the host defines all of the kinds
        if (
            not is_kinds_module
            and "ftn_no_ccpp_kinds" not in body.parent_op().attributes
        ):
            self.print("\nuse ccpp_kinds", prefix="  ")

        # For the ccpp_kinds module, emit ISO_FORTRAN_ENV renames:
        #   use ISO_FORTRAN_ENV, only: kind_phys => REAL64
        # This imports and re-exports each kind under its CCPP name in one step.
        if is_kinds_module:
            iso_renames = ", ".join(
                f"{op.kind_name.data} => {op.kind_value.data}"
                for op in body.ops
                if isa(op, CCPPKindDefOp)
                and op.kind_value.data in self._ISO_FORTRAN_ENV_KINDS
            )
            if iso_renames:
                self.print(f"use ISO_FORTRAN_ENV, only: {iso_renames}", prefix="  ")

        # Emit 'use <module>, only: <name>' lines.  Two sources:
        #   1. External FuncOps with a 'module' attribute (suite cap callees).
        #   2. llvm.GlobalOp stubs with a 'module' attribute (host model vars).
        use_map: dict[str, list[str]] = {}
        for op in body.ops:
            if isa(op, func.FuncOp) and op.is_declaration and "module" in op.attributes:
                mod = op.attributes["module"].data
                use_map.setdefault(mod, []).append(op.sym_name.data)
            elif isa(op, llvm.GlobalOp) and "module" in op.attributes:
                mod = op.attributes["module"].data
                use_map.setdefault(mod, []).append(op.sym_name.data)
        # 3. Types and procedures that the constituent routines need.
        for op in body.ops:
            if isa(op, CCPPSuiteConstituentsOp):
                uses = print_constituents.suite_uses(op)
            elif isa(op, CCPPHostConstituentsOp):
                uses = print_constituents.host_uses(op)
            else:
                continue
            for mod, name in uses:
                use_map.setdefault(mod, []).append(name)
        # 4. Derived types used by declarations in this module.
        module_op = body.parent_op()
        if "ftn_type_uses" in module_op.attributes:
            for type_name, mod in module_op.attributes["ftn_type_uses"].data.items():
                use_map.setdefault(mod.data, []).append(type_name)
        for mod, procs in sorted(use_map.items()):
            for proc in sorted(set(procs)):
                self.print(f"use {mod}, only: {proc}", prefix="  ")

        self.print("\nimplicit none", prefix="  ")
        self.print("private", prefix="  ")
        self.print("")

        # Emit 'public :: kind_name' for each kind (the rename in the use statement
        # above already brings the name into scope; only visibility needs declaring).
        for op in body.ops:
            if isa(op, CCPPKindDefOp):
                self.print(f"public :: {op.kind_name.data}", prefix="  ")

        # Emit module-level character variable declarations for each LLVM global.
        # Globals with a 'module' attribute are USE-associated (already emitted
        # above as 'use' lines) and must not be re-declared here.
        for op in body.ops:
            if isa(op, llvm.GlobalOp) and "module" not in op.attributes:
                name = op.sym_name.data
                val = op.value.data if isa(op.value, StringAttr) else ""
                is_const = op.constant is not None
                # Derive character length from the LLVM array type when available
                char_len: int | str = 16
                if isa(op.global_type, llvm.LLVMArrayType):
                    char_len = cast(llvm.LLVMArrayType, op.global_type).size.data
                if is_const:
                    # Read-only string constants use the parameter attribute
                    self.print(
                        f"character(len={char_len}), parameter :: {name} = '{val}'",
                        prefix="  ",
                    )
                else:
                    # Mutable state variable (ccpp_suite_state) has no parameter
                    self.print(
                        f"character(len={char_len}) :: {name} = '{val}'", prefix="  "
                    )

        # Emit the module variables that hold suite data
        for op in body.ops:
            if isa(op, CCPPSuiteVarOp):
                type_str = self.mlir_type_to_ftn_type(op.var_type)
                dim_suffix = self._ftn_dim_suffix(op.var_type)
                if dim_suffix:
                    type_str += ", allocatable"
                initial = ""
                if op.initial_value is not None and not dim_suffix:
                    initial = f" = {op.initial_value.data}"
                self.print(
                    f"{type_str} :: {op.var_name.data}{dim_suffix}{initial}",
                    prefix="  ",
                )

        for op in body.ops:
            if isa(op, CCPPSuiteConstituentsOp):
                self._print_lines(print_constituents.suite_declarations(op), "  ")
            elif isa(op, CCPPHostConstituentsOp):
                self._print_lines(print_constituents.host_declarations(op), "  ")

        # Emit one public :: line per subroutine definition that is marked public.
        public_procs = [
            op.sym_name.data
            for op in body.ops
            if (
                isa(op, func.FuncOp)
                and not op.is_declaration
                and op.sym_visibility is not None
                and op.sym_visibility.data == "public"
            )
        ]
        if any(isa(op, CCPPSuiteVariablesFnOp) for op in body.ops):
            public_procs.append("ccpp_physics_suite_variables")
        for proc in public_procs:
            self.print(f"public :: {proc}", prefix="  ")

        # Only emit CONTAINS when there are subroutine definitions to print
        has_func_defs = any(
            (isa(op, func.FuncOp) and not op.is_declaration)
            or isinstance(op, (CCPPSuiteConstituentsOp, CCPPHostConstituentsOp))
            for op in body.ops
        )
        if has_func_defs:
            self.print("\nCONTAINS")
            with self.descend() as inner:
                inner.print_block(body)

        self.print(f"end module {module_name.data}")

    def get_call_result_var_ssa(self, res_ssa):
        """Resolve a call result SSA value to the Fortran variable it writes into.

        After a scheme subroutine call the MLIR IR contains a memref.CopyOp
        that copies each result into its destination storage.  This method
        follows that use edge to find the destination variable name.  If no
        CopyOp is found the result was pre-registered as an anonymous local by
        _print_fn and its name is looked up directly in self.variables.
        """
        for use in res_ssa.uses:
            if isa(use.operation, memref.CopyOp):
                return self._get_variable_name_for(use.operation.destination)
            if isa(use.operation, builtin.UnrealizedConversionCastOp):
                return self.get_call_result_var_ssa(use.operation.results[0])
        # No CopyOp — must have been pre-registered as an anonymous local
        return self.variables.get(res_ssa)

    def _print_named_call(self, op: func.CallOp):
        """Print a func.CallOp whose dummy argument names are known.

        An inout argument is both an operand and a result, and is printed once.
        """
        actuals = {}
        for name, arg in zip(op.attributes["ftn_arg_names"].data, op.arguments):
            actuals[name.data] = self._get_variable_name_for(arg)
        for name, res in zip(op.attributes["ftn_result_names"].data, op.res):
            if name.data not in actuals:
                actuals[name.data] = self.get_call_result_var_ssa(res)
        args_str = ", ".join(f"{name}={val}" for name, val in actuals.items())
        self.print(f"call {op.callee.string_value()}({args_str})")

    def _print_call(self, tgt, args, results):
        """Print a func.CallOp as a Fortran subroutine call statement.

        Input arguments are printed by variable name.  Output arguments are
        resolved through the CopyOp use-chain to find the destination variable
        that will receive each result.
        """
        self.print(f"call {tgt.string_value()}(", end="")
        # Print input (in / inout) arguments by their variable names
        for idx, arg in enumerate(args):
            if idx > 0:
                self.print(", ", end="", use_prefix=False)
            self.print(self._get_variable_name_for(arg), end="", use_prefix=False)

        # Print output argument destinations, resolved via CopyOp uses
        for idx, res in enumerate(results, start=len(args)):
            if idx > 0:
                self.print(", ", end="", use_prefix=False)
            self.print(self.get_call_result_var_ssa(res), end="", use_prefix=False)

        self.print(")", use_prefix=False)

    def _print_kw_call(self, op: CCPPKeywordCallOp):
        """Print a ccpp_utils.kw_call as a Fortran keyword-argument subroutine call.

        Compile-time literal overrides are emitted first as ``name=literal``,
        then SSA input operands as ``name=var_name``, then SSA output results
        as ``name=dest_var``.  Inout arguments (present in both operand_names
        and result_names) are deduplicated via a seen-names set.
        """
        self.print(f"call {op.callee.data}(", end="")
        idx = 0
        seen: set[str] = set()
        for name, val_attr in op.overrides.data.items():
            if idx > 0:
                self.print(", ", end="", use_prefix=False)
            self.print(f"{name}={val_attr.data}", end="", use_prefix=False)
            seen.add(name)
            idx += 1
        for name_attr, arg in zip(op.operand_names.data, op.args):
            name = name_attr.data
            if name not in seen:
                if idx > 0:
                    self.print(", ", end="", use_prefix=False)
                self.print(
                    f"{name}={self._get_variable_name_for(arg)}",
                    end="",
                    use_prefix=False,
                )
                seen.add(name)
                idx += 1
        for name_attr, res in zip(op.result_names.data, op.res):
            name = name_attr.data
            if name not in seen:
                if idx > 0:
                    self.print(", ", end="", use_prefix=False)
                self.print(
                    f"{name}={self.get_call_result_var_ssa(res)}",
                    end="",
                    use_prefix=False,
                )
                seen.add(name)
                idx += 1
        self.print(")", use_prefix=False)

    def _print_if(
        self,
        conditional,
        true_bdy: Region,
        false_bdy: Region,
    ):
        """Print an scf.IfOp as a Fortran if / else / end if block."""
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

    def _print_for(self, op: scf.ForOp):
        """Print an scf.ForOp as a Fortran do loop."""
        index = op.body.block.args[0]
        name = self._get_variable_name_for(index)
        lower = self._value_to_expr_str(op.lb)
        upper = self._value_to_expr_str(op.ub)
        self.print(f"do {name} = {lower}, {upper}")
        with self.descend() as inner:
            inner.print_block(op.body.block)
        self.print("end do")

    def _print_lines(self, lines: list[str], prefix: str = ""):
        """Print lines of Fortran that were generated elsewhere."""
        for line in lines:
            self.print(line, prefix=prefix)

    def _print_suite_variables_fn(self, op: CCPPSuiteVariablesFnOp):
        """Print ccpp_physics_suite_variables, listing what each suite needs."""
        lines = [
            "subroutine ccpp_physics_suite_variables(suite_name, variable_list, "
            "errmsg, errflg, input_vars, output_vars, struct_elements)",
            "  character(len=*), intent(in) :: suite_name",
            "  character(len=*), allocatable, intent(out) :: variable_list(:)",
            "  character(len=512), intent(out) :: errmsg",
            "  integer, intent(out) :: errflg",
            "  logical, optional, intent(in) :: input_vars",
            "  logical, optional, intent(in) :: output_vars",
            "  logical, optional, intent(in) :: struct_elements",
            "  logical :: use_inputs, use_outputs",
            "  integer :: index",
            "",
            "  errflg = 0",
            "  errmsg = ''",
            "  use_inputs = .true.",
            "  if (present(input_vars)) use_inputs = input_vars",
            "  use_outputs = .true.",
            "  if (present(output_vars)) use_outputs = output_vars",
        ]
        keyword = "if"
        for suite_name, lists in op.variables.data.items():
            inputs, outputs = ([name.data for name in names] for names in lists)
            both = [name for name in inputs if name in outputs]
            only_inputs = [name for name in inputs if name not in outputs]
            only_outputs = [name for name in outputs if name not in inputs]
            all_names = len(both) + len(only_inputs) + len(only_outputs)
            lines += [
                f"  {keyword} (trim(suite_name) == '{suite_name}') then",
                "    if (use_inputs .and. use_outputs) then",
                f"      allocate(variable_list({all_names}))",
                "    else if (use_inputs) then",
                f"      allocate(variable_list({len(inputs)}))",
                "    else if (use_outputs) then",
                f"      allocate(variable_list({len(outputs)}))",
                "    else",
                "      allocate(variable_list(0))",
                "    end if",
                "    index = 0",
            ]
            for condition, names in (
                ("use_inputs .or. use_outputs", both),
                ("use_inputs", only_inputs),
                ("use_outputs", only_outputs),
            ):
                lines.append(f"    if ({condition}) then")
                for name in names:
                    lines += [
                        "      index = index + 1",
                        f"      variable_list(index) = '{name}'",
                    ]
                lines.append("    end if")
            keyword = "else if"
        lines += [
            "  else",
            "    write(errmsg, '(3a)') 'No suite named ', trim(suite_name), ' found'",
            "    errflg = 1",
            "  end if",
            "end subroutine ccpp_physics_suite_variables",
        ]
        self.print("")
        for line in lines:
            self.print(line)

    def _print_fn(
        self,
        fn_name: StringAttr,
        bdy: Region,
        ftyp: FunctionType,
    ):
        """Print a func.FuncOp definition as a Fortran subroutine.

        Argument names are taken from the name_hint set on each block argument
        and alloca result during IR generation, falling back to positional
        names if no hint is present.

        The ReturnOp is scanned to detect inout arguments (block args that
        appear in the return list) so they can be declared intent(inout) rather
        than the default intent(in).  Pure output arguments come from AllocaOp
        results also present in the return list.
        """
        # Collect input arg names from block arg name hints
        input_names = [
            arg.name_hint if arg.name_hint is not None else f"arg_{idx}"
            for idx, arg in enumerate(bdy.block.args)
        ]

        # Scan ReturnOp to separate output allocas from returned inout block args
        output_names: list[str] = []
        output_ret_vals: list = []
        inout_block_args: set = set()
        for op in bdy.block.ops:
            if isa(op, func.ReturnOp):
                for ret_val in op.arguments:
                    if isa(ret_val.owner, memref.AllocaOp):
                        # AllocaOp result → a true output argument
                        out_name = (
                            ret_val.name_hint
                            if ret_val.name_hint is not None
                            else f"out_{len(output_names)}"
                        )
                        output_names.append(out_name)
                        output_ret_vals.append(ret_val)
                    else:
                        # Block arg in return position → inout argument
                        inout_block_args.add(ret_val)
                break

        # Collect local allocas — AllocaOps whose result is not in the return list
        local_allocas = [
            op
            for op in bdy.block.ops
            if isa(op, memref.AllocaOp) and op.memref not in output_ret_vals
        ]

        # Collect call results that have no CopyOp consumer — they become anonymous locals
        # (e.g. DDT outputs from init that the ccpp_cap doesn't route anywhere).
        # Also look one level through UnrealizedConversionCastOp (inserted for type mismatches).
        def _has_copy_consumer(ssa):
            for u in ssa.uses:
                if isa(u.operation, memref.CopyOp):
                    return True
                if isa(u.operation, builtin.UnrealizedConversionCastOp):
                    if any(
                        isa(u2.operation, memref.CopyOp)
                        for u2 in u.operation.results[0].uses
                    ):
                        return True
            return False

        untracked_call_results: list[tuple[OpResult, str]] = []
        for nested_op in bdy.block.walk():
            if not isa(nested_op, func.CallOp) and not isa(
                nested_op, CCPPKeywordCallOp
            ):
                continue
            inout_results = set()
            if "ftn_arg_names" in nested_op.attributes:
                # A result that is also an operand is the same actual argument
                arg_names = nested_op.attributes["ftn_arg_names"].data
                result_names = nested_op.attributes["ftn_result_names"].data
                inout_results = {
                    res
                    for res, name in zip(nested_op.results, result_names)
                    if name in arg_names
                }
            for res in nested_op.results:
                has_copy = _has_copy_consumer(res)
                if not has_copy and res not in inout_results:
                    hint = (
                        res.name_hint
                        if res.name_hint
                        else f"ccpp_tmp_{len(untracked_call_results)}"
                    )
                    untracked_call_results.append((res, hint))

        # Declare the index of each loop
        loop_indices = list(
            dict.fromkeys(
                nested_op.body.block.args[0].name_hint
                for nested_op in bdy.block.walk()
                if isa(nested_op, scf.ForOp)
            )
        )

        args_str = ", ".join(input_names + output_names)
        start_signature = f"\nsubroutine {fn_name.data}({args_str})"
        end_signature = f"end subroutine {fn_name.data}"

        with self.descend(start_signature, end_signature) as inner:
            # Register input block args so downstream ops can look them up by name
            for arg, arg_name in zip(bdy.block.args, input_names):
                inner.variables[arg] = arg_name

            # Register output alloca results so StoreOp and CallOp can resolve them
            for ret_val, out_name in zip(output_ret_vals, output_names):
                inner.variables[ret_val] = out_name

            # Declare input arguments with intent(in) or intent(inout).
            # Array block args (dynamic memref) are always intent(inout): the host
            # provides the buffer and the scheme may write to it in-place.
            # Exception: memref<memref<?xi8>> is an allocatable character array
            # passed intent(out) — the callee allocates and fills it.
            fn_attrs = bdy.parent_op().attributes
            arg_intents = (
                [intent.data for intent in fn_attrs["ftn_arg_intents"]]
                if "ftn_arg_intents" in fn_attrs
                else None
            )
            allocatable_args = (
                {name.data for name in fn_attrs["ftn_allocatable_args"]}
                if "ftn_allocatable_args" in fn_attrs
                else set()
            )
            for idx, (arg, arg_name) in enumerate(zip(bdy.block.args, input_names)):
                type_str = inner.mlir_type_to_ftn_type(arg.type)
                dim_suffix = inner._ftn_dim_suffix(arg.type)
                if ftnPrintContext._is_allocatable_char(arg.type):
                    type_str = type_str + ", allocatable"
                    intent = "out"
                elif arg_intents is not None:
                    intent = arg_intents[idx]
                    if arg_name in allocatable_args:
                        type_str = type_str + ", allocatable"
                elif dim_suffix:
                    intent = "inout"
                elif arg in inout_block_args:
                    intent = "inout"
                else:
                    intent = "in"
                inner.print(f"{type_str}, intent({intent}) :: {arg_name}{dim_suffix}")

            # Declare output arguments with intent(out) (always scalars)
            for ret_val, out_name in zip(output_ret_vals, output_names):
                type_str = inner.mlir_type_to_ftn_type(ret_val.type)
                dim_suffix = inner._ftn_dim_suffix(ret_val.type)
                inner.print(f"{type_str}, intent(out) :: {out_name}{dim_suffix}")

            # Declare local variables (non-returned allocas, e.g. computed scalars)
            for alloca_op in local_allocas:
                var_name = (
                    alloca_op.memref.name_hint
                    if alloca_op.memref.name_hint is not None
                    else f"local_{id(alloca_op)}"
                )
                inner.variables[alloca_op.memref] = var_name
                type_str = inner.mlir_type_to_ftn_type(alloca_op.memref.type)
                inner.print(f"{type_str} :: {var_name}")

            # Declare local pointers, which are disassociated until a condition holds
            for pointer_op in bdy.block.ops:
                if not isa(pointer_op, CCPPPointerDeclOp):
                    continue
                pointer = pointer_op.res
                var_name = pointer.name_hint or f"ccpp_ptr_{id(pointer_op)}"
                inner.variables[pointer] = var_name
                type_str = inner.mlir_type_to_ftn_type(pointer.type)
                # A pointer to a string takes the length of its target
                type_str = type_str.replace("(len=*)", "(len=:)")
                dim_suffix = inner._ftn_dim_suffix(pointer.type)
                inner.print(f"{type_str}, pointer :: {var_name}{dim_suffix} => null()")

            for index_name in loop_indices:
                inner.print(f"integer :: {index_name}")

            if "ftn_local_decls" in fn_attrs:
                for decl in fn_attrs["ftn_local_decls"]:
                    inner.print(decl.data)

            # Declare anonymous locals for call results that have no CopyOp consumer
            for res, var_name in untracked_call_results:
                inner.variables[res] = var_name
                type_str = inner.mlir_type_to_ftn_type(res.type)
                dim_suffix = inner._ftn_dim_suffix(res.type)
                inner.print(f"{type_str} :: {var_name}{dim_suffix}")

            inner.print("")

            inner.print_block(bdy.block)

    @contextmanager
    def descend(self, block_start: str = None, block_end: str = None):
        """Return a child context with one extra level of indentation.

        The child inherits a copy of the parent's variable map so that names
        defined in an outer scope remain visible inside nested blocks.  An
        optional block_start string (e.g. a subroutine signature) is printed
        before yielding, and block_end (e.g. 'end subroutine') is printed
        after the with-block completes.

        Usage::

            with self.descend("subroutine foo()", "end subroutine foo") as inner:
                inner.print_block(body)
        """
        if block_start is not None:
            self.print(f"{block_start} ")
        yield ftnPrintContext(
            output=self.output,
            variables=self.variables.copy(),
            _cmp_ops=self._cmp_ops,
            _binops=self._binops,
            _counter=self._counter,
            _prefix=self._prefix + self._INDENT,
        )
        if block_end is not None:
            self.print(f"{block_end} ")

    def print(self, text: str, prefix: str = "", end: str = "\n", use_prefix=True):
        """Append text to the current line buffer, flushing on newline.

        Embedded newlines in text cause an immediate buffer flush each time
        they are encountered.  When end="\\n" (the default) the buffer is
        flushed at the end of the call.  Passing use_prefix=False suppresses
        the indentation prefix for inline continuations.
        """
        parts = text.split("\n")
        for i, part in enumerate(parts):
            if i > 0:
                self._emit_line()
            self._line_buf += (self._prefix + prefix if use_prefix else "") + part
        if end == "\n":
            self._emit_line()

    def _emit_line(self):
        """Flush the line buffer, splitting at commas if the line is too long."""
        line = self._line_buf
        self._line_buf = ""
        self._write_with_continuation(line, self._prefix + self._INDENT)

    def _write_with_continuation(self, line: str, cont_prefix: str):
        """Write line, inserting Fortran continuation markers at commas if needed.

        If line exceeds _MAX_LINE_LEN characters, the last comma at or before
        position _MAX_LINE_LEN - 2 is used as the split point: the first part
        is written with a trailing ' &' and the remainder is written on the
        next line starting with cont_prefix.  Recurses until the remainder fits.
        """
        if len(line) <= _MAX_LINE_LEN:
            print(line, file=self.output)
            return
        # Search for the last comma that leaves room for ' &' within the limit
        split_pos = line.rfind(",", 0, _MAX_LINE_LEN - 2)
        if split_pos == -1:
            # A long first argument or condition: split after the next comma, or
            # before the last logical operator that fits
            split_pos = line.find(",", _MAX_LINE_LEN - 2)
        if split_pos == -1:
            operators = [line.rfind(op, 0, _MAX_LINE_LEN - 2) for op in _OPERATORS]
            split_pos = max(operators) - 1 if max(operators) > 0 else -1
        if split_pos == -1:
            # No valid split point — emit as-is rather than produce invalid Fortran
            print(line, file=self.output)
            return
        print(line[: split_pos + 1].ljust(_MAX_LINE_LEN - 1) + "&", file=self.output)
        remainder = cont_prefix + line[split_pos + 1 :].lstrip()
        self._write_with_continuation(remainder, cont_prefix)

    def print_block(self, body: Block):
        """Iterate over every operation in body and dispatch it to print_op."""
        for op in body.ops:
            self.print_op(op)


def get_modules_in_module_op(module: ModuleOp):
    """Yield each named sub-ModuleOp directly contained in the top-level module.

    The top-level module is an anonymous wrapper; the named sub-modules (one
    per cap suite) are what get printed as individual Fortran files.
    """
    for op in module.body.ops:
        if isinstance(op, builtin.ModuleOp):
            yield op


def print_to_ftn(
    prog: ModuleOp, output: IO[str], Ctx: type[ftnPrintContext] = ftnPrintContext
):
    """Print all named sub-modules in prog as Fortran source to output.

    Each sub-module is preceded by a FILE comment that indicates the suggested
    output filename (e.g. '// FILE: hello_world_suite_cap.F90').  Multiple
    modules are separated by a '// -----' divider.
    """
    ctx = Ctx(output)
    ctx.register_binops()
    divider = False
    # Print each cap module as a separate Fortran file section
    for module in get_modules_in_module_op(prog):
        if divider:
            ctx.print("// -----")
        divider = True
        ctx.print("// FILE: " + module.sym_name.data + ".F90")
        ctx.print_op(module)
