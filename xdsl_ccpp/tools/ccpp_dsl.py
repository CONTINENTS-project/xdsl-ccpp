import argparse
import os
import sys


class ccppMain:
    def initialise_argument_parser(self):
        parser = argparse.ArgumentParser(description="xDSL CCPP DSL compiler flow")
        self.set_parser_arguments(parser)
        return parser

    def set_parser_arguments(self, parser):
        parser.add_argument(
            "--suites",
            help="Comma-separated list of suite XML files",
        )
        parser.add_argument(
            "--scheme-files",
            help="Comma-separated list of .meta scheme files",
        )
        parser.add_argument(
            "--host-files",
            default=None,
            help="Comma-separated list of .meta host model files",
        )
        parser.add_argument(
            "-o",
            "--out",
            default=".",
            help="Output directory for generated .F90 files (default: current directory)",
        )
        parser.add_argument(
            "--stdout",
            action="store_true",
            help="Write generated Fortran to stdout instead of .F90 files",
        )
        parser.add_argument(
            "--host-name",
            default=None,
            help="Override the CamelCase host name prefix for generated subroutines "
            "(e.g. 'HelloWorld'); derived from the suite name when not set",
        )
        parser.add_argument(
            "-t",
            "--tempdir",
            default="tmp",
            help="Temporary directory for intermediate files (default: 'tmp')",
        )
        parser.add_argument(
            "-v",
            "--verbose",
            type=int,
            choices=[0, 1, 2],
            default=1,
            help="Verbosity level: 0=quiet, 1=normal, 2=detailed (default: 1)",
        )

    def build_options_db_from_args(self, args):
        options_db = args.__dict__

        if not options_db.get("suites"):
            raise ValueError("--suites is required")
        if not options_db.get("scheme_files"):
            raise ValueError("--scheme-files is required")

        options_db["suites"] = options_db["suites"].split(",")
        options_db["scheme_files"] = options_db["scheme_files"].split(",")
        if options_db["host_files"]:
            options_db["host_files"] = options_db["host_files"].split(",")
        else:
            options_db["host_files"] = []

        all_inputs = (
            options_db["suites"] + options_db["scheme_files"] + options_db["host_files"]
        )
        for f in all_inputs:
            if not os.path.exists(f):
                raise FileNotFoundError(f"Input file not found: '{f}'")

        return options_db

    def print_verbose_message(self, *messages):
        level = self.options_db["verbose"]
        if level == 1:
            print(messages[0])
        elif level == 2:
            print(messages[1] if len(messages) > 1 else messages[0])

    def post_stage_check(self, path):
        if not os.path.exists(path) or os.path.getsize(path) == 0:
            print(f"Error: expected output '{path}' was not created", file=sys.stderr)
            sys.exit(1)
        if self.options_db["verbose"] >= 1:
            print(f"  -> Completed, results in '{path}'")

    def remove_file_if_exists(self, *paths):
        for path in paths:
            if os.path.exists(path):
                os.remove(path)

    def run_frontend(self, tmp_dir):
        suites_arg = ",".join(self.options_db["suites"])
        scheme_files_arg = ",".join(self.options_db["scheme_files"])
        mlir_out = os.path.join(tmp_dir, "ccpp.mlir")

        cmd = (
            f"python3 -m xdsl_ccpp.frontend.ccpp_xml"
            f' --suites "{suites_arg}"'
            f' --scheme-files "{scheme_files_arg}"'
        )
        if self.options_db["host_files"]:
            host_files_arg = ",".join(self.options_db["host_files"])
            cmd += f' --host-files "{host_files_arg}"'
        cmd += f' > "{mlir_out}"'

        self.print_verbose_message(
            "Running CCPP frontend",
            f"Running CCPP frontend with command: {cmd}",
        )
        os.system(cmd)
        self.post_stage_check(mlir_out)
        return mlir_out

    def run_opt(self, tmp_dir, mlir_in):
        ftn_out = os.path.join(tmp_dir, "ccpp.ftn")
        ccpp_cap_pass = "generate-ccpp-cap"
        if self.options_db.get("host_name"):
            ccpp_cap_pass += f"{{host_name={self.options_db['host_name']}}}"
        cmd = (
            f'python3 -m xdsl_ccpp.tools.ccpp_opt "{mlir_in}"'
            f" -p generate-meta-cap,generate-meta-kinds,generate-suite-cap,{ccpp_cap_pass},generate-kinds,strip-ccpp"
            f' -t ftn > "{ftn_out}"'
        )
        self.print_verbose_message(
            "Running CCPP optimizer",
            f"Running CCPP optimizer with command: {cmd}",
        )
        os.system(cmd)
        self.post_stage_check(ftn_out)
        return ftn_out

    def split_fortran_output(self, ftn_file, out_dir):
        """Split the combined Fortran printer output into individual .F90 files.

        The printer emits sections separated by '// -----', each preceded by a
        '// FILE: <name>.F90' marker.  This method writes each section as a
        separate file in out_dir, or prints to stdout when --stdout is set.
        """
        with open(ftn_file) as f:
            content = f.read()

        sections = content.split("// -----")
        for section in sections:
            section = section.strip()
            if not section:
                continue
            lines = section.splitlines()
            if not lines[0].startswith("// FILE:"):
                continue
            filename = lines[0][len("// FILE:") :].strip()
            body = "\n".join(lines[1:]).lstrip("\n") + "\n"

            if self.options_db["stdout"]:
                print(body)
            else:
                out_path = os.path.join(out_dir, filename)
                with open(out_path, "w") as out_f:
                    out_f.write(body)
                self.print_verbose_message(
                    f"  -> Written '{out_path}'",
                    f"  -> Written '{out_path}' ({len(body)} bytes)",
                )

    def run(self):
        parser = self.initialise_argument_parser()
        args = parser.parse_args()
        try:
            self.options_db = self.build_options_db_from_args(args)
        except (ValueError, FileNotFoundError) as e:
            print(f"Error: {e}", file=sys.stderr)
            sys.exit(1)

        tmp_dir = self.options_db["tempdir"]
        out_dir = self.options_db["out"]
        os.makedirs(tmp_dir, exist_ok=True)
        if not self.options_db["stdout"]:
            os.makedirs(out_dir, exist_ok=True)

        mlir_file = self.run_frontend(tmp_dir)
        ftn_file = self.run_opt(tmp_dir, mlir_file)
        self.split_fortran_output(ftn_file, out_dir)

        self.remove_file_if_exists(mlir_file, ftn_file)
        if os.path.isdir(tmp_dir) and not os.listdir(tmp_dir):
            os.rmdir(tmp_dir)


def main():
    ccppMain().run()


if __name__ == "__main__":
    ccppMain().run()
