# API Reference

The repository ships three ASDF systems, each with its own package. This page
groups symbols by the package that defines them.

| Package | System | Covered below |
|---|---|---|
| `cl-cc/regalloc` | `cl-cc-regalloc` | [Register Allocation](#register-allocation) |
| `cl-cc/codegen` | `cl-cc-codegen` | [Instruction Selection and Encoding](#instruction-selection-and-encoding) |
| `cl-cc/emit` | `cl-cc-emit` | [Object Emission](#object-emission) |

`cl-cc/codegen` re-exports the register-allocation symbols it consumes, and
`cl-cc/emit` re-exports symbols from both. Where a symbol appears under more
than one package the entry below names the package that defines it; the
re-exported names are the same symbols.

## Register Allocation

Defined by `cl-cc/regalloc`. Maps unlimited VM virtual registers (`:r0`, `:r1`,
...) onto a target's physical registers, spilling to the stack when the pool
runs out.

### `allocate-registers`

```lisp
(cl-cc/regalloc:allocate-registers instructions cc &optional float-vregs allocation-policy)
  => regalloc-result
```

Runs register allocation over a VM instruction list. This is the entry point
the native backends call; the individual passes below exist for driving or
testing the pipeline in pieces.

| Argument | Type | Default | Meaning |
|---|---|---|---|
| `instructions` | `list` | — | VM instructions to allocate over |
| `cc` | `target-desc` | — | Target descriptor supplying the register pools |
| `float-vregs` | `list` | `nil` | Virtual registers to allocate from the FP pool |
| `allocation-policy` | `list` | `nil` | Plist biasing preferred registers; derived from the instructions when omitted |

**Returns**: a `regalloc-result` carrying the assignment, the spill map, the
spill count, GPR and FP pressure, and the rewritten instruction stream with
spill code inserted.

**Signals**: `none`

### `linear-scan-allocate`

```lisp
(cl-cc/regalloc:linear-scan-allocate intervals cc &optional (spill-slot-offset 0))
  => (values assignment spill-map spill-count)
```

Performs linear scan allocation over a list of live intervals sorted by start
point. Expiring, coalescing and eviction all happen in one forward pass, which
is why the input must already be sorted.

**Returns**: three values — an `eq` hash table of vreg to physical register, an
`eq` hash table of vreg to spill slot, and the highest slot index assigned.

**Signals**: `none`

### `color-allocate`

```lisp
(cl-cc/regalloc:color-allocate intervals available-regs &optional (spill-slot-offset 0) cc)
  => (values assignment spill-map spill-count)
```

Performs Chaitin-Briggs graph-coloring allocation. `intervals` must all come
from a single register class and `available-regs` is the physical color set for
that class.

**Returns**: the same three values as `linear-scan-allocate`.

**Signals**: `none`

### `*regalloc-allocation-strategy*`

```lisp
cl-cc/regalloc:*regalloc-allocation-strategy*
  => :linear-scan
```

Selects the default strategy. Valid values are `:linear-scan` and `:color`.
Linear scan is the default.

### `*ml-regalloc-enabled*`

```lisp
cl-cc/regalloc:*ml-regalloc-enabled*
  => nil
```

When non-`nil`, spill decisions use the weighted spill-cost prediction of
`regalloc-ml-spill-cost` instead of the default heuristic.

### `compute-live-intervals`

```lisp
(cl-cc/regalloc:compute-live-intervals instructions &optional float-vregs)
  => list of live-interval
```

Computes the live range of every virtual register in `instructions`.

**Returns**: a list of `live-interval` objects sorted by start point, which is
the order `linear-scan-allocate` requires.

**Signals**: `none`

**Example**:

```lisp
(cl-cc/regalloc:compute-live-intervals
 (list (cl-cc/vm:make-vm-const :dst :r0 :value 3)
       (cl-cc/vm:make-vm-const :dst :r1 :value 4)
       (cl-cc/vm:make-vm-add :dst :r2 :lhs :r0 :rhs :r1)
       (cl-cc/vm:make-vm-ret :reg :r2)))
;; => a list of three LIVE-INTERVAL objects, for :R0, :R1 and :R2
```

### `split-live-interval`

```lisp
(cl-cc/regalloc:split-live-interval interval minimum-hole-size)
  => (values children boundaries)
```

Splits `interval` at gaps between use positions larger than
`minimum-hole-size`, so a register held across a long idle stretch can be
released and reclaimed instead of occupying the pool throughout.

**Returns**: the child live intervals as the primary value, and internal
split-boundary records as a secondary value. The allocator uses the latter to
place fixed spill stores and loads at split edges. The `live-interval`
structure itself is left unchanged for external callers.

**Signals**: `none`

### `color-spill-slots`

```lisp
(cl-cc/regalloc:color-spill-slots spilled &optional (spill-slot-offset 0))
  => hash-table
```

Shares stack slots between spilled virtual registers whose live ranges do not
overlap, shrinking the frame. The greedy ordering is by spill weight, then
interval length, then start position, which keeps the output deterministic.

**Returns**: a hash table mapping vreg to a 1-origin slot number. Slots stay
1-origin so the `[RBP - slot*8]` spill instruction format is unchanged.

**Signals**: `none`

### `regalloc-result`

```lisp
(cl-cc/regalloc:regalloc-result)
```

Structure holding the outcome of allocation. Accessors use the `regalloc-`
prefix rather than the structure name.

| Accessor | Type | Meaning |
|---|---|---|
| `regalloc-assignment` | `hash-table` | vreg to physical register |
| `regalloc-spill-map` | `hash-table` | vreg to spill slot |
| `regalloc-spill-count` | `fixnum` | Number of stack slots the frame needs |
| `regalloc-gpr-pressure` | `fixnum` | Peak general-purpose register pressure |
| `regalloc-fp-pressure` | `fixnum` | Peak floating-point register pressure |
| `regalloc-instructions` | `list` | The instruction stream after spill insertion |

### `regalloc-lookup`

```lisp
(cl-cc/regalloc:regalloc-lookup result vreg)
  => keyword-or-nil
```

Looks up the physical register assigned to `vreg`.

**Returns**: the physical register keyword, or `nil` when `vreg` was spilled.

**Signals**: `none`

### `live-interval`

```lisp
(cl-cc/regalloc:make-live-interval &key vreg start end use-positions parameter-index
                                        coalesce-with crosses-call-p fp-p
                                        remat-const remat-inst return-value-p
                                        phys-reg spill-slot)
  => live-interval
```

One virtual register's live range. Accessors use the `interval-` prefix.

| Accessor | Meaning |
|---|---|
| `interval-vreg` | The virtual register this interval describes |
| `interval-start` | Instruction index of the defining write |
| `interval-end` | Instruction index of the last read |
| `interval-phys-reg` | Physical register assigned, or `nil` |
| `interval-spill-slot` | Stack slot assigned, or `nil` |
| `interval-remat-const` | Constant to rematerialize instead of reloading |
| `interval-remat-inst` | Instruction to rematerialize instead of reloading |

### `instruction-defs`

```lisp
(cl-cc/regalloc:instruction-defs inst)
  => list
```

Generic function returning the virtual registers written by `inst`. Liveness
analysis dispatches on it, so a new VM instruction type needs a method here to
participate in allocation.

### `instruction-uses`

```lisp
(cl-cc/regalloc:instruction-uses inst)
  => list
```

Generic function returning the virtual registers read by `inst`.

### `regalloc-loop-depths`

```lisp
(cl-cc/regalloc:regalloc-loop-depths instructions)
  => hash-table
```

Derives a loop-nesting depth for each instruction position by finding backward
branches. Positions inside a loop body cost more to spill, which is what the
table is consumed for.

**Returns**: a hash table mapping instruction position to loop depth.

**Signals**: `none`

### `regalloc-ml-spill-cost`

```lisp
(cl-cc/regalloc:regalloc-ml-spill-cost interval &optional loop-depths)
  => number
```

Predicts the cost of spilling `interval`, weighting each use position by one
plus eight times its loop depth. Higher scores mean the interval should be kept
in a register.

**Signals**: `none`

### `vm-spill-store`

```lisp
(cl-cc/regalloc:make-vm-spill-store :src-reg reg :slot slot)
  => vm-spill-store
```

VM instruction storing a register into the spill slot at `[RBP - slot*8]`.
Read the operands back with `vm-spill-src` and `vm-spill-slot`.

### `vm-spill-load`

```lisp
(cl-cc/regalloc:make-vm-spill-load :dst-reg reg :slot slot)
  => vm-spill-load
```

VM instruction loading the spill slot at `[RBP - slot*8]` into a register.
Read the operands back with `vm-spill-dst` and `vm-spill-slot`.

### `*current-regalloc*`

```lisp
cl-cc/regalloc:*current-regalloc*
  => nil
```

Bound to the active `regalloc-result` while a backend emits code, so emitters
can resolve virtual registers without threading the result through every call.

## Instruction Selection and Encoding

Defined by `cl-cc/codegen`. Turns an allocated VM program into target
instruction bytes.

### `compile-to-x86-64-bytes`

```lisp
(cl-cc/codegen:compile-to-x86-64-bytes program &key retpoline spectre-mitigations
                                                    stack-protector shadow-stack
                                                    asan msan tsan ubsan hwasan
                                                    eh-model)
  => (simple-array (unsigned-byte 8) (*))
```

Compiles a `cl-cc/vm:vm-program` to x86-64 machine code. Runs pre-RA
scheduling, register allocation, post-RA scheduling and encoding in one call.

The keyword arguments enable hardening and instrumentation: `retpoline` and
`spectre-mitigations` for speculative-execution mitigations, `stack-protector`
and `shadow-stack` for stack integrity, `asan`, `msan`, `tsan`, `ubsan` and
`hwasan` for the corresponding sanitizers, and `eh-model` to select the
exception-handling model.

**Returns**: a byte vector of encoded instructions.

**Signals**: `none`

### `compile-to-aarch64-bytes`

```lisp
(cl-cc/codegen:compile-to-aarch64-bytes program &key retpoline stack-protector shadow-stack
                                                     asan msan tsan ubsan hwasan)
  => (simple-array (unsigned-byte 8) (*))
```

Compiles a `vm-program` to AArch64 machine code. `stack-protector` and
`shadow-stack` bind the corresponding AArch64 feature flags for the duration of
the call.

**Signals**: `none`

### `compile-to-riscv64-bytes`

```lisp
(cl-cc/codegen:compile-to-riscv64-bytes program &key retpoline stack-protector shadow-stack
                                                     asan msan tsan ubsan hwasan)
  => (simple-array (unsigned-byte 8) (*))
```

Compiles a `vm-program` to RV64IMAFDC machine code.

**Signals**: `none`

### `schedule-post-ra`

```lisp
(cl-cc/codegen:schedule-post-ra instructions regalloc-result)
  => list
```

Pressure-aware list scheduling after register allocation. `instructions` must
be the allocated stream taken from `regalloc-result`. The pass resolves virtual
registers to physical ones with `regalloc-lookup`, builds dependency DAGs from
physical RAW, WAR and WAW hazards, and breaks ties on physical register
pressure. Calls, stores, spill helpers, control flow, unknown operands and
side-effecting instructions are fixed barriers, which keeps the pass
conservative and deterministic.

**Signals**: `none`

### `isel-vm-program`

```lisp
(cl-cc/codegen:isel-vm-program program &key (target :x86-64))
  => vm-program
```

Routes `program` through the MIR pipeline: VM to MIR, MIR-level passes,
instruction selection, and back to VM. The output is still the VM instruction
format, so register allocation and the backends are unaffected by whether this
path was taken.

**Signals**: `isel-diagnostic` (no selection rule covers some subtree)

### `vm-program->mir-module`

```lisp
(cl-cc/codegen:vm-program->mir-module program &key (name :toplevel))
  => mir-module
```

Converts a flat VM program into a MIR module, creating label-aligned blocks and
linking the obvious CFG edges. Each source VM instruction is stored in
instruction metadata so unsupported operations round-trip safely.

**Signals**: `isel-diagnostic` (`program` is not a `vm-program`)

### `optimize-mir-module-for-isel`

```lisp
(cl-cc/codegen:optimize-mir-module-for-isel module)
  => mir-module
```

Runs the MIR-level SSA passes the pipeline needs: integer constant folding and
pure-expression CSE within each function. Side-effecting VM instructions remain
metadata-preserved pass-through nodes. Returns `module`, modified in place.

**Signals**: `none`

### `mir-module->vm-program`

```lisp
(cl-cc/codegen:mir-module->vm-program module template-program &key (target :x86-64))
  => vm-program
```

Selects target instructions from `module` and returns a VM program.
`template-program` supplies the result register, leaf flag and calling
conventions for the new program. Spill handling stays with the register
allocator.

**Signals**: `none`

### `isel-maximal-munch`

```lisp
(cl-cc/codegen:isel-maximal-munch tree target &key rules)
  => list
```

Covers `tree` with `target`'s rules using maximal munch. `rules` defaults to
`(isel-rules-for-target target)`.

**Returns**: a post-order list of `(rule . bindings)` tiles.

**Signals**: `isel-diagnostic` (no rule matches some node)

### `register-isel-rule`

```lisp
(cl-cc/codegen:register-isel-rule rule)
  => isel-rule
```

Registers `rule` under its own target and returns it.

**Signals**: `none`

### `isel-rules-for-target`

```lisp
(cl-cc/codegen:isel-rules-for-target target)
  => list
```

Returns a fresh list of the instruction-selection rules registered for
`target`. The copy means callers cannot corrupt the rule table.

**Signals**: `none`

### `isel-rule`

```lisp
(cl-cc/codegen:isel-rule)
```

One instruction-selection rule. The constructor is internal; rules reach the
table through `register-isel-rule`. Accessors are `isel-rule-name`,
`isel-rule-target`, `isel-rule-pattern`, `isel-rule-result-op`,
`isel-rule-cost`, `isel-rule-size` and `isel-rule-emitter`. `cost` and `size`
default to `1` and are what maximal munch compares when several rules match.

Patterns use symbols beginning with `?` as pattern variables, so `?lhs` binds
whatever subtree occupies that position.

### `isel-diagnostic`

```lisp
(cl-cc/codegen:isel-diagnostic)
```

Condition of type `error` signalled when instruction selection cannot proceed.
`isel-diagnostic-message` reads the explanatory message.

### `*isel-x86-64-rules*`

```lisp
cl-cc/codegen:*isel-x86-64-rules*
```

The list of `isel-rule` records registered for `:x86-64`.
`cl-cc/codegen:*isel-aarch64-rules*` is the AArch64 equivalent.

### `calling-convention`

```lisp
(cl-cc/codegen:calling-convention)
```

Backend calling-convention policy. The constructor is internal; obtain an
instance from the two exported policy variables below. Accessors are
`calling-convention-name`,
`calling-convention-arg-regs`, `calling-convention-callee-saved` and
`calling-convention-omit-frame-pointer-p`. `name` defaults to `:external`.

`cl-cc/codegen:*external-calling-convention*` uses the platform ABI unchanged
for exported functions; `cl-cc/codegen:*internal-calling-convention*` is the
counterpart for calls the compiler fully controls.

### `x86-64-target`

```lisp
(cl-cc/codegen:x86-64-target)
```

Target class for x86-64 code generation. `target-regalloc` is its accessor for
the `regalloc-result` in force, and `target-spill-base-reg` names the register
spill offsets are taken from. `cl-cc/codegen:aarch64-target` is the AArch64
counterpart.

### `emit-instruction`

```lisp
(cl-cc/codegen:emit-instruction target inst stream)
```

Generic function encoding one VM instruction for `target` onto `stream`.
Methods are specialised on both the target class and the instruction class, so
adding an instruction to a backend means adding a method here.

### `compile-to-wasm-wat`

```lisp
(cl-cc/codegen:compile-to-wasm-wat program)
  => string
```

Compiles a `vm-program` to a complete WebAssembly text-format module using the
Wasm GC backend.

**Signals**: `none`

### `compile-to-wasm-binary`

```lisp
(cl-cc/codegen:compile-to-wasm-binary program)
  => vector
```

Compiles a `vm-program` to a minimal WebAssembly binary module.

**Signals**: `none`

### `compile-to-aot-wasm`

```lisp
(cl-cc/codegen:compile-to-aot-wasm program &key deterministic)
  => wasm-aot-result
```

Compiles `program` to a self-contained ahead-of-time `.wasm` bundle. The pass
prunes dead exports and imports, optionally applies deterministic ordering,
integrates `wat2wasm` and `wasm-opt` when they are on `PATH`, and embeds a
content-hash custom section. None of the external tools are required: when one
is missing or fails, the un-processed bytes are used instead.

When `deterministic` is true the module is ordered canonically and the build
hash is appended as a custom section.

**Signals**: `none`

### `wasm-aot-result`

```lisp
(cl-cc/codegen:wasm-aot-result)
```

Bundle returned by `compile-to-aot-wasm`; the constructor is internal.
`wasm-aot-result-bytes` is the
module, `wasm-aot-result-wat` the text form for debugging, and
`wasm-aot-result-metadata` a plist that includes the format tag, the SHA-256
digest and whether deterministic mode was used.

### `wasm-tool-available-p`

```lisp
(cl-cc/codegen:wasm-tool-available-p program)
  => boolean
```

Returns true when `program` is found on `PATH`. Used to decide whether the
optional Wasm toolchain steps can run.

**Signals**: `none`

**Example**:

```lisp
(cl-cc/codegen:wasm-tool-available-p "wasm-opt")
;; => T when wasm-opt is installed, NIL otherwise
```

### `wasm-run-tool-to-string`

```lisp
(cl-cc/codegen:wasm-run-tool-to-string argv &key input-file)
  => string-or-nil
```

Runs an optional Wasm tool and returns its standard output, or `nil` when the
tool is unavailable or fails. Invocation goes through
[cl-process-kit](https://github.com/nerima-lisp/cl-process-kit), so a timeout
escalates SIGTERM to SIGKILL against the child's own process group rather than
merely unwinding the calling Lisp thread.

**Signals**: `none`

### `wasm-file-content-hash`

```lisp
(cl-cc/codegen:wasm-file-content-hash path &key (bits 256))
  => string
```

Returns the hex content digest of the file at `path`.

### `wasm-file-sri-hash`

```lisp
(cl-cc/codegen:wasm-file-sri-hash path &key (bits 384))
  => string
```

Returns a Subresource Integrity token for the file at `path`, in the
`sha384-<base64>` form a browser `integrity` attribute expects.

**Signals**: `none`

## Object Emission

Defined by `cl-cc/emit`. Turns compiler output into the formats other
toolchains consume.

### `vm-program->llvm-ir-module`

```lisp
(cl-cc/emit:vm-program->llvm-ir-module program &key name target-triple data-layout)
  => llvm-ir-module
```

Lowers `program`, a MIR module or MIR function, to a textual LLVM IR module.
`name` defaults to `"clcc_module"`. When `program` is `nil` or a VM program
without MIR, an empty LLVM module is emitted rather than an error. The name is
retained from earlier emit callers, which is why it says `vm-program` while the
input is MIR.

**Signals**: `none`

### `emit-llvm-ir`

```lisp
(cl-cc/emit:emit-llvm-ir thing &key stream name target-triple data-layout)
  => string
```

Emits textual LLVM IR for `thing`, which may be a MIR module, a MIR function,
or an already-built `llvm-ir-module`.

**Returns**: the IR string, additionally written to `stream` when one is given.

**Signals**: `none`

### `llvm-ir-module`

```lisp
(cl-cc/emit:make-llvm-ir-module &key name target-triple data-layout body metadata)
  => llvm-ir-module
```

Textual LLVM IR module. Accessors are `llvm-ir-module-name`,
`llvm-ir-module-target-triple`, `llvm-ir-module-data-layout`,
`llvm-ir-module-body` and `llvm-ir-module-metadata`.

### `llvm-ir-bridge-capabilities`

```lisp
(cl-cc/emit:llvm-ir-bridge-capabilities)
  => list
```

Returns the plist describing what the LLVM lowering covers — the output format,
the accepted input, the MIR constructs it lowers, and the types it maps.

**Signals**: `none`

### `vm-program->mlir-module`

```lisp
(cl-cc/emit:vm-program->mlir-module program &key name)
  => mlir-module
```

Lowers `program`, a MIR module or function, to a textual MLIR module. The
pipeline is MIR to an internal `clcc` dialect to the `func`, `arith` and `cf`
dialects, and the emitted text is valid MLIR suitable for `mlir-opt`.

**Signals**: `none`

### `emit-mlir`

```lisp
(cl-cc/emit:emit-mlir thing &key stream name)
  => string
```

Emits textual MLIR for `thing`, a MIR module or function or an `mlir-module`.

**Returns**: the MLIR string, additionally written to `stream` when one is
given.

**Signals**: `none`

### `mlir-module`

```lisp
(cl-cc/emit:make-mlir-module &key name dialect body metadata)
  => mlir-module
```

Textual MLIR module. Accessors are `mlir-module-name`, `mlir-module-dialect`,
`mlir-module-body` and `mlir-module-metadata`. `dialect` defaults to `"clcc"`.

### `mlir-bridge-capabilities`

```lisp
(cl-cc/emit:mlir-bridge-capabilities)
  => list
```

Returns the plist describing the MLIR lowering: the dialect it defines, the
operations in it, and the conversion pipeline from those operations down to the
standard dialects.

**Signals**: `none`

### `plan-ebpf-program`

```lisp
(cl-cc/emit:plan-ebpf-program program-name instructions &key (hook-point :xdp)
                                                             (maps nil)
                                                             (uses-helpers-p t))
  => ebpf-program-plan
```

Builds an eBPF plan, validating the verifier constraints first.

**Signals**: `simple-error` (via `validate-ebpf-verifier-constraints`)

### `validate-ebpf-verifier-constraints`

```lisp
(cl-cc/emit:validate-ebpf-verifier-constraints instructions)
  => t
```

Checks the subset this backend promises the kernel verifier: an instruction
count under the verifier-friendly cap, no heap allocation or host heap
operations, and a final `BPF_EXIT`.

**Returns**: `t` when every constraint holds.

**Signals**: `simple-error` (instruction count over the cap, a heap operation
present, or the program does not end in `BPF_EXIT`)

### `emit-ebpf-bytecode`

```lisp
(cl-cc/emit:emit-ebpf-bytecode instructions)
  => vector
```

Validates and then encodes `instructions` to an eBPF bytecode vector.

**Signals**: `simple-error` (via `validate-ebpf-verifier-constraints`)

### `emit-ebpf-elf-object`

```lisp
(cl-cc/emit:emit-ebpf-elf-object program-name instructions &key (hook-point :xdp)
                                                                (maps nil)
                                                                (license "GPL"))
  => (simple-array (unsigned-byte 8) (*))
```

Generates a minimal ELF64 relocatable eBPF object loadable by `libbpf` or
`bpftool`. The object carries a program section named after the hook point, a
`license` section, an optional `.maps` section, and the symbol, string and
section-name tables.

Map file-descriptor relocation is deliberately left to libbpf-style loaders.
Direct bytecode can still use `(:ld-map-fd dst fd)` when the descriptor is
known up front.

**Signals**: `simple-error` (via `emit-ebpf-bytecode`)

### `compile-ebpf-program`

```lisp
(cl-cc/emit:compile-ebpf-program program-name instructions &key (hook-point :xdp)
                                                                (maps nil)
                                                                (uses-helpers-p t)
                                                                (emit-elf-p nil))
  => (values plan bytecode)
```

Plans and encodes an eBPF program in one call.

**Returns**: the `ebpf-program-plan` and, by default, the raw bytecode. When
`emit-elf-p` is true the second value is a minimal ELF object instead.

**Signals**: `simple-error` (via `plan-ebpf-program`)

### `ebpf-program-plan`

```lisp
(cl-cc/emit:make-ebpf-program-plan &key program-name hook-point instructions
                                        maps uses-helpers-p verifier-safe-p)
  => ebpf-program-plan
```

A validated eBPF program description. Accessors are
`ebpf-program-plan-program-name`, `ebpf-program-plan-hook-point`,
`ebpf-program-plan-instructions`, `ebpf-program-plan-maps`,
`ebpf-program-plan-uses-helpers-p` and `ebpf-program-plan-verifier-safe-p`.

### `ebpf-map-def`

```lisp
(cl-cc/emit:make-ebpf-map-def &key name type key-size value-size max-entries flags fd)
  => ebpf-map-def
```

One BPF map definition.

| Accessor | Type | Default |
|---|---|---|
| `ebpf-map-def-name` | `string` | `"map"` |
| `ebpf-map-def-type` | `integer` | `+bpf-map-type-array+` |
| `ebpf-map-def-key-size` | `integer` | `4` |
| `ebpf-map-def-value-size` | `integer` | `8` |
| `ebpf-map-def-max-entries` | `integer` | `1` |
| `ebpf-map-def-flags` | `integer` | `0` |
| `ebpf-map-def-fd` | `integer` | `0` |

`cl-cc/emit:+bpf-map-type-array+` and `cl-cc/emit:+bpf-map-type-hash+` are the
map type constants; `cl-cc/emit:+bpf-helper-map-lookup-elem+` and
`cl-cc/emit:+bpf-helper-map-update-elem+` are the helper identifiers.

### `source-map-encode-vlq`

```lisp
(cl-cc/emit:source-map-encode-vlq value)
  => string
```

Encodes an integer with Source Map base64 VLQ encoding.

**Signals**: `none`

**Example**:

```lisp
(cl-cc/emit:source-map-encode-vlq 0)   ; => "A"
(cl-cc/emit:source-map-encode-vlq -1)  ; => "D"
(cl-cc/emit:source-map-encode-vlq 16)  ; => "gB"
```

### `build-wasm-source-map-v3`

```lisp
(cl-cc/emit:build-wasm-source-map-v3 entries &key file (source-root ""))
  => string
```

Builds a Source Map v3 JSON document for Wasm `entries`. Each entry is a plist
carrying `:offset`, `:source`, `:line` and `:column`.

**Signals**: `none`

### `write-wasm-source-map`

```lisp
(cl-cc/emit:write-wasm-source-map result map-path &key wasm-file source-file (source-root ""))
  => pathname
```

Writes the Source Map v3 JSON for `result` to `map-path`, creating any missing
directories, and returns `map-path`.

**Signals**: `none`

### `write-wasm-with-source-map`

```lisp
(cl-cc/emit:write-wasm-with-source-map result wasm-path &key source-file)
  => (values wasm-path map-path)
```

Writes the assembly in `result` to `wasm-path` and its Source Map v3 sidecar
alongside it.

**Returns**: both paths.

**Signals**: `none`

### `make-riscv64-assembler`

```lisp
(cl-cc/emit:make-riscv64-assembler &key target)
  => riscv64-assembler
```

Creates RV64GC assembler state. `target` defaults to
`(cl-cc/target:find-target :riscv64)`.

**Signals**: `none`

### `riscv64-emit-instruction`

```lisp
(cl-cc/emit:riscv64-emit-instruction asm inst)
```

Dispatches one symbolic instruction into `asm`. Instructions are lists whose
head is the mnemonic, for example `(:add :a0 :a1 :a2)`, `(:ld :a0 :sp 8)`,
`(:sd :ra :sp 0)`, `(:jal :ra 16)`, `(:ret)`, `(:c.addi :sp -16)` and
`(:fadd.d :fa0 :fa1 :fa2)`.

**Signals**: `simple-error` (`inst` is not a cons, or the mnemonic is not
supported)

### `riscv64-emit-function`

```lisp
(cl-cc/emit:riscv64-emit-function name instructions &key (save-regs nil)
                                                         (stack-size 0)
                                                         (save-ra t))
  => vector
```

Emits a complete function — prologue, body, epilogue — and returns its bytes.
`name` is accepted for symbol-table integration and is not used yet.

**Signals**: `simple-error` (via `riscv64-emit-instruction`)

### `riscv64-emit-prologue`

```lisp
(cl-cc/emit:riscv64-emit-prologue asm &key (save-regs nil) (stack-size 0) (save-ra t))
```

Emits the frame setup: allocate `stack-size` bytes, save the return address
when `save-ra` is true, and save each register in `save-regs`.
`cl-cc/emit:riscv64-emit-epilogue` takes the same arguments and reverses it.

### `riscv64-emit-bytes`

```lisp
(cl-cc/emit:riscv64-emit-bytes asm)
  => vector
```

Returns the bytes assembled into `asm` so far.

### `riscv64-emit-load-immediate`

```lisp
(cl-cc/emit:riscv64-emit-load-immediate asm rd value)
```

Emits the shortest instruction sequence that materialises `value` in register
`rd`.

### `riscv64-emit-pic-call`

```lisp
(cl-cc/emit:riscv64-emit-pic-call asm rd symbol-offset &key (scratch :t0))
```

Emits a position-independent call to `symbol-offset` through `rd`, using
`scratch` as the temporary register.
