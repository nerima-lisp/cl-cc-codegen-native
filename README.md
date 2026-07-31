# cl-cc-codegen-native  [![CI](https://github.com/nerima-lisp/cl-cc-codegen-native/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/nerima-lisp/cl-cc-codegen-native/actions/workflows/ci.yml) [![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

Native code generation for the [cl-cc](https://github.com/nerima-lisp/cl-cc)
Common Lisp compiler: register allocation, instruction selection and encoding
for x86-64 / AArch64 / RISC-V / WebAssembly, and object emission.

Three ASDF systems in one repository — `cl-cc-regalloc`, `cl-cc-codegen`,
`cl-cc-emit` — because the boundaries *between* them move while the boundary
*around* them does not: a new addressing mode touches the encoder and the
allocator's cost model in the same change.

## Why this could be extracted

cl-cc's split design gated this on §5-2 — hardening `cl-cc/vm`'s public
contract. An external repository cannot reach another package's internal
symbols, and `cl-cc/codegen` alone held 100 `cl-cc/vm::` references. `t/`
asserts the count is zero across all three systems, by scanning `src/` rather
than trusting it.

`cl-cc-mir`, `cl-cc-target` and `cl-cc-binary` are named as part of this bundle
in that design. They are separate repositories instead: each is a
dependency-free leaf that other things also use, so nothing here needs them
vendored.

## Usage

```lisp
(asdf:load-system "cl-cc-codegen-native")
```

## Development

```sh
nix develop
nix flake check
```

Running the test suite directly (outside `nix flake check`) goes through
`scripts/with-timeout.pl`, the same bounded-execution wrapper `cl-weave` and
its sibling nerima-lisp repositories use, rather than a bare `timeout` — that
binary is GNU coreutils and is not present by default on macOS:

```sh
perl scripts/with-timeout.pl 120 sbcl --script run-tests.lisp
```

### External tool invocation

Host CPU-feature probing (`sysctl -a` / `/proc/cpuinfo`) and the optional
Wasm toolchain integration (`wasm-opt`, `wat2wasm`, `wasm2wat`, `shasum`/
`sha*sum`/`openssl`) go through
[`cl-process-kit`](https://github.com/nerima-lisp/cl-process-kit) directly —
no adapter — rather than bare `uiop:run-program` wrapped in
`sb-ext:with-timeout`. A timed-out probe or tool invocation now escalates
SIGTERM → SIGKILL against the child's own process group; the previous
`sb-ext:with-timeout` approach only unwound the calling Lisp thread, which
could leave the external process itself still running.

### Coverage

`nix build .#checks.coverage` (or `perl scripts/with-timeout.pl 300 sbcl
--script scripts/run-coverage.lisp`) runs the suite a second time under
SBCL's `sb-cover` via cl-weave's built-in `:coverage` support — no adapter —
and prints expression/branch percentages for `codegen/src`, `regalloc/src`
and `emit/src`. As of 2026-07 that baseline is **20.2% expression, 24.5%
branch** (7372/36449, 631/2572): `t/` is a boundary and regression suite, not
exhaustive per-opcode coverage of the three backends' ~30 source files.
Raising it requires writing tests, not just measuring — this only wires the
measurement up. `checks.coverage` is informational and does not fail the
build; wire `:coverage-minimum-expression`/`:coverage-minimum-branch` into
`cl-cc-codegen-native.asd`'s `test-op` once there is a real target to hold.

## License

MIT
