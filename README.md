# cl-cc-codegen-native

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

## License

MIT
