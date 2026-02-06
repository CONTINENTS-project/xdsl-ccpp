from dataclasses import dataclass

from xdsl.dialects import builtin, memref, func, arith, scf
from xdsl.context import Context
from xdsl.passes import ModulePass
from xdsl.pattern_rewriter import (
    GreedyRewritePatternApplier,
    PatternRewriter,
    PatternRewriteWalker,
    RewritePattern,
    InsertPoint,
    op_type_rewrite_pattern,
)
from xdsl.ir import Block, Region
from xdsl.utils.hints import isa

from ccpp_dsl.util.visitor import Visitor
from ccpp_dsl.dialects import ccpp

from ccpp_dsl.transforms.util.ccpp_descriptors import CCPPType, CCPPTableProperties, CCPPArgumentTable, CCPPArgument, XMLSuiteBase, XMLScheme, XMLGroup, XMLSuite, BuildMetaDataDescriptions, BuildSchemeDescription
from ccpp_dsl.transforms.util.typing import TypeConversions

class GatherMetaFunctionSignatures(Visitor):
    def __init__(self):
        self.meta_functions={}

    def traverse_func_op(self, func_op: func.FuncOp):
        if func_op.is_declaration:
            self.meta_functions[func_op.sym_name.data]=func_op


class GenerateSuiteSubroutine(RewritePattern):
    def __init__(self, suite_descriptions, meta_data, meta_fn_sigs, top_level_module):
        self.suite_descriptions=suite_descriptions
        self.meta_data=meta_data
        self.meta_fn_sigs=meta_fn_sigs
        self.top_level_module=top_level_module

    def getSchemeNames(self, suite_description):
        scheme_names=[]
        for group in suite_description:
            for scheme in group:
                scheme_names.append(scheme.attributes["name"])
        return scheme_names

    def getArgumentTable(self, scheme_name, subroutine_name):
        assert scheme_name in self.meta_data
        return self.meta_data[scheme_name].getArgTable(subroutine_name)

    def generateVariableCreation(self, scheme_names, arg_tables):
        args_required={}
        for scheme_name in scheme_names:
            arg_table=arg_tables[scheme_name]
            for fn_arg in arg_table.getFunctionArguments():
                if fn_arg.name in args_required:
                    assert fn_arg.getAttr("type") == args_required[fn_arg.name].getAttr("type")
                else:
                    args_required[fn_arg.name]=fn_arg

        alloc_ops={}
        for arg in args_required.values():
            arg_type=arg.getAttr("type")
            data_shape=[]
            if arg_type=="character":
                data_shape.append(int(arg.getAttr("kind").split("=")[1]))

            alloc_ops[arg.name] = memref.AllocaOp.get(TypeConversions.getBaseType(arg_type), shape=data_shape)
        return alloc_ops

    def generateVariableInitialisations(self, data_ops):
        err_const=arith.ConstantOp.from_int_and_width(0, 32)

        store_op=memref.StoreOp.get(
                    err_const,
                    data_ops["errflg"],
                    []
                )

        return [err_const, store_op]

    def generateSchemeSubroutineCallOps(self, subroutine_name, arg_table, data_ops):
        in_ssa=[]
        out_types=[]
        out_tracking=[]
        for arg in arg_table.getFunctionArguments():
            if arg.getAttr("intent") == "in" or arg.getAttr("intent") == "inout":
                in_ssa.append(data_ops[arg.name])
            elif arg.getAttr("intent") == "out":
                out_types.append(data_ops[arg.name].results[0].type)
                out_tracking.append(data_ops[arg.name])

        assert len(out_types) == len(out_tracking)
        call_op=func.CallOp(subroutine_name, in_ssa, out_types)

        store_ops=[]
        for idx, out_var in enumerate(out_tracking):
            store_ops.append(memref.CopyOp(call_op.results[idx], out_var))

        err_const_comp=arith.ConstantOp.from_int_and_width(0, 32)
        load_op=memref.LoadOp.get(data_ops["errflg"], [])
        cmp=arith.CmpiOp(load_op, err_const_comp, 0)
        conditional_op=scf.IfOp(cmp, [], [call_op]+store_ops+[scf.YieldOp()])

        return [err_const_comp, cmp, load_op, conditional_op]

    def generateSubroutineCall(self, suite_description, tgt_subroutine_postfix, generated_subroutine_posfix=None):
        if generated_subroutine_posfix is None:
            generated_subroutine_posfix=tgt_subroutine_postfix

        scheme_names=self.getSchemeNames(suite_description)
        arg_tables={}
        for scheme_name in scheme_names:
            arg_tables[scheme_name]=self.getArgumentTable(scheme_name, scheme_name+tgt_subroutine_postfix)

        input_arg_types=[]

        new_block=Block(arg_types=input_arg_types)

        create_data_ops=self.generateVariableCreation(scheme_names, arg_tables)

        initialisation_ops=self.generateVariableInitialisations(create_data_ops)

        call_ops=[]
        fn_sigs={}
        for scheme_name in scheme_names:
            assert scheme_name+tgt_subroutine_postfix in self.meta_fn_sigs
            call_ops+=self.generateSchemeSubroutineCallOps(scheme_name+tgt_subroutine_postfix, arg_tables[scheme_name], create_data_ops)
            if scheme_name+tgt_subroutine_postfix not in fn_sigs:
                fn_sigs[scheme_name+tgt_subroutine_postfix]=self.meta_fn_sigs[scheme_name+tgt_subroutine_postfix]

        body_ops=list(create_data_ops.values())+initialisation_ops+call_ops+[func.ReturnOp(*list(create_data_ops.values()))]

        new_block.add_ops(body_ops)
        body=Region()
        body.add_block(new_block)

        return_types=[o.results[0].type for o in create_data_ops.values()]

        new_fn_type = builtin.FunctionType.from_lists(input_arg_types, return_types)
        new_func=func.FuncOp(
        suite_description.attributes["name"]+"_suite"+generated_subroutine_posfix,
        new_fn_type,
        body,
        )

        return new_func, list(fn_sigs.values())

    def clone_func_defs(self, *func_defs):
        ops=[]
        for fn_def_l in func_defs:
            for func_def in fn_def_l:
              ops.append(func.FuncOp.external(func_def.sym_name.data, func_def.function_type.inputs, func_def.function_type.outputs))
        return ops

    @op_type_rewrite_pattern
    def match_and_rewrite(self, op: ccpp.SuiteOp, rewriter: PatternRewriter):
        suite_description=self.suite_descriptions[op.suite_name.data]

        init_fn, init_fn_sigs=self.generateSubroutineCall(suite_description, "_init", "_initialize")
        finalise_fn, finalise_fn_sigs=self.generateSubroutineCall(suite_description, "_finalize")

        fn_sigs=self.clone_func_defs(init_fn_sigs, finalise_fn_sigs)

        scheme_mod=builtin.ModuleOp([init_fn, finalise_fn]+fn_sigs, sym_name=builtin.StringAttr(op.suite_name.data+"_cap"))

        rewriter.insert_op(scheme_mod, InsertPoint.at_start(self.top_level_module.body.block))

@dataclass(frozen=True)
class SuiteCAP(ModulePass):
    name = "generate-suite-cap"

    def find_ccpp_module(self, ops):
        for op in ops:
            if isa(op, builtin.ModuleOp) and op.sym_name is not None and op.sym_name.data == "ccpp":
                return op
        return None

    def apply(self, ctx: Context, op: builtin.ModuleOp) -> None:

        ccpp_mod = self.find_ccpp_module(op.body.block.ops)
        assert ccpp_mod is not None

        bmdd=BuildMetaDataDescriptions()
        bmdd.traverse(ccpp_mod)
        meta_data_descriptions=bmdd.meta_data

        meta_fn_sig=GatherMetaFunctionSignatures()
        meta_fn_sig.traverse(ccpp_mod)
        meta_fn_sigs=meta_fn_sig.meta_functions

        bsd=BuildSchemeDescription()
        bsd.traverse(ccpp_mod)
        scheme_descriptions=bsd.schemes

        PatternRewriteWalker(
            GreedyRewritePatternApplier(
                [
                    GenerateSuiteSubroutine(scheme_descriptions, meta_data_descriptions, meta_fn_sigs, op),
                ]
            ),
            apply_recursively=False,
        ).rewrite_module(op)
