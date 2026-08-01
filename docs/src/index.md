# cl-cc-codegen-native

Native code generation for the [cl-cc](https://github.com/nerima-lisp/cl-cc)
Common Lisp compiler. It takes the VM instruction stream the front end
produces, assigns machine registers to its unlimited virtual registers, selects
and encodes target instructions for x86-64, AArch64, RISC-V and WebAssembly,
and emits object output.

```lisp
(asdf:load-system "cl-cc-codegen-native")

;; A VM program in, a byte vector of x86-64 machine code out.
(cl-cc/codegen:compile-to-x86-64-bytes program)
;; => #(85 72 137 229 ...)
```

## Three systems, one repository

The repository holds three ASDF systems rather than one, and three systems
rather than three repositories.

| System | Package | Responsibility |
|---|---|---|
| `cl-cc-regalloc` | `cl-cc/regalloc` | Liveness analysis, linear-scan and graph-colouring allocation, spill code |
| `cl-cc-codegen` | `cl-cc/codegen` | Instruction selection, per-target encoders, post-RA scheduling, WebAssembly |
| `cl-cc-emit` | `cl-cc/emit` | Object emission: eBPF, LLVM IR, MLIR, RISC-V assembly, Wasm source maps |

They ship together because the boundaries *between* them move while the
boundary *around* them does not: a new addressing mode touches the encoder and
the allocator's cost model in the same change. `cl-cc-codegen-native` is an
umbrella system that depends on all three and defines no components of its own,
so loading it pulls the whole native backend.

`cl-cc/codegen` re-exports the register-allocation symbols it uses, and
`cl-cc/emit` re-exports both. A symbol such as `allocate-registers` is
therefore reachable under all three package names.

## Where to go next

- [Getting Started](getting-started.md) — add the flake input, load the
  system, and compile one VM program to machine code.
- [Reference: API](reference/api.md) — the exported symbols, grouped by
  subsystem.

## Contributing and support

Issue templates, the contribution guide, the code of conduct and the security
policy are org-level defaults published from
[nerima-lisp/.github](https://github.com/nerima-lisp/.github). Release history
lives in this repository's
[GitHub Releases](https://github.com/nerima-lisp/cl-cc-codegen-native/releases).
