# Glossary

This repository's codegen-native backend lowers VM (virtual machine) and MIR (machine intermediate representation) programs into target machine code and other backend representations. Each feature groups one capability's domain model and rules in a domain package. Features that need host I/O or tool integration keep that code in a separate infrastructure package. Key types and functions below are representative public symbols, not a complete API list; `None` means no representative is listed for that entry.

## targets/x86-64

- Definition: Compiles VM instructions to x86-64 machine-code bytes and provides x86-64 target configuration, including speculative-execution mitigation controls.
- Package: `cl-cc/codegen-native/targets/x86-64`
- Key types: None.
- Key functions: None.
- Other contexts: The hardening feature tracks Windows CFG targets and GuardCF metadata; this target owns its x86-64 mitigation switches and instruction emission.

## targets/aarch64

- Definition: Compiles VM instructions to AArch64 machine-code bytes and exposes switches for optional instruction-set and security features. SME (Scalable Matrix Extension) support is experimental; `*sme-enabled*` allows higher-level lowering to select AArch64 SME encoders, and `aarch64-supports-sme-p` reports whether that switch is enabled.
- Package: `cl-cc/codegen-native/targets/aarch64`
- Key types: None.
- Key functions: `compile-to-aarch64-bytes`, `aarch64-supports-sme-p`
- Other contexts: This target owns its AArch64-specific feature switches and instruction emission.

## targets/riscv64

- Definition: Provides a 64-bit RISC-V assembler and emits RISC-V instructions and functions.
- Package: `cl-cc/codegen-native/targets/riscv64`
- Key types: None.
- Key functions: `make-riscv64-assembler`, `riscv64-emit-instruction`, `riscv64-emit-function`

## targets/wasm

- Definition: Compiles VM programs to WebAssembly text and emits instructions for shared-memory threads and atomics. `wasm-threads-flag-enabled-p` reports whether WebAssembly threads are enabled. Its infrastructure package builds ahead-of-time (AOT) WebAssembly result bundles and creates Source Map v3 data, which maps generated WebAssembly positions to source locations for browser debugging.
- Package: `cl-cc/codegen-native/targets/wasm`, `cl-cc/codegen-native/targets/wasm/infra`
- Key types: None.
- Key functions: `compile-to-wasm-wat`, `wasm-threads-flag-enabled-p`
- Other contexts: The `targets/wasm/infra` package owns `compile-to-aot-wasm`, its `wasm-aot-result` type, and `build-wasm-source-map-v3`. The emit/wasi feature supplies WebAssembly System Interface (WASI) Preview 2 imports for host APIs.

## targets/ppc64

- Definition: This experimental backend is disabled by default. It provides 64-bit PowerPC (PPC64) instruction encodings, including IBM POWER10 instructions, and function entry and exit sequences for the ELFv2 (version 2 Executable and Linkable Format ABI).
- Package: `cl-cc/codegen-native/targets/ppc64`
- Key types: None.
- Key functions: `emit-ppc64-instr`, `ppc64-elfv2-prologue`, `ppc64-backend-available-p`

## lowering

- Definition: Selects machine instructions from MIR and builds stack-map records for live garbage-collected values at safepoints, where execution may pause for garbage collection.
- Package: `cl-cc/codegen-native/lowering`
- Key types: `isel-diagnostic`, `cg-stack-map`
- Key functions: `isel-maximal-munch`, `cg-generate-safepoint-stack-map`, `cg-embed-stack-maps-after-safepoints`
- Other contexts: Each target's supported instruction set determines which instruction-selection rules apply.

## scheduling

- Definition: Schedules instructions after register allocation (post-RA), which maps virtual registers to hardware registers, while respecting instruction dependencies.
- Package: `cl-cc/codegen-native/scheduling`
- Key types: None.
- Key functions: `schedule-post-ra`

## hardening

- Definition: Provides Windows Control Flow Guard (CFG) support by tracking registered indirect-call targets, checking them when enabled, and producing GuardCF table metadata. Retpolines mitigate speculative execution of indirect branches; Spectre mitigations limit other speculative-execution risks. Stack protectors detect stack corruption, and shadow stacks protect return addresses.
- Package: `cl-cc/codegen-native/hardening`
- Key types: `win-cfg-invalid-target`
- Key functions: `win-cfg-register-function`, `win-cfg-enabled-p`
- Other contexts: The x86-64 and AArch64 targets own their mitigation switches and emit target-specific instructions. The x86-64 target emits guarded indirect-call sequences.

## sanitizer

- Definition: AddressSanitizer (ASan) checks memory accesses for errors; UndefinedBehaviorSanitizer (UBSan) inserts checks for undefined operations. This feature provides their instrumentation controls.
- Package: `cl-cc/codegen-native/sanitizer`
- Key types: None.
- Key functions: None.
- Other contexts: Target emitters read the ASan and UBSan instrumentation switches when adding memory-access and undefined-operation checks.

## emit/llvm

- Definition: Builds LLVM IR (intermediate representation) modules from VM programs and emits LLVM IR text.
- Package: `cl-cc/codegen-native/emit/llvm`
- Key types: `llvm-ir-module`
- Key functions: `vm-program->llvm-ir-module`, `emit-llvm-ir`
- Other contexts: The emit/mlir feature provides a separate MLIR representation.

## emit/mlir

- Definition: Builds Multi-Level Intermediate Representation (MLIR) modules from VM programs and emits MLIR text.
- Package: `cl-cc/codegen-native/emit/mlir`
- Key types: `mlir-module`
- Key functions: `vm-program->mlir-module`, `emit-mlir`
- Other contexts: The emit/llvm feature provides a separate LLVM IR representation.

## emit/ebpf

- Definition: Plans extended Berkeley Packet Filter (eBPF) programs and maps (key-value data shared with programs), checks that plans stay within the subset accepted by the kernel verifier (the safety checker for programs before execution), and emits bytecode or Executable and Linkable Format (ELF) objects.
- Package: `cl-cc/codegen-native/emit/ebpf`
- Key types: `ebpf-program-plan`, `ebpf-map-def`
- Key functions: `plan-ebpf-program`, `emit-ebpf-bytecode`, `emit-ebpf-elf-object`

## emit/wasi

- Definition: Creates WebAssembly System Interface (WASI) Preview 2 imports, which let WebAssembly modules call host-provided APIs, and injects their text forms into modules.
- Package: `cl-cc/codegen-native/emit/wasi`
- Key types: None.
- Key functions: `make-wasi-p2-imports`, `wasi-p2-import->wat`, `inject-wasi-p2-imports-into-wat`
- Other contexts: The targets/wasm feature provides WebAssembly text emission and module support.

## regalloc

- Definition: Maps temporary virtual registers to physical CPU registers, computes live intervals (ranges where values remain live), and spills values to memory when registers are scarce.
- Package: `cl-cc/codegen-native/regalloc`
- Key types: `live-interval`, `regalloc-result`
- Key functions: `compute-live-intervals`, `linear-scan-allocate`, `color-allocate`
- Other contexts: Target backends and lowering consume register-allocation results.
