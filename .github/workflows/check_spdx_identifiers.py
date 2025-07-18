#!/usr/bin/env python3
# SPDX-License-Identifier: MIT

import sys

from pathlib import Path

SPDX_IDENT = "SPDX-License-Identifier: "


def check(root: Path) -> bool:
    ignored = [".git", ".gitmodules", ".gitignore",
               "LICENSE",
               "zig-out", ".zig-cache",
               "third-party"]

    problems_found = 0

    for path in root.rglob("*"):
        if path.is_dir():
            continue
        skip = False
        for ignored_str in ignored:
            if ignored_str in path.parts:
                skip = True
                break
        if skip:
            continue

        with open(path, "r") as f:
            first_line = f.readline()
            if first_line.startswith("#!"):  # skip shebang
                first_line = f.readline()

        if SPDX_IDENT not in first_line:
            if problems_found == 0:
                print(f"Files found without \"{SPDX_IDENT}\" in the first line:")
            problems_found += 1
            print(path)

    return problems_found != 0


if __name__ == "__main__":
    sys.exit(check(Path.cwd()))
