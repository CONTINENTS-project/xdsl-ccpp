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

@dataclass(frozen=True)
class CCPPCAP(ModulePass):

    name = "generate-ccpp-cap"

    def find_ccpp_module(self, ops):
        """Return the named 'ccpp' ModuleOp from the given op list, or None."""
        for op in ops:
            if isa(op, builtin.ModuleOp) and op.sym_name is not None and op.sym_name.data == "ccpp":
                return op
        return None

    def apply(self, ctx: Context, op: builtin.ModuleOp) -> None:
        ccpp_mod = self.find_ccpp_module(op.body.block.ops)
        assert ccpp_mod is not None

        # Build Python descriptor objects from the CCPP metadata IR
        bmdd = BuildMetaDataDescriptions()
        bmdd.traverse(ccpp_mod)
        meta_data_descriptions = bmdd.meta_data

