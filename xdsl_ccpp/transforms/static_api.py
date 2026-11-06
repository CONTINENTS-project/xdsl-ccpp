"""The static API that a host model such as the CCPP Single Column Model calls.

A host that links the CCPP caps statically calls five procedures, which dispatch on the
name of the suite and of the group.  Each takes the ``ccpp_t`` object of the host, that
also carries the error flag and message, and returns the error flag::

    call ccpp_physics_run(cdata, suite_name=name, group_name="radiation", ierr=ierr)

This pass writes that module, with the names, arguments and error handling of the one
that the CCPP framework prebuild generates, for the suite cap subroutines of
``generate-suite-cap`` when it ran with ``static_api``.  Those subroutines take no
arguments in the run phase, as the host variables hold the loop bounds, so the API only
dispatches.
"""

from dataclasses import dataclass

from xdsl.context import Context
from xdsl.dialects import builtin
from xdsl.dialects.builtin import StringAttr
from xdsl.passes import ModulePass
from xdsl.utils.hints import isa

from xdsl_ccpp.transforms.util.ccpp_descriptors import (
    BuildMetaDataDescriptions,
    BuildSchemeDescription,
)
from xdsl_ccpp.transforms.util.variables import ERROR_CODE, ERROR_MESSAGE, standard_name

CCPP_TYPE = "ccpp_t"

# The API procedure for each phase, and the suite cap subroutine that it calls
PHASES = (
    ("init", "initialize"),
    ("timestep_init", "timestep_initial"),
    ("run", None),
    ("timestep_finalize", "timestep_final"),
    ("finalize", "finalize"),
)

TO_LOWER = """\
   ! Necessary to convert incoming suite and group names to lowercase
   function to_lower(str) result(lower)
      implicit none
      character(len=*), intent(in) :: str
      character(len=len(str)) :: lower
      integer, parameter :: upper_to_lower = ichar('a') - ichar('A')
      integer :: i, ichar_val

      do i = 1, len(str)
         ichar_val = ichar(str(i:i))
         if (ichar_val >= ichar('A') .and. ichar_val <= ichar('Z')) then
            lower(i:i) = char(ichar_val + upper_to_lower)
         else
            lower(i:i) = str(i:i)
         end if
      end do
   end function to_lower
"""


def _control_members(meta_data):
    """Return ``(module, error message member, error flag member)`` of ``ccpp_t``."""
    if CCPP_TYPE not in meta_data or CCPP_TYPE not in meta_data[CCPP_TYPE].arg_tables:
        raise ValueError(
            f"The static API needs the metadata of the host type {CCPP_TYPE}, "
            "which carries the error flag and message"
        )
    props = meta_data[CCPP_TYPE]
    members = {
        standard_name(arg): arg.name
        for arg in props.getArgTable(CCPP_TYPE).getFunctionArguments()
    }
    for std_name in (ERROR_CODE, ERROR_MESSAGE):
        if std_name not in members:
            raise ValueError(f"{CCPP_TYPE} has no member with standard name {std_name}")
    module = props.getAttr("module") if props.hasAttr("module") else "ccpp_types"
    return module, members[ERROR_MESSAGE], members[ERROR_CODE]


def _subroutine(suite, suffix):
    return f"{suite.attributes['name']}_suite_{suffix}"


def _procedure(phase, suites, errmsg, errflg):
    """Return the Fortran of one API procedure."""
    lines = [
        f"   subroutine ccpp_physics_{phase}(cdata, suite_name, group_name, ierr)",
        "",
        "      implicit none",
        "",
        "      type(ccpp_t),               intent(inout) :: cdata",
        "      character(len=*),           intent(in)    :: suite_name",
        "      character(len=*), optional, intent(in)    :: group_name",
        "      integer,                    intent(out)   :: ierr",
        "",
        "      ierr = 0",
        "",
    ]
    keyword = "if"
    for suite in suites:
        name = suite.attributes["name"]
        lines.append(
            f'      {keyword} (to_lower(trim(suite_name))=="{name.lower()}") then'
        )
        lines += _suite_branch(phase, suite, errmsg, errflg)
        keyword = "else if"
    if keyword == "if":
        lines.append("      ierr = 1")
    else:
        lines += [
            "      else",
            f"         write(cdata%{errmsg},'(*(a))') 'Invalid suite ' // "
            "to_lower(trim(suite_name))",
            "         ierr = 1",
            "      end if",
        ]
    lines += [
        "",
        f"      cdata%{errflg} = ierr",
        "",
        f"   end subroutine ccpp_physics_{phase}",
        "",
    ]
    return lines


def _call(suite, suffix, errmsg, errflg):
    return (
        f"call {_subroutine(suite, suffix)}"
        f"(errmsg=cdata%{errmsg}, errflg=cdata%{errflg})"
    )


def _suite_branch(phase, suite, errmsg, errflg):
    """Return the lines to run one phase of a suite, inside the test of its name."""
    suffix = dict(PHASES)[phase]
    groups = [group.attributes["name"] for group in suite]
    lines = []
    if phase == "run":
        lines += [
            "         if (present(group_name)) then",
        ]
        keyword = "if"
        for group in groups:
            lines += [
                f'            {keyword} (to_lower(trim(group_name))=="{group.lower()}") then',
                f"               {_call(suite, group, errmsg, errflg)}",
            ]
            keyword = "else if"
        if groups:
            lines += [
                "            else",
                f"               write(cdata%{errmsg}, '(*(a))') 'Group ' // "
                "to_lower(trim(group_name)) // ' not found'",
                "               ierr = 1",
                "            end if",
            ]
        lines += ["         else"]
        for group in groups:
            lines += [
                f"            {_call(suite, group, errmsg, errflg)}",
                f"            if (cdata%{errflg}/=0) then",
                f"               ierr = cdata%{errflg}",
                "               return",
                "            end if",
            ]
        lines += ["         end if"]
    else:
        lines += [
            "         if (present(group_name)) then",
            f"            write(cdata%{errmsg}, '(*(a))') 'The group {phase} is not "
            "supported, only the whole suite'",
            "            ierr = 1",
            "         else",
            f"            {_call(suite, suffix, errmsg, errflg)}",
            "         end if",
        ]
    # Both ways of setting ierr agree with the error flag the cap subroutines set
    lines += [f"         if (ierr==0) ierr = cdata%{errflg}"]
    return lines


def static_api_source(module_name, suites, meta_data):
    """Return the Fortran source of the static API module."""
    ccpp_module, errmsg, errflg = _control_members(meta_data)
    lines = [f"module {module_name}", ""]
    lines.append(f"   use {ccpp_module}, only: ccpp_t")
    for suite in suites:
        suite_module = f"{suite.attributes['name']}_cap"
        names = [
            _subroutine(suite, suffix) for _, suffix in PHASES if suffix is not None
        ]
        names += [_subroutine(suite, group.attributes["name"]) for group in suite]
        for name in names:
            lines.append(f"   use {suite_module}, only: {name}")
    lines += [
        "",
        "   implicit none",
        "",
        "   private",
        *(f"   public :: ccpp_physics_{phase}" for phase, _ in PHASES),
        "",
        "   contains",
        "",
        TO_LOWER,
    ]
    for phase, _ in PHASES:
        lines += _procedure(phase, suites, errmsg, errflg)
    lines.append(f"end module {module_name}")
    return "\n".join(lines) + "\n"


@dataclass(frozen=True)
class StaticAPI(ModulePass):
    """Generate the static API module that calls the suite caps.

    Runs after ``generate-suite-cap{static_api=true}``.
    """

    name = "generate-static-api"

    # Name of the module, and of the file that is written for it
    api_name: str = "ccpp_static_api"

    def apply(self, ctx: Context, op: builtin.ModuleOp) -> None:
        ccpp_mod = next(
            child
            for child in op.body.ops
            if isa(child, builtin.ModuleOp)
            and child.sym_name is not None
            and child.sym_name.data == "ccpp"
        )
        meta = BuildMetaDataDescriptions()
        meta.traverse(ccpp_mod)
        suites = BuildSchemeDescription()
        suites.traverse(ccpp_mod)

        api = builtin.ModuleOp([], sym_name=StringAttr(self.api_name))
        api.attributes["ftn_source"] = StringAttr(
            static_api_source(
                self.api_name, list(suites.schemes.values()), meta.meta_data
            )
        )
        op.body.block.add_op(api)
