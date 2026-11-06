import itertools
import re
from dataclasses import dataclass

from xdsl.context import Context
from xdsl.dialects import arith, builtin, func, llvm, memref, scf
from xdsl.dialects.builtin import ArrayAttr, DictionaryAttr, StringAttr, i1, i8, i32
from xdsl.ir import Block, Region
from xdsl.passes import ModulePass
from xdsl.pattern_rewriter import (
    GreedyRewritePatternApplier,
    InsertPoint,
    PatternRewriter,
    PatternRewriteWalker,
    RewritePattern,
    op_type_rewrite_pattern,
)
from xdsl.utils.hints import isa

from xdsl_ccpp.dialects import ccpp, ccpp_utils
from xdsl_ccpp.dialects.ccpp_utils import (
    AllocateOp,
    ArraySectionOp,
    DeallocateOp,
    FortranExprOp,
    HostVarRefOp,
    KeywordCallOp,
    PointerAssociateOp,
    PointerDeclOp,
    PointerNullifyOp,
    SuiteConstituentsOp,
    SuiteVarOp,
)
from xdsl_ccpp.transforms.util import constituents as ccpp_consts
from xdsl_ccpp.transforms.util import variables as ccpp_vars
from xdsl_ccpp.transforms.util.ccpp_descriptors import (
    BuildMetaDataDescriptions,
    BuildSchemeDescription,
)
from xdsl_ccpp.transforms.util.typing import TypeConversions
from xdsl_ccpp.util.visitor import Visitor

# A scheme call with up to this many optional arguments that exist only under a
# condition is generated for every combination of them, with the others omitted
# from the call.  The number of calls doubles with each argument, so a call with
# more uses a local pointer for each argument instead.  The pointer is associated
# with the variable under the condition, and a disassociated pointer passed to an
# optional dummy argument is absent, as in capgen and mkstatic.  This needs the
# variable to have the TARGET attribute (or be a pointer), which the variants don't.
MAX_CONDITIONAL_ARGS = 4


class GatherMetaFunctionSignatures(Visitor):
    """Collects all external func.FuncOp declarations from the ccpp module.

    These declarations represent the scheme subroutine signatures generated
    by the generate-meta-cap pass and are needed when building call sites.
    """

    def __init__(self):
        self.meta_functions = {}

    def traverse_func_op(self, func_op: func.FuncOp):
        # Only record external declarations, not definitions
        if func_op.is_declaration:
            self.meta_functions[func_op.sym_name.data] = func_op


class PhaseBuilder:
    """Builds the body of one suite cap subroutine.

    Holds the values available in the subroutine, and turns each scheme argument
    into an SSA value by standard name.  Arguments with no owner become dummy
    arguments of the subroutine, which are added to its block as they are found.
    """

    def __init__(self, block, errmsg, errflg, in_run_phase, generator):
        self.block = block
        self.errmsg = errmsg
        self.errflg = errflg
        self.in_run_phase = in_run_phase
        self.generator = generator
        self.host = generator.host
        self.suite_vars = generator.suite_vars
        # The host provides the horizontal loop bounds in the run phase, instead of
        # the caller of the subroutine
        self.host_bounds = generator.static_api and in_run_phase
        # (counter, extent) values inside a subcycle that the host has no variables for
        self.subcycle = None
        self.col_start = None
        self.col_end = None
        self.ncol = None
        self.dummies: dict = {}
        self.dummy_intents: dict = {}
        self.allocatable_dummies: list = []
        # Local pointers for conditional arguments, reused as each is nullified
        self.pointers: dict = {}
        self.pointer_decls: list = []

    def pointer_to(self, arg, pointer_type):
        """Return the local pointer for an argument of a type, declaring it once."""
        key = (ccpp_vars.standard_name(arg), pointer_type)
        if key not in self.pointers:
            taken = {value.name_hint for value in self.dummies.values()}
            taken |= {decl.res.name_hint for decl in self.pointer_decls}
            name = f"{arg.name}_ptr"
            while name in taken:
                name += "_"
            decl = PointerDeclOp(pointer_type)
            decl.res.name_hint = name
            self.pointer_decls.append(decl)
            self.pointers[key] = decl.res
        return self.pointers[key]

    def bound(self, bound):
        """Return ``(ops, value)`` for one bound of a dimension."""
        if bound == ccpp_vars.CONSTANT_ONE:
            bound = "1"
        if bound.isdigit():
            const = arith.ConstantOp.from_int_and_width(int(bound), 32)
            return [const], const.result
        ref = self.generator.host_ref(self.host[bound])
        return [ref], ref.res

    def has_bound(self, *bounds):
        """Whether the bounds of a dimension are numbers or host variables."""
        return all(
            bound == ccpp_vars.CONSTANT_ONE
            or bound.isdigit()
            or bound == ccpp_vars.LOOP_EXTENT
            or bound in self.host
            for bound in bounds
        )

    def _dummy(self, std_name, arg):
        """Return the dummy argument for a variable with no owner."""
        intent = arg.getAttr("intent")
        if std_name in self.dummies:
            if self.dummy_intents[std_name] != intent:
                self.dummy_intents[std_name] = "inout"
            return self.dummies[std_name]

        value = self.block.insert_arg(
            TypeConversions.convert_arg(arg), len(self.block.args)
        )
        names = {dummy.name_hint for dummy in self.dummies.values()}
        name = arg.name
        while name in names:
            name += "_"
        value.name_hint = name
        self.dummies[std_name] = value
        self.dummy_intents[std_name] = intent
        if arg.hasAttr("allocatable"):
            self.allocatable_dummies.append(name)
        return value

    def source_of(self, std_name):
        """Return the `Variable` providing a standard name, or None."""
        return self.host.get(std_name) or self.suite_vars.get(std_name)

    def _section(self, source, arg, level_dim, level_index):
        """Return ``(ops, lowers, uppers)`` selecting what a scheme argument needs.

        Returns no bounds when the scheme receives the whole variable.
        """
        arg_dims = ccpp_vars.dimensions(arg)
        arg_uppers = {upper for _, upper in arg_dims}
        horizontal_slice = self.in_run_phase and ccpp_vars.LOOP_EXTENT in arg_uppers
        dims = iter(source.dims)
        # The scheme gets the extent that it declares, where it has all dimensions
        declared = iter(arg_dims) if len(arg_dims) == len(source.dims) else None
        # A static API passes the extent that the scheme declares, even when that is
        # the whole variable, as the CCPP framework does: a dummy argument that takes
        # its shape would see the shape of the host variable otherwise
        explicit = (
            self.generator.static_api
            and declared is not None
            and bool(source.dims)
            and self.has_bound(
                *(bound for dim in arg_dims + source.dims for bound in dim)
            )
        )
        ops: list = []
        lowers: list = []
        uppers: list = []
        selects = False
        for subscript in source.subscripts or [None] * len(source.dims):
            if subscript is not None:
                # An index fixed by the host metadata
                index_ops, index = self.bound(subscript)
                ops += index_ops
                lowers.append(index)
                uppers.append(index)
                selects = True
                continue

            lower, upper = next(dims)
            declared_lower, declared_upper = (
                next(declared) if declared else (lower, upper)
            )
            if upper in (ccpp_vars.HORIZONTAL, ccpp_vars.LOOP_EXTENT) and (
                horizontal_slice
            ):
                lowers.append(self.col_start)
                uppers.append(self.col_end)
                selects = True
            elif upper == level_dim:
                lowers.append(level_index)
                uppers.append(level_index)
                selects = True
            else:
                if not self.has_bound(declared_lower, declared_upper):
                    declared_lower, declared_upper = lower, upper
                lower_ops, lower_value = self.bound(declared_lower)
                upper_ops, upper_value = self.bound(
                    ccpp_vars.HORIZONTAL
                    if declared_upper == ccpp_vars.LOOP_EXTENT
                    else declared_upper
                )
                ops += lower_ops + upper_ops
                lowers.append(lower_value)
                uppers.append(upper_value)
        if selects or explicit:
            return ops, lowers, uppers
        return [], [], []

    def value_of(self, arg, expected_type, level_dim=None, level_index=None):
        """Return ``(ops, value)`` for a scheme argument, of type *expected_type*."""
        std_name = ccpp_vars.standard_name(arg)
        horizontal = self.host.get(ccpp_vars.HORIZONTAL)
        ops: list = []
        source = None
        if std_name == ccpp_vars.ERROR_CODE:
            value = self.errflg
        elif std_name == ccpp_vars.ERROR_MESSAGE:
            value = self.errmsg
        elif self.host_bounds and std_name in ccpp_vars.LOOP_NAMES:
            source = self.source_of(std_name)
            if source is None:
                value = self._dummy(std_name, arg)
        elif (
            std_name in ccpp_vars.SUBCYCLE_NAMES
            and self.subcycle is not None
            and self.source_of(std_name) is None
        ):
            value = self.subcycle[std_name == ccpp_vars.SUBCYCLE_EXTENT]
        elif self.in_run_phase and std_name == ccpp_vars.LOOP_EXTENT:
            value = self.ncol
        elif self.in_run_phase and std_name == ccpp_vars.LOOP_BEGIN:
            value = self.col_start
        elif self.in_run_phase and std_name == ccpp_vars.LOOP_END:
            value = self.col_end
        elif std_name == ccpp_vars.LOOP_BEGIN:
            start = FortranExprOp("1", expected_type)
            ops.append(start)
            value = start.res
        elif std_name in (ccpp_vars.LOOP_END, ccpp_vars.LOOP_EXTENT) and horizontal:
            source = horizontal
        else:
            source = self.source_of(std_name)
            if source is None:
                value = self._dummy(std_name, arg)

        if source is not None:
            ref = self.generator.variable_ref(source)
            ops.append(ref)
            value = ref.res
            if not arg.hasAttr("allocatable"):
                section_ops, lowers, uppers = self._section(
                    source, arg, level_dim, level_index
                )
                if lowers:
                    section = ArraySectionOp(value, lowers, uppers, expected_type)
                    ops += [*section_ops, section]
                    value = section.res

        if value.type != expected_type:
            # The backend looks through this cast to the underlying variable
            cast = builtin.UnrealizedConversionCastOp(
                operands=[[value]], result_types=[[expected_type]]
            )
            ops.append(cast)
            value = cast.results[0]
        return ops, value


class GenerateSuiteSubroutine(RewritePattern):
    """Rewrites each ccpp.SuiteOp into a named ModuleOp containing the CCPP cap
    subroutines: register, initialize, finalize, timestep_initial, timestep_final
    and one for each group.  Each subroutine guards scheme calls behind an errflg
    check and manages the ccpp_suite_state lifecycle string.
    """

    def __init__(
        self,
        suite_descriptions,
        meta_data,
        meta_fn_sigs,
        top_level_module,
        static_api=False,
        generates_kinds=True,
    ):
        self.suite_descriptions = suite_descriptions
        self.meta_data = meta_data
        self.meta_fn_sigs = meta_fn_sigs
        self.top_level_module = top_level_module
        # The host calls the run phase through a static API that has no loop bounds
        self.static_api = static_api
        # Whether the suites need kinds that the host does not define
        self.generates_kinds = generates_kinds
        self.host = ccpp_vars.host_variables(meta_data)
        self.suite_vars: dict = {}
        self.host_imports: dict = {}

    def variable_ref(self, variable):
        """Return an op referencing a host or suite variable."""
        if variable.module is not None:
            return self.host_ref(variable)
        return HostVarRefOp(
            variable.expression, "", TypeConversions.convert_arg(variable.arg)
        )

    def host_ref(self, variable):
        """Return an op referencing a host variable, and record the import."""
        self.host_imports[variable.root] = variable.module
        self.host_imports.update(variable.uses)
        return HostVarRefOp(
            variable.expression,
            variable.module,
            TypeConversions.convert_arg(variable.arg, len(variable.dims)),
        )

    def activeCondition(self, variable):
        """Return an op for the condition under which a host variable exists."""

        def replace(match):
            source = self.host.get(match.group(0).lower())
            if source is None:
                return match.group(0)
            self.host_imports[source.root] = source.module
            self.host_imports.update(source.uses)
            return source.expression

        return FortranExprOp(re.sub(r"[A-Za-z_]\w*", replace, variable.active), i1)

    def levelDimension(self, phase, arg_table):
        """Return the vertical dimension that a scheme needs a loop over, or None.

        A scheme is called once per level when it declares a variable without the
        vertical dimension that the variable has.
        """
        for arg in arg_table.getFunctionArguments():
            source = phase.source_of(ccpp_vars.standard_name(arg))
            if source is None or arg.hasAttr("allocatable"):
                continue
            arg_dimensions = ccpp_vars.dimensions(arg)
            if len(arg_dimensions) >= len(source.dims):
                # The scheme has all of the dimensions, perhaps with other names
                continue
            arg_uppers = {upper for _, upper in arg_dimensions}
            for _, upper in source.dims:
                if upper in ccpp_vars.VERTICAL_DIMENSIONS and upper not in arg_uppers:
                    return upper
        return None

    def associatePointers(self, associations):
        """Build the ops associating pointers under the conditions that apply.

        *associations* holds ``(source, ops, pointer, value)`` for each pointer.
        Pointers that share a condition are associated in one ``if``.
        """
        groups: dict = {}
        for source, ops, pointer, value in associations:
            group = groups.setdefault(source.active, (source, []))[1]
            group += [*ops, PointerAssociateOp(pointer, value)]
        ops = []
        for source, group in groups.values():
            condition = self.activeCondition(source)
            ops += [condition, scf.IfOp(condition.res, [], [*group, scf.YieldOp()])]
        return ops

    def generateCall(
        self, subroutine_name, arg_table, phase, overrides, level, omitted, pointed=()
    ):
        """Build the ops for one scheme call and return them.

        *level* is ``(dimension, index)`` inside a vertical loop.  Arguments named in
        *omitted* are left out, which optional arguments allow.  *pointed* holds
        ``(argument, source)`` for arguments that are passed through a local pointer,
        which is associated when the condition on the variable holds.
        """
        pointed = {arg.name: source for arg, source in pointed}
        callee = self.meta_fn_sigs[subroutine_name]
        callee_in_types = list(callee.function_type.inputs)
        callee_out_types = list(callee.function_type.outputs)
        level_dim, level_index = level

        ops: list = []
        in_ssa = []
        in_names = []
        out_types = []
        out_names = []
        out_values = []
        associations = []
        pointers = []
        in_idx = 0
        out_idx = 0

        for arg in arg_table.getFunctionArguments():
            intent = arg.getAttr("intent")
            is_input = intent in ("in", "inout")
            is_output = intent in ("out", "inout")
            expected = (
                callee_in_types[in_idx] if is_input else callee_out_types[out_idx]
            )
            if arg.name not in overrides and arg.name not in omitted:
                value_ops, value = phase.value_of(arg, expected, level_dim, level_index)
                if arg.name in pointed:
                    if arg.hasAttr("allocatable"):
                        raise NotImplementedError(
                            f"{subroutine_name}: {arg.name} is allocatable, which "
                            "a pointer cannot be passed to"
                        )
                    pointer = phase.pointer_to(arg, expected)
                    associations.append((pointed[arg.name], value_ops, pointer, value))
                    pointers.append(pointer)
                    value_ops, value = [], pointer
                ops += value_ops
                if is_input:
                    in_ssa.append(value)
                    in_names.append(arg.name)
                if is_output:
                    out_types.append(expected)
                    out_names.append(arg.name)
                    out_values.append(value)
            in_idx += is_input
            out_idx += is_output

        if overrides or omitted:
            call_op = KeywordCallOp(
                subroutine_name,
                ArrayAttr([StringAttr(n) for n in in_names]),
                ArrayAttr([StringAttr(n) for n in out_names]),
                DictionaryAttr({k: StringAttr(v) for k, v in overrides.items()}),
                in_ssa,
                out_types,
            )
        else:
            call_op = func.CallOp(subroutine_name, in_ssa, out_types)
            # Scheme dummy arguments can be in any order, so calls are keyword based
            call_op.attributes["ftn_arg_names"] = ArrayAttr(
                [StringAttr(n) for n in in_names]
            )
            call_op.attributes["ftn_result_names"] = ArrayAttr(
                [StringAttr(n) for n in out_names]
            )

        copies = [
            memref.CopyOp(result, value)
            for result, value in zip(call_op.results, out_values)
        ]
        return [
            *self.associatePointers(associations),
            *ops,
            call_op,
            *copies,
            *(PointerNullifyOp(pointer) for pointer in pointers),
        ]

    def generateCallVariants(
        self,
        subroutine_name,
        arg_table,
        phase,
        overrides,
        level,
        omitted,
        conditional,
        pointed=(),
    ):
        """Build a scheme call for each combination of conditional arguments."""
        if not conditional:
            return self.generateCall(
                subroutine_name, arg_table, phase, overrides, level, omitted, pointed
            )
        arg, source = conditional[0]
        condition = self.activeCondition(source)
        args = (subroutine_name, arg_table, phase, overrides, level)
        present = self.generateCallVariants(*args, omitted, conditional[1:], pointed)
        absent = self.generateCallVariants(
            *args, omitted | {arg.name}, conditional[1:], pointed
        )
        return [
            condition,
            scf.IfOp(
                condition.res, [], [*present, scf.YieldOp()], [*absent, scf.YieldOp()]
            ),
        ]

    def generateSchemeSubroutineCallOps(self, arg_table, phase, overrides):
        """Build the IR for a single scheme call guarded by errflg.

        The call only executes when errflg is zero, meaning no prior error has
        occurred, and is repeated for each level if the scheme works on one level.
        """
        # Only apply overrides whose names actually appear in this arg table;
        # the same override dict may be shared across entry points (_run, _init,
        # _finalize) and not every entry point has the same arguments.
        arg_names = {arg.name for arg in arg_table.getFunctionArguments()}
        overrides = {k: v for k, v in overrides.items() if k in arg_names}

        omitted = set()
        conditional = []
        for arg in arg_table.getFunctionArguments():
            if not arg.hasAttr("optional"):
                continue
            std_name = ccpp_vars.standard_name(arg)
            source = phase.source_of(std_name)
            if source is None and std_name not in ccpp_vars.CONTROL_NAMES:
                omitted.add(arg.name)
            elif source is not None and source.active is not None:
                conditional.append((arg, source))

        pointed = []
        if len(conditional) > MAX_CONDITIONAL_ARGS:
            pointed, conditional = conditional, []

        def guarded_call(level):
            call_ops = self.generateCallVariants(
                arg_table.getAttr("name"),
                arg_table,
                phase,
                overrides,
                level,
                omitted,
                conditional,
                pointed,
            )
            zero = arith.ConstantOp.from_int_and_width(0, 32)
            load_op = memref.LoadOp.get(phase.errflg, [])
            cmp = arith.CmpiOp(load_op, zero, 0)
            return [zero, cmp, load_op, scf.IfOp(cmp, [], [*call_ops, scf.YieldOp()])]

        level_dim = self.levelDimension(phase, arg_table)
        if level_dim is None:
            return guarded_call((None, None))

        lower = arith.ConstantOp.from_int_and_width(1, 32)
        step = arith.ConstantOp.from_int_and_width(1, 32)
        upper_ops, upper = phase.bound(level_dim)
        loop_body = Block(arg_types=[i32])
        level_index = loop_body.args[0]
        level_index.name_hint = ccpp_vars.VERTICAL_DIMENSIONS[level_dim]
        # The bound of the loop is an integer rather than a reference to one
        cast = builtin.UnrealizedConversionCastOp(
            operands=[[upper]], result_types=[[i32]]
        )
        loop_body.add_ops([*guarded_call((level_dim, level_index)), scf.YieldOp()])
        loop = scf.ForOp(lower, cast.results[0], step, [], Region(loop_body))
        return [lower, step, *upper_ops, cast, loop]

    def generateSubcycle(self, loop, calls, phase):
        """Build the ops for the schemes of one subcycle, run *loop* times.

        *calls* holds ``(scheme name, overrides, table)``.  The counter and the extent
        are variables of the host when it has any, as in the CCPP framework, which sets
        them for every subcycle.  Otherwise schemes are given the values directly.
        """
        integer_type = TypeConversions.convert("integer")
        host_counter = self.host.get(ccpp_vars.SUBCYCLE_COUNTER)
        host_extent = self.host.get(ccpp_vars.SUBCYCLE_EXTENT)

        def build(counter):
            """Return the ops for one pass, given the value of the counter."""
            ops = []
            extent = FortranExprOp(str(loop), integer_type)
            ops.append(extent)
            phase.subcycle = (counter, extent.res)
            for _, overrides, table in calls:
                ops += self.generateSchemeSubroutineCallOps(table, phase, overrides)
            phase.subcycle = None
            return ops

        def assign(variable, value_ops, value):
            ref = self.variable_ref(variable)
            return [ref, *value_ops, memref.StoreOp.get(value, ref.res, [])]

        ops = []
        if host_extent is not None:
            const = arith.ConstantOp.from_int_and_width(loop, 32)
            ops += assign(host_extent, [const], const.result)

        if loop == 1:
            const = arith.ConstantOp.from_int_and_width(1, 32)
            if host_counter is not None:
                ops += assign(host_counter, [const], const.result)
            return [
                *ops,
                *([const] if host_counter is None else []),
                *build(const.result),
            ]

        lower = arith.ConstantOp.from_int_and_width(1, 32)
        upper = arith.ConstantOp.from_int_and_width(loop, 32)
        step = arith.ConstantOp.from_int_and_width(1, 32)
        body = Block(arg_types=[i32])
        counter = body.args[0]
        counter.name_hint = ccpp_vars.SUBCYCLE_COUNTER
        body_ops = []
        if host_counter is not None:
            body_ops += assign(host_counter, [], counter)
        body_ops += build(counter)
        body.add_ops([*body_ops, scf.YieldOp()])
        return [
            *ops,
            lower,
            upper,
            step,
            scf.ForOp(lower, upper, step, [], Region(body)),
        ]

    def generateStringConstantGlobal(self, string: str) -> llvm.GlobalOp:
        """Create an internal LLVM global holding a 16-byte string constant."""
        return llvm.GlobalOp(
            llvm.LLVMArrayType.from_size_and_type(16, i8),
            "const_" + string,
            "internal",
            constant=True,
            value=StringAttr(string),
        )

    def generateStateCheckOps(
        self, check_string: str, data_ops, fn_name: str | None = None
    ):
        """Emit ops that compare ccpp_suite_state against check_string.

        If the state does not match the expected value, errflg is set to 1
        and, when fn_name is provided, an error message is written into errmsg.
        The comparison uses ccpp_utils.StrCmpOp (lowered later by the
        lower-ccpp-utils pass) and an XOrI to negate the equality result.
        """
        arr_type = llvm.LLVMArrayType.from_size_and_type(16, i8)

        # Load the expected state constant and the current runtime state
        addr_const = llvm.AddressOfOp("const_" + check_string, llvm.LLVMPointerType())
        loaded_const = llvm.LoadOp(addr_const, arr_type)
        addr_state = llvm.AddressOfOp("ccpp_suite_state", llvm.LLVMPointerType())
        loaded_state = llvm.LoadOp(addr_state, arr_type)

        strcmp_op = ccpp_utils.StrCmpOp(loaded_const, loaded_state, len(check_string))

        # strcmp returns 1 if equal; negate to get mismatch flag for scf.if
        one_i1 = arith.ConstantOp.from_int_and_width(1, 1)
        mismatch = arith.XOrIOp(strcmp_op.res, one_i1.result)

        # Set errflg = 1 if the state does not match; optionally write errmsg
        one = arith.ConstantOp.from_int_and_width(1, 32)
        store = memref.StoreOp.get(one, data_ops["errflg"], [])
        if fn_name is not None:
            trim_state = ccpp_utils.TrimOp(loaded_state)
            write_err = ccpp_utils.WriteErrMsgOp(
                data_ops["errmsg"],
                trim_state.res,
                "Invalid initial CCPP state, '",
                f"' in {fn_name}",
            )
            true_ops = [trim_state, write_err, one, store, scf.YieldOp()]
        else:
            true_ops = [one, store, scf.YieldOp()]
        if_op = scf.IfOp(mismatch.result, [], true_ops)

        return [
            addr_const,
            loaded_const,
            addr_state,
            loaded_state,
            strcmp_op,
            one_i1,
            mismatch,
            if_op,
        ]

    def generateStateAssignment(self, state_string: str):
        """Emit ops that write state_string into the ccpp_suite_state global."""
        arr_type = llvm.LLVMArrayType.from_size_and_type(16, i8)
        # Load from the string constant global and store into ccpp_suite_state
        addr_src = llvm.AddressOfOp("const_" + state_string, llvm.LLVMPointerType())
        loaded = llvm.LoadOp(addr_src, arr_type)
        addr_dst = llvm.AddressOfOp("ccpp_suite_state", llvm.LLVMPointerType())
        store = llvm.StoreOp(loaded, addr_dst)
        return [addr_src, loaded, addr_dst, store]

    def generateAllocations(self, phase):
        """Emit ops allocating every array the suite stores."""
        ops = []
        for variable in self.suite_vars.values():
            if not variable.dims:
                continue
            lowers = []
            uppers = []
            for lower, upper in variable.dims:
                lower_ops, lower_value = phase.bound(lower)
                upper_ops, upper_value = phase.bound(upper)
                ops += lower_ops + upper_ops
                lowers.append(lower_value)
                uppers.append(upper_value)
            ref = self.variable_ref(variable)
            initial_value = (
                variable.arg.getAttr("default_value")
                if variable.arg.hasAttr("default_value")
                else None
            )
            ops += [ref, AllocateOp(ref.res, lowers, uppers, initial_value)]
        return ops

    def generateDeallocations(self):
        """Emit ops deallocating every array the suite stores."""
        ops = []
        for variable in self.suite_vars.values():
            if variable.dims:
                ref = self.variable_ref(variable)
                ops += [ref, DeallocateOp(ref.res)]
        return ops

    def generateSubroutineCall(
        self,
        suite_description,
        tgt_subroutine_postfix,
        generated_subroutine_posfix,
        state_string: str | None = None,
        check_string: str | None = None,
        group_name: str | None = None,
    ):
        """Build a single cap subroutine as a func.FuncOp.

        tgt_subroutine_postfix  -- the scheme entry point called (e.g. "_init").
        generated_subroutine_posfix -- suffix used for the generated function
                                   name (e.g. "_initialize").
        state_string            -- if set, write this value into ccpp_suite_state
                                   at the end of the subroutine.
        check_string            -- if set, verify ccpp_suite_state equals this
                                   value at the start of the subroutine.
        group_name              -- if set, only call the schemes of this group.
        """
        in_run_phase = tgt_subroutine_postfix == "_run"
        entries = list(
            ccpp_vars.entry_point_tables(
                suite_description,
                self.meta_data,
                tgt_subroutine_postfix,
                group_name,
                with_subcycle=True,
            )
        )

        errmsg_alloc = memref.AllocaOp.get(
            TypeConversions.getBaseType("character"), shape=[512]
        )
        errmsg_alloc.memref.name_hint = "errmsg"
        errflg_alloc = memref.AllocaOp.get(
            TypeConversions.getBaseType("integer"), shape=[]
        )
        errflg_alloc.memref.name_hint = "errflg"
        output_allocs = [errmsg_alloc, errflg_alloc]

        integer_type = TypeConversions.convert("integer")
        phase_block_args = []
        if in_run_phase and not self.static_api:
            phase_block_args = [integer_type, integer_type]
        new_block = Block(arg_types=phase_block_args)
        phase = PhaseBuilder(
            new_block, errmsg_alloc.memref, errflg_alloc.memref, in_run_phase, self
        )

        ncol_ops = []
        if phase.host_bounds:
            for bound in (ccpp_vars.LOOP_BEGIN, ccpp_vars.LOOP_END):
                if bound not in self.host:
                    raise ValueError(
                        f"The static API needs the host to provide {bound}, which "
                        "no host metadata does"
                    )
            begin_ops, phase.col_start = phase.value_of(
                self.host[ccpp_vars.LOOP_BEGIN].arg, integer_type
            )
            end_ops, phase.col_end = phase.value_of(
                self.host[ccpp_vars.LOOP_END].arg, integer_type
            )
            ncol_ops = [*begin_ops, *end_ops]
        elif in_run_phase:
            phase.col_start, phase.col_end = new_block.args
            phase.col_start.name_hint = "col_start"
            phase.col_end.name_hint = "col_end"
            ncol_alloc = memref.AllocaOp.get(
                TypeConversions.getBaseType("integer"), shape=[]
            )
            ncol_alloc.memref.name_hint = "ccpp_ncol"
            load_col_start = memref.LoadOp.get(phase.col_start, [])
            load_col_end = memref.LoadOp.get(phase.col_end, [])
            sub_op = arith.SubiOp(load_col_end, load_col_start)
            one_const = arith.ConstantOp.from_int_and_width(1, 32)
            add_op = arith.AddiOp(sub_op, one_const)
            store_ncol = memref.StoreOp.get(add_op, ncol_alloc, [])
            phase.ncol = ncol_alloc.memref
            ncol_ops = [
                ncol_alloc,
                load_col_start,
                load_col_end,
                sub_op,
                one_const,
                add_op,
                store_ncol,
            ]

        err_const = arith.ConstantOp.from_int_and_width(0, 32)
        initialisation_ops = [
            err_const,
            memref.StoreOp.get(err_const, errflg_alloc, []),
        ]

        # A scheme listed more than once runs each time it appears, but the other
        # phases only ever call it once.
        call_ops = []
        fn_sigs = {}
        called = set()
        for subcycle, subcycle_entries in itertools.groupby(
            entries, key=lambda entry: entry[3]
        ):
            subcycle_calls = []
            for scheme_name, overrides, table, _ in subcycle_entries:
                if not in_run_phase and scheme_name in called:
                    continue
                called.add(scheme_name)
                subcycle_calls.append((scheme_name, overrides, table))
                full_name = table.getAttr("name")
                fn_sigs[full_name] = (self.meta_fn_sigs[full_name], scheme_name)
            if not subcycle_calls:
                continue
            if subcycle is None:
                for _, overrides, table in subcycle_calls:
                    call_ops += self.generateSchemeSubroutineCallOps(
                        table, phase, overrides
                    )
            else:
                call_ops += self.generateSubcycle(
                    subcycle.loop if in_run_phase else 1, subcycle_calls, phase
                )

        errmsg_fn_name = (
            suite_description.attributes["name"] + generated_subroutine_posfix
        )
        data_ops = {"errflg": errflg_alloc, "errmsg": errmsg_alloc}
        check_ops = (
            self.generateStateCheckOps(check_string, data_ops, errmsg_fn_name)
            if check_string is not None
            else []
        )
        state_ops = (
            self.generateStateAssignment(state_string)
            if state_string is not None
            else []
        )
        allocate_ops = (
            self.generateAllocations(phase) if tgt_subroutine_postfix == "_init" else []
        )
        deallocate_ops = (
            self.generateDeallocations()
            if tgt_subroutine_postfix == "_finalize"
            else []
        )

        new_block.add_ops(
            [
                *output_allocs,
                *phase.pointer_decls,
                *initialisation_ops,
                *ncol_ops,
                *check_ops,
                *allocate_ops,
                *call_ops,
                *deallocate_ops,
                *state_ops,
                func.ReturnOp(*output_allocs),
            ]
        )
        body = Region()
        body.add_block(new_block)

        new_fn_type = builtin.FunctionType.from_lists(
            [arg.type for arg in new_block.args],
            [alloc.results[0].type for alloc in output_allocs],
        )
        new_func = func.FuncOp(
            suite_description.attributes["name"]
            + "_suite"
            + generated_subroutine_posfix,
            new_fn_type,
            body,
            visibility="public",
        )
        intents = ["in"] * len(phase_block_args)
        new_func.attributes["ftn_arg_intents"] = ArrayAttr(
            [StringAttr(i) for i in [*intents, *phase.dummy_intents.values()]]
        )
        new_func.attributes["ftn_arg_standard_names"] = ArrayAttr(
            [
                StringAttr(name)
                for name in [
                    *(
                        [ccpp_vars.LOOP_BEGIN, ccpp_vars.LOOP_END]
                        if phase_block_args
                        else []
                    ),
                    *phase.dummies,
                ]
            ]
        )
        new_func.attributes["ftn_allocatable_args"] = ArrayAttr(
            [StringAttr(name) for name in phase.allocatable_dummies]
        )

        return new_func, list(fn_sigs.values())

    def clone_func_defs(self, func_defs):
        """Create private external declarations for (FuncOp, scheme name) pairs.

        These stubs are placed in the generated module so that the IR remains
        self-contained and verifiable before linking against the real scheme
        object files.  Each records the Fortran module of the scheme, which CCPP
        requires to have the same name as the scheme, so that the backend can
        import the procedure and its explicit interface.
        """
        decls = []
        for fd, scheme_name in func_defs:
            decl = func.FuncOp.external(
                fd.sym_name.data, fd.function_type.inputs, fd.function_type.outputs
            )
            decl.attributes["module"] = StringAttr(scheme_name)
            decls.append(decl)
        return decls

    @op_type_rewrite_pattern
    def match_and_rewrite(self, op: ccpp.SuiteOp, rewriter: PatternRewriter):
        """Generate the complete cap module for one ccpp.SuiteOp.

        For each of the five lifecycle subroutines (initialize, finalize,
        physics, timestep_initial, timestep_final) a func.FuncOp is built via
        generateSubroutineCall.  String constant globals and the mutable
        ccpp_suite_state global are created once and shared across all five.
        The resulting ops are wrapped in a named builtin.ModuleOp and inserted
        at the top level.
        """
        suite_description = self.suite_descriptions[op.suite_name.data]

        # Each tuple describes one cap subroutine:
        # (scheme postfix to call, generated name postfix, state to write, state to check)
        # The run phase has one subroutine per group, which the host selects
        # through suite_part.
        subroutine_specs = [
            ("_register", "_register", None, "uninitialized", None),
            ("_init", "_initialize", "initialized", "uninitialized", None),
            ("_finalize", "_finalize", "uninitialized", "initialized", None),
            *(
                (
                    "_run",
                    "_" + group.attributes["name"],
                    None,
                    "in_time_step",
                    group.attributes["name"],
                )
                for group in suite_description
            ),
            (
                "_timestep_init",
                "_timestep_initial",
                "in_time_step",
                "initialized",
                None,
            ),
            ("_timestep_final", "_timestep_final", "initialized", "in_time_step", None),
        ]

        # The host cap provides constituents, so they are not suite variables
        constituents = ccpp_consts.suite_constituents(
            suite_description, self.meta_data, self.host
        )
        dynamic = ccpp_consts.dynamic_constituents(suite_description, self.meta_data)
        self.suite_vars = ccpp_vars.suite_variables(
            suite_description,
            self.meta_data,
            self.host,
            exclude={*constituents, *dynamic, *ccpp_consts.OBJECT_MEMBERS},
        )
        self.host_imports = {}

        generated_fns = []
        fn_sigs_by_name = {}
        check_strings_used = set()
        state_strings_used = set()

        # Generate one FuncOp per subroutine spec and accumulate unique string values
        for (
            tgt_postfix,
            gen_postfix,
            state_string,
            check_string,
            group_name,
        ) in subroutine_specs:
            fn, sigs = self.generateSubroutineCall(
                suite_description,
                tgt_postfix,
                gen_postfix,
                state_string=state_string,
                check_string=check_string,
                group_name=group_name,
            )
            generated_fns.append(fn)
            # Deduplicate scheme function signatures by name
            for sig in sigs:
                fn_sigs_by_name[sig[0].sym_name.data] = sig
            if check_string is not None:
                check_strings_used.add(check_string)
            if state_string is not None:
                state_strings_used.add(state_string)

        fn_sigs = self.clone_func_defs(list(fn_sigs_by_name.values()))

        # Mutable global holding the current lifecycle state of the suite
        ccpp_suite_state_global = llvm.GlobalOp(
            llvm.LLVMArrayType.from_size_and_type(16, i8),
            "ccpp_suite_state",
            "internal",
            value=StringAttr("uninitialized"),
        )

        # One read-only global per unique state string (shared by check and assign ops)
        all_strings_used = check_strings_used | state_strings_used
        string_const_globals = [
            self.generateStringConstantGlobal(s) for s in sorted(all_strings_used)
        ]

        suite_var_ops = [
            SuiteVarOp(
                variable.expression,
                TypeConversions.convert_arg(variable.arg),
                variable.arg.getAttr("default_value")
                if variable.arg.hasAttr("default_value")
                else None,
            )
            for variable in self.suite_vars.values()
        ]

        constituent_ops = []
        if constituents or dynamic:
            constituent_ops.append(
                SuiteConstituentsOp(
                    op.suite_name.data,
                    ArrayAttr(
                        [
                            DictionaryAttr(
                                {
                                    key: StringAttr(value)
                                    for key, value in ccpp_consts.properties(
                                        std_name, arg
                                    ).items()
                                }
                            )
                            for std_name, arg in constituents.items()
                            if not std_name.startswith(ccpp_consts.TENDENCY_PREFIX)
                        ]
                    ),
                )
            )

        # Imports of the host variables that the schemes are called with
        host_globals = []
        for root, module in {
            **ccpp_vars.host_kinds(self.meta_data),
            **self.host_imports,
        }.items():
            glob = llvm.GlobalOp(
                llvm.LLVMArrayType.from_size_and_type(1, i8), root, "external"
            )
            glob.attributes["module"] = StringAttr(module)
            host_globals.append(glob)

        scheme_mod = builtin.ModuleOp(
            [
                ccpp_suite_state_global,
                *string_const_globals,
                *host_globals,
                *suite_var_ops,
                *constituent_ops,
                *generated_fns,
                *fn_sigs,
            ],
            sym_name=builtin.StringAttr(op.suite_name.data + "_cap"),
        )
        if not self.generates_kinds:
            scheme_mod.attributes["ftn_no_ccpp_kinds"] = builtin.UnitAttr()
        type_uses = TypeConversions.derived_type_uses(scheme_mod, self.meta_data)
        if type_uses:
            scheme_mod.attributes["ftn_type_uses"] = DictionaryAttr(
                {k: StringAttr(v) for k, v in type_uses.items()}
            )

        rewriter.insert_op(
            scheme_mod, InsertPoint.at_start(self.top_level_module.body.block)
        )


@dataclass(frozen=True)
class SuiteCAP(ModulePass):
    """MLIR pass that generates CCPP cap subroutines from ccpp.SuiteOp nodes.

    Traverses the top-level module looking for the named 'ccpp' sub-module,
    collects metadata and scheme descriptions from it, then rewrites each
    ccpp.SuiteOp into a self-contained ModuleOp containing the five lifecycle
    cap subroutines.
    """

    name = "generate-suite-cap"

    # Call the run phase with the horizontal loop bounds of the host model, rather than
    # arguments, as the host does when it calls the cap through a static API.
    static_api: bool = False

    def find_ccpp_module(self, ops):
        """Return the named 'ccpp' ModuleOp from the given op list, or None."""
        for op in ops:
            if (
                isa(op, builtin.ModuleOp)
                and op.sym_name is not None
                and op.sym_name.data == "ccpp"
            ):
                return op
        return None

    def apply(self, ctx: Context, op: builtin.ModuleOp) -> None:
        ccpp_mod = self.find_ccpp_module(op.body.block.ops)
        assert ccpp_mod is not None

        # Build Python descriptor objects from the CCPP metadata IR
        bmdd = BuildMetaDataDescriptions()
        bmdd.traverse(ccpp_mod)
        meta_data_descriptions = bmdd.meta_data

        # Collect the function signatures already declared in the ccpp module
        meta_fn_sig = GatherMetaFunctionSignatures()
        meta_fn_sig.traverse(ccpp_mod)
        meta_fn_sigs = meta_fn_sig.meta_functions

        # Build a map from suite name to its SuiteOp descriptor
        bsd = BuildSchemeDescription()
        bsd.traverse(ccpp_mod)
        scheme_descriptions = bsd.schemes

        PatternRewriteWalker(
            GreedyRewritePatternApplier(
                [
                    GenerateSuiteSubroutine(
                        scheme_descriptions,
                        meta_data_descriptions,
                        meta_fn_sigs,
                        op,
                        self.static_api,
                        any(isa(child, ccpp.KindsOp) for child in ccpp_mod.body.ops)
                        or not ccpp_vars.host_kinds(meta_data_descriptions),
                    ),
                ]
            ),
            apply_recursively=False,
        ).rewrite_module(op)
