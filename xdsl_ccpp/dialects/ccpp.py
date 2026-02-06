from __future__ import annotations

from collections.abc import Sequence
from xdsl.dialects.builtin import (
    StringAttr,
    UnitAttr,
)

from xdsl.ir import Dialect, Operation, SSAValue, VerifyException, Block, Region, SpacedOpaqueSyntaxAttribute, EnumAttribute
from xdsl.irdl import (
    IRDLOperation,
    attr_def,
    irdl_attr_definition,
    irdl_op_definition,
    prop_def,
    opt_prop_def,
    region_def,
    traits_def,
)
from xdsl.utils.hints import isa

from xdsl.traits import NoTerminator

from enum import StrEnum, auto

class TableTypeKind(StrEnum):
    Scheme = auto()
    Module = auto()
    DDT = auto()

@irdl_attr_definition
class TableTypeKindAttr(EnumAttribute[TableTypeKind], SpacedOpaqueSyntaxAttribute):
    name = "ccp.table_type_kind"

@irdl_op_definition
class SuiteOp(IRDLOperation):
    name = "ccpp.suite"

    suite_name = prop_def(StringAttr)
    version = opt_prop_def(StringAttr)

    body = region_def("single_block")

    traits = traits_def(
        NoTerminator(),
    )

    def __init__(self, suite_name: str | StringAttr, body: Region | Sequence[Operation] | Sequence[Block], version:str | StringAttr | None = None):

        if isa(suite_name, str):
            suite_name=StringAttr(suite_name)

        properties={"suite_name": suite_name}

        if version is not None:
            if isa(version, str):
                version=StringAttr(version)
            properties["version"]=version

        super().__init__(
            regions=[body], properties=properties
        )

@irdl_op_definition
class GroupOp(IRDLOperation):
    name = "ccpp.group"

    group_name = prop_def(StringAttr)

    body = region_def("single_block")

    traits = traits_def(
        NoTerminator(),
    )

    def __init__(self, group_name: str | StringAttr, body: Region | Sequence[Operation] | Sequence[Block]):

        if isa(group_name, str):
            group_name=StringAttr(group_name)

        properties={"group_name": group_name}

        super().__init__(
            regions=[body], properties=properties
        )

@irdl_op_definition
class SchemeOp(IRDLOperation):
    name = "ccpp.scheme"

    scheme_name = prop_def(StringAttr)

    def __init__(self, scheme_name: str | StringAttr):

        if isa(scheme_name, str):
            scheme_name=StringAttr(scheme_name)

        properties={"scheme_name": scheme_name}

        super().__init__(
            properties=properties
        )

class TableBaseOp(IRDLOperation):
    table_name = prop_def(StringAttr, prop_name="name")
    table_type = prop_def(TableTypeKindAttr, prop_name="type")

    body = region_def("single_block")

    traits = traits_def(
        NoTerminator(),
    )

    def __init__(self, table_name: str | StringAttr, table_type: str | TableTypeKindAttr, body: Region | Sequence[Operation] | Sequence[Block]):

        if isa(table_name, str):
            table_name=StringAttr(table_name)

        if isa(table_type, str):
            table_type=TableTypeKindAttr(TableTypeKind(table_type))

        super().__init__(
            regions=[body], properties={"name": table_name, "type": table_type}
        )

@irdl_op_definition
class TablePropertiesOp(TableBaseOp):
    name = "ccpp.table_properties"

@irdl_op_definition
class ArgumentTableOp(TableBaseOp):
    name = "ccpp.arg_table"

@irdl_op_definition
class ArgumentOp(IRDLOperation):
    name = "ccpp.arg"

    arg_name = prop_def(StringAttr, prop_name="name")
    arg_type = prop_def(StringAttr, prop_name="type")
    standard_name = opt_prop_def(StringAttr)
    long_name = opt_prop_def(StringAttr)
    # TODO: dimensions
    kind = opt_prop_def(StringAttr)
    intent = opt_prop_def(StringAttr)
    units = opt_prop_def(StringAttr)
    optional = opt_prop_def(UnitAttr)

    def __init__(self, arg_name : str | StringAttr, arg_type : str | StringAttr, attributes):
        if isa(arg_name, str):
            arg_name=StringAttr(arg_name)

        if isa(arg_type, str):
            arg_type=StringAttr(arg_type)

        properties={"name":arg_name, "type":arg_type}
        prop_keys=list(attributes.keys())
        prop_keys.remove("type")
        # TODO below
        if "dimensions" in prop_keys: prop_keys.remove("dimensions")

        known_props=["standard_name", "long_name", "kind", "intent", "units"]
        for prop in known_props:
            if prop in attributes:
                properties[prop]=StringAttr(attributes[prop])
                prop_keys.remove(prop)

        if "optional" in attributes:
            if attributes[optional]:
                properties["optional"]=UnitAttr()
                prop_keys.remove("optional")

        assert len(prop_keys) == 0

        super().__init__(
            properties=properties
        )

CCPP = Dialect(
    "ccpp",
    [
        SuiteOp,
        GroupOp,
        SchemeOp,
        TablePropertiesOp,
        ArgumentTableOp,
        ArgumentOp,
    ],
    [
        TableTypeKindAttr,
    ],
)
