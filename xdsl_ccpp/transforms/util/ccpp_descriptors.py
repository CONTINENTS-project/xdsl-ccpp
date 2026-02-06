from enum import Enum, StrEnum, auto

from ccpp_dsl.util.visitor import Visitor
from ccpp_dsl.dialects import ccpp

class CCPPType(StrEnum):
        SCHEME = auto()
        MODULE = auto()
        DDT = auto()

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
    def __init__(self, arg_tables=None):
        super().__init__()
        if arg_tables is None:
            self.arg_tables={}
        else:
            self.arg_tables=arg_tables

    def setAttr(self, key, value):
        if key == "type" and isinstance(value, str):
            value=CCPPType(value)
        super().setAttr(key, value, ["name", "type", "dependencies", "relative_path"])

    def setArgTable(self, k ,v):
        assert isinstance(v, CCPPArgument)
        self.arg_tables[k]=v

    def getArgTable(self, v):
        return self.arg_tables[v]

class CCPPArgumentTable(CCPPItem):
    def __init__(self, function_arguments=None):
        super().__init__()
        if function_arguments is None:
            self.function_arguments={}
        else:
            self.function_arguments=function_arguments

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
    def __init__(self, attributes):
        self.attributes=attributes
        self.children=[]

    def __iter__(self):
        return self.children.__iter__()

    def __next__(self):
        return self.children.__next__()

    def addChild(self, child):
        self.children.append(child)

class XMLScheme(XMLSuiteBase):
    def __init__(self, scheme_name):
        super().__init__({"name": scheme_name})

class XMLGroup(XMLSuiteBase):
    def __init__(self, group_name):
        super().__init__({"name": group_name})

class XMLSuite(XMLSuiteBase):
    def __init__(self, suite_name, version):
        super().__init__({"name": suite_name, "version": version})

class BuildMetaDataDescriptions(Visitor):
    def __init__(self):
        self.meta_data={}
        arg_token=None
        arg_table=None

    def traverse_table_properties_op(self, properties_op: ccpp.TablePropertiesOp):
        arg_tables={}
        self.arg_table=None
        for op in properties_op.body.ops:
            self.traverse(op)
            assert self.arg_table is not None
            k,v=self.arg_table
            arg_tables[k]=v
            self.arg_table=None
        ccpp_prop=CCPPTableProperties(arg_tables)
        ccpp_prop.setAttr("name", properties_op.table_name.data)
        ccpp_prop.setAttr("type", properties_op.table_type.data)
        self.meta_data[ccpp_prop.getAttr("name")]=ccpp_prop


    def traverse_argument_table_op(self, arg_table_op: ccpp.ArgumentTableOp):
        assert self.arg_table is None
        args={}
        self.arg_token=None
        for op in arg_table_op.body.ops:
            self.traverse(op)
            assert self.arg_token is not None
            args[self.arg_token.name]=self.arg_token
            self.arg_token=None
        new_arg_table=CCPPArgumentTable(args)

        new_arg_table.setAttr("name", arg_table_op.table_name.data)
        new_arg_table.setAttr("type", arg_table_op.table_type.data)
        self.arg_table=new_arg_table.getAttr("name"), new_arg_table

    def traverse_argument_op(self, arg_op: ccpp.ArgumentOp):
        assert self.arg_token is None
        arg=CCPPArgument(arg_op.arg_name.data)

        known_props=["standard_name", "long_name", "kind", "intent", "units", "type"]
        for kp in known_props:
            if kp in arg_op.properties:
                arg.setAttr(kp, arg_op.properties[kp].data)
        if "optional" in arg_op.properties:
            arg["optional"]=True

        self.arg_token=arg

class BuildSchemeDescription(Visitor):
    def __init__(self):
        self.schemes={}
        self.current_group=None
        self.current_scheme=None

    def traverse_suite_op(self, suite_op:ccpp.SuiteOp):
        current_suite=XMLSuite(suite_op.suite_name.data, suite_op.version.data)
        for op in suite_op.body.ops:
            self.traverse(op)
            assert self.current_group is not None
            current_suite.addChild(self.current_group)
            self.current_group=None
        self.schemes[suite_op.suite_name.data]=current_suite

    def traverse_group_op(self, group_op:ccpp.GroupOp):
        self.current_group=XMLGroup(group_op.group_name.data)
        for op in group_op.body.ops:
            self.traverse(op)
            assert self.current_scheme is not None
            self.current_group.addChild(self.current_scheme)
            self.current_scheme=None

    def traverse_scheme_op(self, scheme_op:ccpp.SchemeOp):
        self.current_scheme=XMLScheme(scheme_op.scheme_name.data)
