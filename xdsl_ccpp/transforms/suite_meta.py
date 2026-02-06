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
from xdsl.rewriter import InsertPoint

from ccpp_dsl.util.visitor import Visitor
from ccpp_dsl.dialects import ccpp

from ccpp_dsl.transforms.util.ccpp_descriptors import CCPPType, CCPPTableProperties, CCPPArgumentTable, CCPPArgument, BuildMetaDataDescriptions
from ccpp_dsl.transforms.util.typing import TypeConversions

class MoveCCPPIntoDedicatedModule(RewritePattern):
    def __init__(self, dedicated_module):
        self.dedicated_module=dedicated_module


class MoveSuiteOpIntoDedicatedModule(MoveCCPPIntoDedicatedModule):
    def __init__(self, dedicated_module):
        super().__init__(dedicated_module)

    @op_type_rewrite_pattern
    def match_and_rewrite(self, op: ccpp.SuiteOp, rewriter: PatternRewriter):
        op.detach()
        rewriter.insert_op(op, InsertPoint.at_end(self.dedicated_module.body.block))

class MoveTablePropertiesOpIntoDedicatedModule(MoveCCPPIntoDedicatedModule):
    def __init__(self, dedicated_module):
        super().__init__(dedicated_module)

    @op_type_rewrite_pattern
    def match_and_rewrite(self, op: ccpp.TablePropertiesOp, rewriter: PatternRewriter):
        op.detach()
        rewriter.insert_op(op, InsertPoint.at_end(self.dedicated_module.body.blocks[0]))

@dataclass(frozen=True)
class MetaCAP(ModulePass):
    name = "generate-meta-cap"

    def generate_function_signature(self, arg_table):
        in_args=[]
        out_args=[]

        for fn_arg in arg_table.getFunctionArguments():
            arg_type=TypeConversions.convert(fn_arg.getAttr("type"), fn_arg.getAttr("kind") if fn_arg.hasAttr("kind") else None)
            if fn_arg.hasAttr("intent"):
                if fn_arg.getAttr("intent") == "in":
                    in_args.append(arg_type)
                elif fn_arg.getAttr("intent") == "out":
                    out_args.append(arg_type)
                elif fn_arg.getAttr("intent") == "inout":
                    in_args.append(arg_type)
                    out_args.append(arg_type)
                else:
                    assert False
            else:
                # Assume inout
                in_args.append(arg_type)
                out_args.append(arg_type)

        return func.FuncOp.external(arg_table.getAttr("name"), in_args, out_args)

    def apply(self, ctx: Context, op: builtin.ModuleOp) -> None:
        mod=builtin.ModuleOp([], sym_name=builtin.StringAttr("ccpp"))
        PatternRewriteWalker(
            GreedyRewritePatternApplier(
                [
                    MoveSuiteOpIntoDedicatedModule(mod),
                    MoveTablePropertiesOpIntoDedicatedModule(mod),
                ]
            ),
            apply_recursively=False,
        ).rewrite_module(op)

        bmdd=BuildMetaDataDescriptions()
        bmdd.traverse(mod)
        meta_data_descriptions=bmdd.meta_data

        ops=[]
        for prop in meta_data_descriptions.values():
            for table in prop.arg_tables.values():
                ops.append(self.generate_function_signature(table))

        mod.body.block.add_ops(ops)

        op.body.block.add_op(mod)
