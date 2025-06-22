<!-- SPDX-License-Identifier: MIT -->
# atium
A programming language project aimed at learning and experimentation.

More specifically, this project is not aimed at creating a programming language for use in real-world applications,
but rather a toy project where I, and potential contributors, can experiment and learn about language and compiler
related topics.

Currently, the motivations and ideas for the project are:
- build a big project using Zig
- design a modern, low-level (but not feature-complete) programming language akin to Zig and Rust
- build modern compiler using MLIR
- design a memory-safe language (similar to Rust)
    - create a borrow-checker (or something similar)
    - language design such that it restricts the programmer as little as possible

### Licensing

The source code in this repository is licensed under the MIT License (see [LICENSE](./LICENSE)).

```
SPDX-License-Identifier: MIT
```

#### Third-Party Code

This project includes third-party code that is unmodified and licensed under the respective license:

- the LLVM project (see `third-party/llvm-project`) is licensed under the Apache License v2.0 with LLVM
  exceptions (see [LICENSE.txt](./third-party/llvm-project/LICENSE.txt))
