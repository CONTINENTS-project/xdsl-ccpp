import argparse
import xml.etree.ElementTree as ET
from enum import Enum, StrEnum, auto
from xdsl.dialects.builtin import ModuleOp

from ccpp_dsl.dialects.ccpp import SuiteOp, GroupOp, SchemeOp, TablePropertiesOp, ArgumentTableOp, ArgumentOp

class CCPPType(StrEnum):
        SCHEME = auto()
        MODULE = auto()
        DDT = auto()

class MetaData:
    def __init__(self, table_properties, arg_tables):
        self.table_properties=table_properties
        self.arg_tables=arg_tables

class SchemeMetaData(MetaData):
    def __init__(self, table_properties, arg_tables):
        super().__init__(table_properties, arg_tables)

class HostMetaData(MetaData):
    def __init__(self, table_properties, arg_tables):
        super().__init__(table_properties, arg_tables)

class CCPPItem:
    def __init__(self):
        self.attrs={}

    def setAttr(self, key, value, allowed_keys=None):
        if allowed_keys is not None:
            assert key in allowed_keys
        self.attrs[key]=value

    def getAttr(self, key):
        assert key in self.attrs
        return self.attrs[key]

    def hasAttr(self, key):
        return key in self.attrs

    def getAttrs(self):
        return self.attrs

class CCPPTableProperties(CCPPItem):
    def __init__(self):
        super().__init__()

    def setAttr(self, key, value):
        if key == "type" and isinstance(value, str):
            value=CCPPType(value)
        super().setAttr(key, value, ["name", "type", "dependencies", "relative_path"])

class CCPPArgumentTable(CCPPItem):
    def __init__(self):
        super().__init__()
        self.function_arguments={}

    def setAttr(self, key, value):
        super().setAttr(key, value, ["name", "type"])

    def setFunctionArgument(self, fn_arg):
        assert isinstance(fn_arg, CCPPArgument)
        self.function_arguments[fn_arg.name]=fn_arg

    def getFunctionArgument(self, arg_name):
        return self.function_arguments[arg_name]

    def getFunctionArguments(self):
        return self.function_arguments.values()

class CCPPArgument(CCPPItem):
    def __init__(self, name):
        self.name=name
        super().__init__()

class XMLSuiteBase:
    def __init__(self, xml_node):
        self.attributes=xml_node.attrib
        self.children=[]

    def __iter__(self):
        return self.children.__iter__()

    def __next__(self):
        return self.children.__next__()

class XMLScheme(XMLSuiteBase):
    def __init__(self, xml_node):
        assert xml_node.tag=="scheme"
        self.scheme_name=xml_node.text

        super().__init__(xml_node)
        assert len(xml_node) == 0

class XMLGroup(XMLSuiteBase):
    def __init__(self, xml_node):
        assert xml_node.tag=="group"
        super().__init__(xml_node)

        for child in xml_node:
            if child.tag == "scheme":
                self.children.append(XMLScheme(child))

class XMLSuite(XMLSuiteBase):
    def __init__(self, xml_name):
        tree = ET.parse(xml_name)
        root = tree.getroot()

        assert root.tag=="suite"
        super().__init__(root)

        for child in root:
            if child.tag == "group":
                self.children.append(XMLGroup(child))

class ccppXML:
    class MetaParseState(Enum):
        PROPERTIES = 1
        ARG_TABLE = 2
        ARG = 3
        NONE = 4

    def initialise_argument_parser(self):
        parser = argparse.ArgumentParser(description="CCPP XML")
        self.set_parser_arguments(parser)
        return parser

    def set_parser_arguments(self, parser):
        parser.add_argument(
            "--scheme-files",
        )

        parser.add_argument(
            "--host-files",
        )

        parser.add_argument(
            "--suites",
        )

    def build_options_db_from_args(self, args):
        options_db = args.__dict__

        if "scheme_files" in options_db and options_db["scheme_files"] is not None:
            options_db["scheme_files"]=options_db["scheme_files"].split(",")
        else:
            options_db["scheme_files"]=[]

        if "host_files" in options_db and options_db["host_files"] is not None:
            options_db["host_files"]=options_db["host_files"].split(",")
        else:
            options_db["host_files"]=[]

        if "suites" in options_db and options_db["suites"] is not None:
            options_db["suites"]=options_db["suites"].split(",")
        else:
            options_db["suites"]=[]

        return options_db

    def parse_metadata_file(self, filename, isScheme):
        current_table_properties=None
        current_arg_table=None
        parse_state=ccppXML.MetaParseState.NONE
        table_arg_tables=[]
        current_arg=None

        with open(filename) as file:
            for line in file:
                sline=line.strip()
                if "[" in sline and "]" in sline:
                    token=sline.translate(str.maketrans('', '', "[]"))

                    if token=="ccpp-table-properties" or token=="ccpp-arg-table":
                        if current_arg is not None:
                            current_arg_table.setFunctionArgument(current_arg)
                            current_arg=None
                        if current_arg_table is not None:
                            table_arg_tables.append(current_arg_table)
                            current_arg_table=None

                    if token=="ccpp-table-properties":
                        assert current_table_properties is None
                        current_table_properties=CCPPTableProperties()
                        parse_state=ccppXML.MetaParseState.PROPERTIES
                    elif token=="ccpp-arg-table":
                        parse_state=ccppXML.MetaParseState.ARG_TABLE
                        current_arg_table=CCPPArgumentTable()
                    elif token[0] == " " and token[-1] == " ":
                        if current_arg is not None:
                            current_arg_table.setFunctionArgument(current_arg)
                        parse_state=ccppXML.MetaParseState.ARG
                        current_arg=CCPPArgument(token.strip())
                    else:
                        assert False
                else:
                    assert parse_state != ccppXML.MetaParseState.NONE
                    assert "=" in sline
                    tokens=sline.split("=")
                    if parse_state == ccppXML.MetaParseState.PROPERTIES:
                        assert current_table_properties is not None
                        current_table_properties.setAttr(tokens[0].strip(), tokens[1].strip())
                    elif parse_state == ccppXML.MetaParseState.ARG_TABLE:
                        assert current_arg_table is not None
                        current_arg_table.setAttr(tokens[0].strip(), tokens[1].strip())
                    elif parse_state == ccppXML.MetaParseState.ARG:
                        assert current_arg is not None
                        current_arg.setAttr(tokens[0].strip(), tokens[1].strip())

        if current_arg is not None:
            current_arg_table.setFunctionArgument(current_arg)
        if current_arg_table is not None:
            table_arg_tables.append(current_arg_table)

        assert current_table_properties is not None
        if isScheme:
            return SchemeMetaData(current_table_properties, table_arg_tables)
        else:
            return HostMetaData(current_table_properties, table_arg_tables)

    def build_suite_ir(self, suite):
        groups=[]
        for grp in suite:
            schemes=[]
            for scheme in grp:
                schemes.append(SchemeOp(scheme.scheme_name))
            groups.append(GroupOp(grp.attributes["name"], schemes))
        return SuiteOp(suite.attributes["name"], groups, suite.attributes["version"] if "version" in suite.attributes else None)

    def build_meta_ir(self, meta):
        tables=[]
        for table in meta.arg_tables:
            args=[]
            for fn_arg in table.getFunctionArguments():
                args.append(ArgumentOp(fn_arg.name, fn_arg.getAttr("type"), fn_arg.getAttrs()))
            tables.append(ArgumentTableOp(table.getAttr("name"), str(table.getAttr("type")), args))
        return TablePropertiesOp(table.getAttr("name"), str(table.getAttr("type")), tables)

    def run(self):
        ir_ops=[]
        parser = self.initialise_argument_parser()
        args = parser.parse_args()
        self.options_db = self.build_options_db_from_args(args)

        assert len(self.options_db["suites"]) == 1
        suites=XMLSuite(self.options_db["suites"][0])
        ir_ops.append(self.build_suite_ir(suites))

        schemes={}
        for scheme_file in self.options_db["scheme_files"]:
            c=self.parse_metadata_file(scheme_file, True)
            schemes[c.table_properties.getAttr("name")]=c
            ir_ops.append(self.build_meta_ir(c))

        hosts={}
        for host_file in self.options_db["host_files"]:
            c=self.parse_metadata_file(host_file, True)
            hosts[c.table_properties.getAttr("name")]=c
            ir_ops.append(self.build_meta_ir(c))

        print(ModuleOp(ir_ops))


def main():
    ccppXML().run()


if __name__ == "__main__":
    ccppXML().run()
