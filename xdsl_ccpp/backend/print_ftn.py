from __future__ import annotations

import warnings
from collections.abc import Iterable
from contextlib import contextmanager
from dataclasses import dataclass, field
from typing import IO, Literal, cast

from xdsl.dialects import arith, csl, memref, scf, builtin, func, llvm
from xdsl_ccpp.dialects.ccpp_utils import StrCmpOp as CCPPStrCmpOp, StringEqOp as CCPPStringEqOp
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

    # Maps arith op names to their Fortran infix operator strings
    _binops: dict[str, str] = field(default_factory=dict[str, str])

    # Maps comparison op names to a predicate-string → Fortran-operator dict
    _cmp_ops: dict[str, dict[str, str | None]] = field(
        default_factory=dict[str, dict[str, str | None]]
    )

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
            case MemRefType(element_type=IntegerType(width=IntAttr(data=8)), shape=shape) if len(shape) == 1 and next(iter(shape)).data == DYNAMIC_INDEX:
                # A 1-D dynamic i8 memref is an assumed-length Fortran character
                # argument — declared as character(len=*), not character(:).
                return "character(len=*)"
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
        match type_attr:
            case MemRefType(element_type=IntegerType(width=IntAttr(data=8)), shape=shape) if len(shape) == 1 and next(iter(shape)).data == DYNAMIC_INDEX:
                # character(len=*) uses len= notation — no dimension suffix needed
                return ""
            case MemRefType(shape=shape) if any(dim.data == DYNAMIC_INDEX for dim in shape):
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
            case memref.LoadOp(memref=arr, indices=idxs, res=res):
                # A load from a memref is represented by the variable name itself
                self.print(self._get_variable_name_for(arr), end="", use_prefix=False)
            case arith.CmpiOp(predicate=v, lhs=l, rhs=r):
                # Emit lhs <op> rhs using the Fortran comparison operator
                str_pred = arith.CMPI_COMPARISON_OPERATIONS[v.value.data]
                self.print_expr(l.owner)
                self.print(f" {self._cmp_ops[op.name][str_pred]} ", end="", use_prefix=False)
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
            case CCPPStrCmpOp():
                # High-level strcmp: emit as a Fortran character equality test
                lhs_name = self._get_variable_name_for(op.lhs)
                rhs_name = self._get_variable_name_for(op.rhs)
                self.print(f"{lhs_name} .eq. {rhs_name}", end="", use_prefix=False)
            case CCPPStringEqOp():
                # Compare an assumed-length string against a compile-time literal
                lhs_name = self._get_variable_name_for(op.lhs)
                literal_val = op.literal.data
                self.print(f"trim({lhs_name}) .eq. '{literal_val}'", end="", use_prefix=False)
            case _:
                print(type(op))
                assert False

    def print_op(self, op: Operation):
        """Dispatch an MLIR operation to the appropriate Fortran printer.

        Operations that produce values but emit no Fortran statement (e.g.
        address-of, load) register names in the variables dict and return
        silently.  Operations that have no Fortran equivalent (e.g. alloca,
        global declarations, yield) are skipped with a pass.
        """
        match op:
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
                self.variables[op.dereferenced_value] = self._get_variable_name_for(op.ptr)
            case llvm.StoreOp():
                # Emit a Fortran assignment from the source value to the destination
                dst_name = self._get_variable_name_for(op.ptr)
                src_name = self._get_variable_name_for(op.value)
                self.print(f"{dst_name} = {src_name}")
            case func.FuncOp(sym_name=name, body=bdy, function_type=ftyp):
                # Skip external declarations; only print subroutine definitions
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
        """Print a builtin.ModuleOp as a Fortran module block.

        The preamble contains:
          - use ccpp_kinds / implicit none / private defaults
          - character variable declarations for every llvm.GlobalOp
          - a public :: line for each subroutine definition marked public
        The CONTAINS section follows, with all subroutine definitions printed
        by delegating to print_block.
        """
        assert module_name is not None

        self.print(f"module {module_name.data}")
        self.print("\nuse ccpp_kinds", prefix="  ")

        # Emit 'use <module>, only: <procs>' for each external FuncOp that
        # carries a module attribute (set by generate-ccpp-cap to record
        # which suite cap module owns the callee).
        use_map: dict[str, list[str]] = {}
        for op in body.ops:
            if (
                isa(op, func.FuncOp)
                and op.is_declaration
                and "module" in op.attributes
            ):
                mod = op.attributes["module"].data
                use_map.setdefault(mod, []).append(op.sym_name.data)
        for mod, procs in sorted(use_map.items()):
            self.print(f"use {mod}, only: {', '.join(sorted(procs))}", prefix="  ")

        self.print("\nimplicit none", prefix="  ")
        self.print("private", prefix="  ")
        self.print("")

        # Emit module-level character variable declarations for each LLVM global
        for op in body.ops:
            if isa(op, llvm.GlobalOp):
                name = op.sym_name.data
                val = op.value.data if isa(op.value, StringAttr) else ""
                is_const = op.constant is not None
                if is_const:
                    # Read-only string constants use the parameter attribute
                    self.print(f"character(len=16), parameter :: {name} = '{val}'", prefix="  ")
                else:
                    # Mutable state variable (ccpp_suite_state) has no parameter
                    self.print(f"character(len=16) :: {name} = '{val}'", prefix="  ")

        # Emit one public :: line per subroutine definition that is marked public
        public_procs = [
            op.sym_name.data
            for op in body.ops
            if isa(op, func.FuncOp)
            and not op.is_declaration
            and op.sym_visibility is not None
            and op.sym_visibility.data == "public"
        ]
        for proc in public_procs:
            self.print(f"public :: {proc}", prefix="  ")

        self.print("\nCONTAINS")

        with self.descend() as inner:
            inner.print_block(body)

        self.print(f"end module {module_name.data}")

    def get_call_result_var_ssa(self, res_ssa):
        """Resolve a call result SSA value to the Fortran variable it writes into.

        After a scheme subroutine call the MLIR IR contains a memref.CopyOp
        that copies each result into its destination storage.  This method
        follows that use edge to find the destination variable name, which is
        then printed as the output argument of the Fortran call.
        """
        for use in res_ssa.uses:
            if isa(use.operation, memref.CopyOp):
                return self._get_variable_name_for(use.operation.destination)

    def _print_call(self, tgt, args, results):
        """Print a func.CallOp as a Fortran subroutine call statement.

        Input arguments are printed by variable name.  Output arguments are
        resolved through the CopyOp use-chain to find the destination variable
        that will receive each result.
        """
        self.print(f"call {tgt.string_value()}(", end="")
        # Print input (in / inout) arguments by their variable names
        for idx, arg in enumerate(args):
            if idx > 0: self.print(", ", end="", use_prefix=False)
            self.print(self._get_variable_name_for(arg), end="", use_prefix=False)

        # Print output argument destinations, resolved via CopyOp uses
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
                        out_name = ret_val.name_hint if ret_val.name_hint is not None else f"out_{len(output_names)}"
                        output_names.append(out_name)
                        output_ret_vals.append(ret_val)
                    else:
                        # Block arg in return position → inout argument
                        inout_block_args.add(ret_val)
                break

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
            for arg, arg_name in zip(bdy.block.args, input_names):
                type_str = inner.mlir_type_to_ftn_type(arg.type)
                dim_suffix = inner._ftn_dim_suffix(arg.type)
                if dim_suffix:
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
        """Print text to the output stream, applying the current indentation.

        Multi-line strings are split and each line is prefixed individually.
        Pass use_prefix=False to suppress indentation (e.g. for continuations
        on the same line).
        """
        for l in text.split("\n"):
            print((self._prefix + prefix if use_prefix else "") + l, file=self.output, end=end)

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
