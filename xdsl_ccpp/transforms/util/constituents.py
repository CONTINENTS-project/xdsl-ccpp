"""Constituents: variables that the CCPP framework manages rather than the host.

As in the CCPP framework, a scheme variable is a constituent when its metadata says
that it is advected, is a constituent, or has a molar mass, and no host module
provides it.  The host cap holds a constituents object with an array of all the
constituents, and passes slices of it to the suite cap, so that constituents reach
the schemes as dummy arguments rather than as suite variables.

A scheme can also create constituents at run time in its register phase, by
returning an allocatable array of ``ccpp_constituent_properties_t``.
"""

from xdsl_ccpp.transforms.util import variables as ccpp_vars

CONSTITUENT_TYPE = "ccpp_constituent_properties_t"
TENDENCY_PREFIX = "tendency_of_"

# Members of the constituents object that schemes can ask for, by standard name.
# Arrays have the dimensions (horizontal, vertical layer, number of constituents).
OBJECT_ARRAYS = {
    "ccpp_constituents": "vars_layer",
    "ccpp_constituent_tendencies": "vars_layer_tend",
}
OBJECT_SCALARS = {
    "number_of_ccpp_constituents": "num_layer_vars",
    "number_of_ccpp_advected_constituents": "num_advected_vars",
}
OBJECT_MEMBERS = {**OBJECT_ARRAYS, **OBJECT_SCALARS}

VERTICAL_LAYER = ccpp_vars.VERTICAL_LAYER
VERTICAL_INTERFACE = "vertical_interface_dimension"


def is_dynamic(arg):
    """Return True if an argument is an array of constituents made at run time."""
    return arg.getAttr("type") == CONSTITUENT_TYPE


def _is_flagged(arg):
    """Return True if the metadata of an argument makes it a constituent."""
    if arg.hasAttr("advected") or arg.hasAttr("constituent"):
        return True
    if arg.hasAttr("molar_mass"):
        try:
            return float(arg.getAttr("molar_mass")) != 0.0
        except ValueError:
            return True
    return False


def _is_tendency(std_name):
    return std_name.startswith(TENDENCY_PREFIX)


def suite_constituents(suite_description, meta_data, host):
    """Return ``{standard_name: arg}`` for the constituents that a suite makes.

    The first scheme argument that mentions a constituent supplies its properties.
    The entries are in the order in which the phases and schemes use them.
    Tendencies are included, as the host needs to provide arrays for them.
    """
    found: dict = {}
    for postfix in ccpp_vars.PHASES:
        for _, _, table in ccpp_vars.entry_point_tables(
            suite_description, meta_data, postfix
        ):
            for arg in table.getFunctionArguments():
                std_name = ccpp_vars.standard_name(arg)
                if (
                    std_name in host
                    or std_name in OBJECT_MEMBERS
                    or std_name in ccpp_vars.CONTROL_NAMES
                    or is_dynamic(arg)
                    or not _is_flagged(arg)
                ):
                    continue
                found.setdefault(std_name, arg)
    return found


def dynamic_constituents(suite_description, meta_data):
    """Return the standard names of the constituents that schemes make at run time."""
    names: dict = {}
    for _, _, table in ccpp_vars.entry_point_tables(
        suite_description, meta_data, "_register"
    ):
        for arg in table.getFunctionArguments():
            if is_dynamic(arg):
                names[ccpp_vars.standard_name(arg)] = None
    return list(names)


def has_constituents(suite_description, meta_data, host):
    """Return True if a suite makes constituents, at run time or otherwise."""
    return bool(
        suite_constituents(suite_description, meta_data, host)
        or dynamic_constituents(suite_description, meta_data)
    )


def properties(std_name, arg):
    """Return the properties that a suite cap creates a constituent with.

    The result is a dictionary of strings, and ``default_value`` is empty when the
    metadata does not give one.
    """
    names = {name for bounds in ccpp_vars.dimensions(arg) for name in bounds}
    vertical = ""
    for candidate in (VERTICAL_LAYER, VERTICAL_INTERFACE):
        if candidate in names:
            vertical = candidate
            break
    long_name = (
        arg.getAttr("long_name")
        if arg.hasAttr("long_name")
        else std_name[:1].upper() + std_name[1:].replace("_", " ")
    )
    return {
        "std_name": std_name,
        "long_name": long_name,
        "units": arg.getAttr("units") if arg.hasAttr("units") else "",
        "vertical_dim": vertical,
        "advected": ".true." if arg.hasAttr("advected") else ".false.",
        "default_value": arg.getAttr("default_value")
        if arg.hasAttr("default_value")
        else "",
    }


class ConstituentMap:
    """Where a host cap finds the data for the constituents of all its suites.

    *suites* maps each suite name to the ``{standard_name: arg}`` of its constituents.
    The host cap keeps the index of each constituent in an array, which is filled in
    when the constituents are registered.
    """

    def __init__(self, host_name, suites):
        self.names = sorted(
            {
                name
                for found in suites.values()
                for name in found
                if not _is_tendency(name)
            }
        )
        self.tendencies = {
            name for found in suites.values() for name in found if _is_tendency(name)
        }
        self.object_name = f"{host_name}_constituents_obj"
        self.stdnames_name = f"{host_name}_model_const_stdnames"
        self.indices_name = f"{host_name}_model_const_indices"
        for name in sorted(self.tendencies):
            if name[len(TENDENCY_PREFIX) :] not in self.names:
                raise ValueError(
                    f"No associated state variable for tendency variable '{name}'"
                )

    def provides(self, std_name):
        """Return True if the constituents object has data for a standard name."""
        return (
            std_name in OBJECT_MEMBERS
            or std_name in self.names
            or std_name in self.tendencies
        )

    def expression(self, std_name, horizontal, vertical):
        """Return the Fortran expression for the data behind a standard name.

        *horizontal* and *vertical* are the ranges to select, such as ``:``.
        """
        obj = self.object_name
        if std_name in OBJECT_SCALARS:
            return f"{obj}%{OBJECT_SCALARS[std_name]}"
        if std_name in OBJECT_ARRAYS:
            last = f"1:{obj}%num_layer_vars"
            return f"{obj}%{OBJECT_ARRAYS[std_name]}({horizontal}, {vertical}, {last})"
        member = "vars_layer"
        base = std_name
        if _is_tendency(std_name):
            member = "vars_layer_tend"
            base = std_name[len(TENDENCY_PREFIX) :]
        index = f"{self.indices_name}({self.names.index(base) + 1})"
        return f"{obj}%{member}({horizontal}, {vertical}, {index})"
