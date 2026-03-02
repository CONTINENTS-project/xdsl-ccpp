from dataclasses import dataclass

from xdsl.dialects import builtin, memref, func, arith, scf, llvm
from xdsl.dialects.builtin import i8, StringAttr
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
from xdsl.ir import Block, Region, SSAValue
from xdsl.utils.hints import isa

from xdsl_ccpp.util.visitor import Visitor
from xdsl_ccpp.dialects import ccpp
from xdsl_ccpp.dialects import ccpp_utils

from xdsl_ccpp.transforms.util.ccpp_descriptors import BuildMetaDataDescriptions, BuildSchemeDescription
from xdsl_ccpp.transforms.util.typing import TypeConversions

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
            intent = arg.getAttr("intent")
            if intent == "in" or intent == "inout":
                in_ssa.append(data_ops[arg.name])
            if intent == "out" or intent == "inout":
                val = data_ops[arg.name]
                out_types.append(val.type if isinstance(val, SSAValue) else val.results[0].type)
                out_tracking.append(val)

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

    def generateStringConstantGlobal(self, string: str) -> llvm.GlobalOp:
        return llvm.GlobalOp(
            llvm.LLVMArrayType.from_size_and_type(16, i8),
            "const_" + string,
            "internal",
            constant=True,
            value=StringAttr(string),
        )

    def generateStateCheckOps(self, check_string: str, data_ops):
        arr_type = llvm.LLVMArrayType.from_size_and_type(16, i8)

        addr_const = llvm.AddressOfOp("const_" + check_string, llvm.LLVMPointerType())
        loaded_const = llvm.LoadOp(addr_const, arr_type)
        addr_state = llvm.AddressOfOp("ccpp_suite_state", llvm.LLVMPointerType())
        loaded_state = llvm.LoadOp(addr_state, arr_type)

        strcmp_op = ccpp_utils.StrCmpOp(loaded_const, loaded_state, len(check_string))

        # strcmp returns 1 if equal; negate to get mismatch flag for scf.if
        one_i1 = arith.ConstantOp.from_int_and_width(1, 1)
        mismatch = arith.XOrIOp(strcmp_op.res, one_i1.result)

        one = arith.ConstantOp.from_int_and_width(1, 32)
        store = memref.StoreOp.get(one, data_ops["errflg"], [])
        if_op = scf.IfOp(mismatch.result, [], [one, store, scf.YieldOp()])

        return [addr_const, loaded_const, addr_state, loaded_state, strcmp_op, one_i1, mismatch, if_op]

    def generateStateAssignment(self, state_string: str):
        arr_type = llvm.LLVMArrayType.from_size_and_type(16, i8)
        addr_src = llvm.AddressOfOp("const_" + state_string, llvm.LLVMPointerType())
        loaded = llvm.LoadOp(addr_src, arr_type)
        addr_dst = llvm.AddressOfOp("ccpp_suite_state", llvm.LLVMPointerType())
        store = llvm.StoreOp(loaded, addr_dst)
        return [addr_src, loaded, addr_dst, store]

    def generateSubroutineCall(self, suite_description, tgt_subroutine_postfix, generated_subroutine_posfix=None, state_string: str | None = None, check_string: str | None = None):
        if generated_subroutine_posfix is None:
            assert tgt_subroutine_postfix is not None
            generated_subroutine_posfix=tgt_subroutine_postfix


        scheme_names=self.getSchemeNames(suite_description)
        arg_tables={}
        all_args={}
        if tgt_subroutine_postfix is not None:
            for scheme_name in scheme_names:
                arg_tables[scheme_name]=self.getArgumentTable(scheme_name, scheme_name+tgt_subroutine_postfix)

        # Collect unique args across all schemes, preserving first-seen order
            for scheme_name in scheme_names:
                for fn_arg in arg_tables[scheme_name].getFunctionArguments():
                    if fn_arg.name in all_args:
                        assert fn_arg.getAttr("type") == all_args[fn_arg.name].getAttr("type")
                    else:
                        all_args[fn_arg.name]=fn_arg

        # in/inout args become block arguments (input parameters to the cap subroutine)
        # out-only args are allocated locally
        input_arg_list=[a for a in all_args.values() if a.getAttr("intent") in ("in", "inout")]
        output_arg_list=[a for a in all_args.values() if a.getAttr("intent") == "out"]

        input_arg_types=[TypeConversions.convert(a.getAttr("type"), a.getAttr("kind") if a.hasAttr("kind") else None)
                         for a in input_arg_list]

        new_block=Block(arg_types=input_arg_types)

        data_ops={}
        for idx, fn_arg in enumerate(input_arg_list):
            new_block.args[idx].name_hint=fn_arg.name
            data_ops[fn_arg.name]=new_block.args[idx]

        alloc_ops={}
        for fn_arg in output_arg_list:
            arg_type=fn_arg.getAttr("type")
            data_shape=[]
            if arg_type=="character":
                data_shape.append(int(fn_arg.getAttr("kind").split("=")[1]))
            alloc_op=memref.AllocaOp.get(TypeConversions.getBaseType(arg_type), shape=data_shape)
            alloc_op.memref.name_hint=fn_arg.name
            alloc_ops[fn_arg.name]=alloc_op
            data_ops[fn_arg.name]=alloc_op

        # errflg and errmsg must always be present regardless of whether scheme
        # functions are called (e.g. when tgt_subroutine_postfix is None)
        if "errflg" not in data_ops:
            alloc_op=memref.AllocaOp.get(TypeConversions.getBaseType("integer"), shape=[])
            alloc_op.memref.name_hint="errflg"
            alloc_ops["errflg"]=alloc_op
            data_ops["errflg"]=alloc_op
        if "errmsg" not in data_ops:
            alloc_op=memref.AllocaOp.get(TypeConversions.getBaseType("character"), shape=[512])
            alloc_op.memref.name_hint="errmsg"
            alloc_ops["errmsg"]=alloc_op
            data_ops["errmsg"]=alloc_op

        initialisation_ops=self.generateVariableInitialisations(data_ops)

        call_ops=[]
        fn_sigs={}
        if tgt_subroutine_postfix is not None:
            for scheme_name in scheme_names:
                assert scheme_name+tgt_subroutine_postfix in self.meta_fn_sigs
                call_ops+=self.generateSchemeSubroutineCallOps(scheme_name+tgt_subroutine_postfix, arg_tables[scheme_name], data_ops)
                if scheme_name+tgt_subroutine_postfix not in fn_sigs:
                    fn_sigs[scheme_name+tgt_subroutine_postfix]=self.meta_fn_sigs[scheme_name+tgt_subroutine_postfix]

        # inout block args are also returned (they are both inputs and outputs)
        inout_return_vals=[data_ops[a.name] for a in input_arg_list if a.getAttr("intent") == "inout"]
        alloc_return_vals=list(alloc_ops.values())

        check_ops=self.generateStateCheckOps(check_string, data_ops) if check_string is not None else []
        state_ops=self.generateStateAssignment(state_string) if state_string is not None else []

        body_ops=alloc_return_vals+initialisation_ops+check_ops+call_ops+state_ops+[func.ReturnOp(*inout_return_vals, *alloc_return_vals)]

        new_block.add_ops(body_ops)
        body=Region()
        body.add_block(new_block)

        return_types=[v.type for v in inout_return_vals]+[o.results[0].type for o in alloc_return_vals]

        new_fn_type = builtin.FunctionType.from_lists(input_arg_types, return_types)
        new_func=func.FuncOp(
            suite_description.attributes["name"]+"_suite"+generated_subroutine_posfix,
            new_fn_type,
            body,
            visibility="public",
        )

        return new_func, list(fn_sigs.values())

    def clone_func_defs(self, func_defs):
        return [
            func.FuncOp.external(fd.sym_name.data, fd.function_type.inputs, fd.function_type.outputs)
            for fd in func_defs
        ]

    @op_type_rewrite_pattern
    def match_and_rewrite(self, op: ccpp.SuiteOp, rewriter: PatternRewriter):
        suite_description=self.suite_descriptions[op.suite_name.data]

        # (tgt_postfix, gen_postfix, state_string, check_string)
        subroutine_specs = [
            ("_init",     "_initialize", "initialized",  "uninitialized"),
            ("_finalize", None,          "uninitialized", "initialized"),
            ("_run",      "_physics",    None,            "in_time_step"),
            (None,      "_timestep_initial",    "in_time_step",    "initialized"),
            (None,      "_timestep_final",    "initialized",    "in_time_step"),
        ]

        generated_fns = []
        fn_sigs_by_name = {}
        check_strings_used = set()
        state_strings_used = set()

        for tgt_postfix, gen_postfix, state_string, check_string in subroutine_specs:
            fn, sigs = self.generateSubroutineCall(
                suite_description, tgt_postfix, gen_postfix,
                state_string=state_string, check_string=check_string,
            )
            generated_fns.append(fn)
            for sig in sigs:
                fn_sigs_by_name[sig.sym_name.data] = sig
            if check_string is not None:
                check_strings_used.add(check_string)
            if state_string is not None:
                state_strings_used.add(state_string)

        fn_sigs = self.clone_func_defs(list(fn_sigs_by_name.values()))

        ccpp_suite_state_global = llvm.GlobalOp(
            llvm.LLVMArrayType.from_size_and_type(16, i8),
            "ccpp_suite_state",
            "internal",
            value=StringAttr("uninitialized"),
        )

        all_strings_used = check_strings_used | state_strings_used
        string_const_globals = [self.generateStringConstantGlobal(s) for s in sorted(all_strings_used)]

        scheme_mod=builtin.ModuleOp([ccpp_suite_state_global]+string_const_globals+generated_fns+fn_sigs, sym_name=builtin.StringAttr(op.suite_name.data+"_cap"))

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
