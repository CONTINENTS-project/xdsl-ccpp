import argparse
import os, glob

from xdsl.dialects.builtin import ModuleOp

from xdsl_ccpp.transforms.suite_cap import SuiteCAP
from xdsl_ccpp.transforms.suite_meta import MetaCAP
from xdsl_ccpp.transforms.strip_ccpp import StripCCPP
from xdsl_ccpp.dialects.ccpp import CCPP

from pathlib import Path

from typing import Callable, Dict, List, IO

from xdsl.xdsl_opt_main import xDSLOptMain

import traceback


class CCPPOptMain(xDSLOptMain):
    def register_all_passes(self):
        super().register_all_passes()
        self.register_pass("generate-suite-cap", lambda: SuiteCAP)
        self.register_pass("generate-meta-cap", lambda: MetaCAP)
        self.register_pass("strip-ccpp", lambda: StripCCPP)

    def register_all_targets(self):
        super().register_all_targets()

        def _output_ftn(prog: ModuleOp, output: IO[str]):
            from xdsl_ccpp.backend.print_ftn import print_to_ftn

            print_to_ftn(prog, output)

        self.available_targets["ftn"] = _output_ftn

    def setup_pipeline(self):
        super().setup_pipeline()

    def register_all_arguments(self, arg_parser: argparse.ArgumentParser):
        super().register_all_arguments(arg_parser)
        arg_parser.add_argument(
            "--output-module-files",
            default=False,
            action="store_true",
            help="Outputs the generated module files on a module by module basis",
        )

    def register_all_dialects(self):
        super().register_all_dialects()
        self.ctx.load_dialect(CCPP)

    @staticmethod
    def get_passes_as_dict() -> Dict[str, Callable[[ModuleOp], None]]:
        """Add all passes that can be called by psy-opt in a dictionary."""

        pass_dictionary = {}

        passes = FtnOptMain.passes_native

        for pass_function in passes:
            pass_dictionary[pass_function.__name__.replace("_", "-")] = pass_function

        return pass_dictionary

    def get_passes_as_list(native=False, integrated=False) -> List[str]:
        """Add all passes that can be called by psy-opt in a dictionary."""

        pass_list = []

        passes = FtnOptMain.passes_native

        for pass_function in passes:
            pass_list.append(pass_function.__name__.replace("_", "-"))

        return pass_list

    def register_all_frontends(self):
        super().register_all_frontends()


def _output_modules_to_file_for_target(module, target, ccpp_main):
    ccpp_main.args.target = target
    i = 0
    # This will generate output for every sub module that is part of the
    # top level module
    for op in module.regions[0].blocks[0].ops:
        if isinstance(op, ModuleOp):
            module_contents = psy_main.output_resulting_program(op)
            f = open("generated/module_" + str(i) + "." + target, "w")
            f.write(module_contents)
            f.close()
            i += 1


def _empty_generate_dir():
    if not os.path.isdir("generated"):
        Path("generated").mkdir(parents=True, exist_ok=True)

    files = glob.glob("generated/*")
    for f in files:
        os.remove(f)


def main():
    ccpp_main = CCPPOptMain()

    try:
        ccpp_main.run()
        if ccpp_main.args.output_module_files:
            chunks, file_extension = ccpp_main.prepare_input()
            assert len(chunks) == 1
            module = ccpp_main.parse_chunk(chunks[0], file_extension)
            ftn_main.apply_passes(module)
            contents = ccpp_main.output_resulting_program(module)
            _empty_generate_dir()
            _output_modules_to_file_for_target(module, ccpp_main.args.target, ccpp_main)
    except SyntaxError as e:
        print(e.get_message())
        exit(0)


if __name__ == "__main__":
    main()
