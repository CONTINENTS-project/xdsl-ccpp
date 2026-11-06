"""Resolution of scheme arguments to the variables that provide them.

Scheme arguments are matched by standard name, as in the CCPP framework.  A
variable is owned by the host when a host module provides it, directly or as a
member of a derived type.  Otherwise it belongs to the suite when a scheme produces
it, and the suite cap stores it in a module variable.  A variable with no owner is
passed down from the host cap as a dummy argument.
"""

import re
from dataclasses import dataclass, field

from xdsl_ccpp.transforms.util.ccpp_descriptors import CCPPType, find_entry_point

ERROR_CODE = "ccpp_error_code"
ERROR_MESSAGE = "ccpp_error_message"
LOOP_BEGIN = "horizontal_loop_begin"
LOOP_END = "horizontal_loop_end"
LOOP_EXTENT = "horizontal_loop_extent"
# Subcycle loops, which have nothing to do with the horizontal loop
SUBCYCLE_COUNTER = "ccpp_loop_counter"
SUBCYCLE_EXTENT = "ccpp_loop_extent"
SUBCYCLE_NAMES = (SUBCYCLE_COUNTER, SUBCYCLE_EXTENT)
HORIZONTAL = "horizontal_dimension"
VERTICAL_LAYER = "vertical_layer_dimension"
CONSTANT_ONE = "ccpp_constant_one"
VERTICAL_DIMENSIONS = {
    "vertical_layer_dimension": "vertical_layer_index",
    "vertical_interface_dimension": "vertical_interface_index",
}
LOOP_NAMES = (LOOP_BEGIN, LOOP_END, LOOP_EXTENT)
CONTROL_NAMES = {ERROR_CODE, ERROR_MESSAGE, LOOP_BEGIN, LOOP_END, LOOP_EXTENT}

# Scheme entry points in the order in which a host calls them
PHASES = (
    "_register",
    "_init",
    "_timestep_init",
    "_run",
    "_timestep_final",
    "_finalize",
)


def standard_name(arg):
    """Return the lower case standard name of an argument (they ignore case)."""
    name = arg.getAttr("standard_name") if arg.hasAttr("standard_name") else arg.name
    return name.lower()


def dimensions(arg):
    """Return the ``(lower, upper)`` bounds of an argument, in lower case."""
    if not arg.hasAttr("dim_names"):
        return []
    bounds = []
    for dim in arg.getAttr("dim_names"):
        lower, _, upper = dim.lower().rpartition(":")
        bounds.append((lower.strip() or CONSTANT_ONE, upper.strip()))
    return bounds


@dataclass
class Variable:
    """A Fortran variable that can provide a scheme argument."""

    # Fortran expression, e.g. phys_state%q
    expression: str
    arg: object
    # Bounds of each dimension that is not fixed by an index
    dims: list
    # One entry per subscript: a standard name for a fixed index, or None
    subscripts: list = field(default_factory=list)
    # The root variable and its module, for host variables
    root: str | None = None
    module: str | None = None
    # Other host variables that the expression refers to, as (root, module)
    uses: list = field(default_factory=list)

    @property
    def active(self):
        return self.arg.getAttr("active") if self.arg.hasAttr("active") else None


def _host_variable(arg, prefix, root, module):
    """Build a `Variable` from a host metadata entry.

    The name can select from an array, e.g. ``q(:,:,index_of_water_vapor)``.
    """
    match = re.fullmatch(r"(\w+)\((.*)\)", arg.name)
    base = match.group(1) if match else arg.name
    subscripts = []
    if match:
        for subscript in match.group(2).split(","):
            subscript = subscript.strip().lower()
            subscripts.append(None if subscript == ":" else subscript)
    return Variable(prefix + base, arg, dimensions(arg), subscripts, root, module)


def _member_prefix(name):
    """Return the prefix that selects the members of a derived type variable.

    An element of an array is selected by a standard name, such as
    ``Interstitial(ccpp_thread_number)``.  It stays as ``{standard_name}`` in the
    prefix until `host_variables` can look up the host variable that it names.
    """
    match = re.fullmatch(r"(\w+)\((.*)\)", name)
    if not match:
        return f"{name}%"
    subscripts = [
        "{" + sub.strip().lower() + "}"
        if re.fullmatch(r"[A-Za-z_]\w*", sub.strip())
        else sub.strip()
        for sub in match.group(2).split(",")
    ]
    return f"{match.group(1)}({','.join(subscripts)})%"


def _add_ddt_members(variables, meta_data, arg, prefix, root, module):
    """Add the members of a derived type variable, including nested ones."""
    type_name = arg.getAttr("type")
    if type_name not in meta_data or type_name not in meta_data[type_name].arg_tables:
        return
    table = meta_data[type_name].getArgTable(type_name)
    for member in table.getFunctionArguments():
        variables.setdefault(
            standard_name(member), _host_variable(member, prefix, root, module)
        )
        member_prefix = prefix + _member_prefix(member.name)
        _add_ddt_members(variables, meta_data, member, member_prefix, root, module)


def host_kinds(meta_data):
    """Return ``{kind name: module}`` for the kinds that host modules define.

    The metadata of such a module declares an integer for each kind, whose standard
    name is the name of the kind, as ``kind_phys`` in the ``machine`` module of the
    CCPP physics.  Schemes then use the kind of the host, not one that is generated.
    Only kinds that schemes use count, as a module can declare kinds it does not have.
    """
    used = set()
    for props in meta_data.values():
        if props.getAttr("type") != CCPPType.SCHEME:
            continue
        for table in props.arg_tables.values():
            for arg in table.getFunctionArguments():
                if arg.getAttr("type") == "real" and arg.hasAttr("kind"):
                    used.add(arg.getAttr("kind"))
    kinds = {}
    for table_name, props in meta_data.items():
        if props.getAttr("type") != CCPPType.MODULE:
            continue
        if table_name not in props.arg_tables:
            continue
        for arg in props.getArgTable(table_name).getFunctionArguments():
            if (
                arg.getAttr("type") == "integer"
                and not dimensions(arg)
                and arg.name.startswith("kind_")
                and standard_name(arg) == arg.name.lower()
                and arg.name in used
            ):
                kinds.setdefault(arg.name, table_name)
    return kinds


def host_variables(meta_data):
    """Return ``{standard_name: Variable}`` for everything in host modules."""
    variables = {}
    for table_name, props in meta_data.items():
        if props.getAttr("type") != CCPPType.MODULE:
            continue
        if table_name not in props.arg_tables:
            continue
        for arg in props.getArgTable(table_name).getFunctionArguments():
            root = arg.name.partition("(")[0]
            if arg.hasAttr("type") and arg.getAttr("type").lower() in (
                root.lower(),
                standard_name(arg),
            ):
                # The definition of a derived type, listed in the module that has it
                continue
            variables[standard_name(arg)] = _host_variable(arg, "", root, table_name)
            _add_ddt_members(
                variables, meta_data, arg, _member_prefix(arg.name), root, table_name
            )
    for variable in variables.values():
        _resolve_subscripts(variable, variables)
    return variables


def _resolve_subscripts(variable, variables):
    """Replace ``{standard_name}`` in an expression with the host variable."""

    def replace(match):
        source = variables.get(match.group(1))
        if source is None:
            raise ValueError(
                f"{variable.expression} is selected by {match.group(1)}, "
                "which no host variable provides"
            )
        variable.uses.append((source.root, source.module))
        return source.expression

    variable.expression = re.sub(r"\{(\w+)\}", replace, variable.expression)


def control_arguments(meta_data):
    """Return the host cap dummy arguments and where the control values are.

    The dummy arguments are the variables of the ``host`` metadata table, which
    the host passes to every call.  Returns ``(args, {standard_name: expression})``.
    A derived type argument provides the members that it contains.
    """
    args = []
    expressions = {}
    for props in meta_data.values():
        if props.getAttr("type") != CCPPType.HOST:
            continue
        for table in props.arg_tables.values():
            for arg in table.getFunctionArguments():
                args.append(arg)
                expressions[standard_name(arg)] = arg.name
                members = {}
                _add_ddt_members(members, meta_data, arg, f"{arg.name}%", None, None)
                for std_name, member in members.items():
                    expressions[std_name] = member.expression
    return args, expressions


def entry_point_tables(
    suite_description, meta_data, postfix, group_name=None, with_subcycle=False
):
    """Yield ``(scheme_name, overrides, table)`` for one phase of a suite.

    Schemes without this entry point are skipped.  With *with_subcycle*, a fourth
    item is the subcycle that the scheme belongs to, or None.
    """
    for group in suite_description:
        if group_name is not None and group.attributes["name"] != group_name:
            continue
        for scheme in group:
            scheme_name = scheme.attributes["name"]
            assert scheme_name in meta_data, f"No metadata for scheme {scheme_name}"
            props = meta_data[scheme_name]
            table_name = find_entry_point(props, scheme_name, postfix)
            if table_name is not None:
                entry = (
                    scheme_name,
                    scheme.attributes.get("arg_overrides", {}),
                    props.getArgTable(table_name),
                )
                yield (*entry, scheme.subcycle) if with_subcycle else entry


def _allocation_bounds(dims, host):
    """Return the bounds to allocate a suite array with, or None if unknown."""
    bounds = []
    for lower, upper in dims:
        if upper == LOOP_EXTENT:
            upper = HORIZONTAL
        for bound in (lower, upper):
            if not (bound == CONSTANT_ONE or bound.isdigit() or bound in host):
                return None
        bounds.append((lower, upper))
    return bounds


def suite_variables(suite_description, meta_data, host, exclude=()):
    """Return ``{standard_name: Variable}`` for variables the suite must store.

    A variable qualifies when no host module has it, a scheme sets it before any
    scheme reads it (or it has a default value), and its size is known.  The
    variable takes the rank of its largest use, because a scheme inside a vertical
    loop sees one level of it.  Standard names in *exclude* are never suite variables,
    as something else provides them.
    """
    uses: dict = {}
    for postfix in PHASES:
        for _, _, table in entry_point_tables(suite_description, meta_data, postfix):
            for arg in table.getFunctionArguments():
                std_name = standard_name(arg)
                if (
                    std_name not in CONTROL_NAMES
                    and std_name not in host
                    and std_name not in exclude
                ):
                    uses.setdefault(std_name, []).append(arg)

    taken = {variable.root for variable in host.values()}
    variables = {}
    for std_name, args in uses.items():
        first = args[0]
        if first.getAttr("intent") == "in" and not first.hasAttr("default_value"):
            continue
        widest = max(args, key=lambda arg: len(dimensions(arg)))
        bounds = _allocation_bounds(dimensions(widest), host)
        if bounds is None:
            continue
        name = first.name
        while name in taken:
            name = "suite_" + name
        taken.add(name)
        variables[std_name] = Variable(name, widest, bounds)
    return variables


def required_variables(
    suite_description, meta_data, host, control, constituents=(), framework=()
):
    """Return the sorted standard names a suite reads and writes.

    As in the CCPP framework these are the host variables, but a protected one is
    never an input.
    *control* holds the standard names of the host cap arguments, which count as
    host variables.  *framework* holds the names of other variables that the host cap
    provides without a host module, and which count in the same way.  A name in
    *constituents* is both read and written, as the framework updates constituents.
    The dimensions of an argument are read.  Returns ``(inputs, outputs)``.
    """
    inputs = set()
    outputs = set()
    for postfix in PHASES:
        for _, _, table in entry_point_tables(suite_description, meta_data, postfix):
            for arg in table.getFunctionArguments():
                for bounds in dimensions(arg):
                    for name in bounds:
                        source = host.get(name)
                        if name in framework or (
                            source is not None and not _is_protected(source.arg)
                        ):
                            inputs.add(name)
                std_name = standard_name(arg)
                if std_name in (LOOP_BEGIN, LOOP_END, LOOP_EXTENT):
                    continue
                if std_name in constituents:
                    inputs.add(std_name)
                    outputs.add(std_name)
                    continue
                source = host.get(std_name)
                if source is None and std_name not in control:
                    if std_name not in framework:
                        continue
                intent = arg.getAttr("intent")
                # Protection only stops a variable from being an input
                protected = source is not None and _is_protected(source.arg)
                if intent == "inout" or (intent == "in" and not protected):
                    inputs.add(std_name)
                if intent in ("out", "inout"):
                    outputs.add(std_name)
    return sorted(inputs), sorted(outputs)


def _is_protected(arg):
    return arg.hasAttr("protected") and arg.getAttr("protected")
