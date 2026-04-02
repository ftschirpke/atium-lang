# SPDX-License-Identifier: MIT
import lit.formats

from pathlib import Path

FILEPATH = Path(__file__)

config.name = "atium"
config.test_format = lit.formats.ShTest(True)
config.suffixes = {".atium"}

repo_root = FILEPATH.absolute().parent.parent.parent
config.test_source_root = str(FILEPATH.parent)

compiler = str(repo_root / "zig-out" / "bin" / "compiler")
config.substitutions.append(("%{compiler}", compiler))
