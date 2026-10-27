;;;; cl-cc-codegen.asd — per-target code generation
;;;;
;;;; Instruction selection, encoding and emission for x86-64, AArch64,
;;;; RISC-V and WebAssembly. The isel/ rules and the per-target *-codegen
;;;; files are kept together with the encoders because a target's addressing
;;;; modes, its instruction-selection rules and its encoder tables change in
;;;; the same commit far more often than any of them changes alone.

(asdf:defsystem :cl-cc-codegen
  :description "Per-target code generation: x86-64, AArch64, RISC-V, WASM backends"
  :author "takeokunn"
  :license "MIT"
  :homepage "https://github.com/nerima-lisp/cl-cc"
  :version "0.1.0"
  :depends-on (:cl-cc-bootstrap :cl-cc-vm :cl-cc-mir :cl-cc-target
               :cl-cc-binary
               :cl-cc-optimize :cl-cc-regalloc :cl-process-kit :cl-host-kit)
  :pathname "src"
  :serial t
  :components
  ((:module "lowering"
            :pathname "../../src/lowering"
            :serial t
            :components ((:file "package") (:file "calling-convention")
                         (:file "native-atomics")
                         (:file "native-consts")
                         (:file "native-target")
                         (:file "native-stack")
                         (:file "native-peephole")
                         (:file "stack-maps")
                         (:file "isel-core")
                         (:file "regalloc-advanced")))
           (:module "scheduling"
            :pathname "../../src/scheduling"
            :serial t
            :components ((:file "package")
                         (:file "native-common")
                         (:file "x86-64-macro-fusion")
                         (:file "post-ra-scheduler")))
           (:module "sanitizer"
            :pathname "../../src/sanitizer"
            :serial t
            :components ((:file "package")
                         (:file "sanitizer")))
           (:module "hardening"
            :pathname "../../src/hardening"
            :serial t
            :components ((:file "package")
                         (:file "win-cfg")))
           (:module "x86-64"
            :pathname "../../src/targets/x86-64"
            :serial t
            :components ((:file "package")
                         (:file "x86-64")
                         (:file "x86-64-encoding")
                         (:file "x86-64-encoding-instrs")
                         (:file "x86-64-encoding-instrs-xmm")
                         (:file "x86-64-sequences")
                         (:file "x86-64-regs")
                         (:file "x86-64-emit-ops")
                         (:file "x86-64-emit-ops-bits")
                         (:file "x86-64-emit-ops-logical")
                         (:file "x86-64-codegen-size-table")
                         (:file "x86-64-codegen-data")
                         (:file "x86-64-codegen-core")
                         (:file "x86-64-codegen-emitters")
                         (:file "x86-64-lea-peephole")
                         (:file "atomics")
                         (:file "x86-64-eh")
                         (:file "x86-64-peephole")
                         (:file "isel/x86-64-rules")
                         (:file "sanitizer")
                         (:file "win-cfg-emission")
                         (:file "x86-64-codegen-dispatch")))
           (:module "aarch64"
            :pathname "../../src/targets/aarch64"
            :serial t
            :components ((:file "package")
                         (:file "a64-shrink-wrap-data")
                         (:file "aarch64")
                         (:file "aarch64-codegen")
                         (:file "aarch64-codegen-labels")
                         (:file "aarch64-emitters")
                         (:file "aarch64-peephole")
                         (:file "aarch64-atomics")
                         (:file "aarch64-program")
                         (:file "isel/aarch64-rules")))
           (:module "riscv64"
            :pathname "../../src/targets/riscv64"
            :serial t
            :components ((:file "package")
                         (:file "riscv64")
                         (:file "riscv64-codegen")))
           (:module "wasm"
            :pathname "../../src/targets/wasm"
            :serial t
            :components ((:file "package")
                         (:file "wasm-type-constants")
                         (:file "wasm-types")
                         (:file "wasm-ir")
                         (:file "wasm-extract")
                         (:file "wasm-features")
                         (:file "wasm-string-builtins")
                         (:file "wasm-trampoline")
                         (:file "wasm-trampoline-gc")
                         (:file "wasm-trampoline-fixnum")
                         (:file "wasm-trampoline-proposals")
                         (:file "wasm-trampoline-tables")
                         (:file "wasm-trampoline-emit")
                         (:file "wasm-trampoline-build")
                         (:file "wasm")
                         (:file "wasm-sections")
                         (:file "wasm-functions")
                         (:file "wasm-imports")
                         (:file "wasm-feature-params")
                         (:file "wasm-binary")
                         (:file "wasm-binary-debug")
                         (:file "wasm-output")
                         (:file "wasm-simd")
                         (:file "wasm-emit-data")
                         (:file "wasm-emit-sections")
                         (:file "wasm-threads")
                         (:file "wasm-threads-integration")
                         (:file "wasm-emit-instrs-atomic")
                         (:file "wasm-emit-instrs")
                         (:module "infra"
                          :pathname "infra"
                          :serial t
                          :components ((:file "wasm-aot")
                                       (:file "wasm-source-map")))))
           (:module "ppc64"
            :pathname "../../src/targets/ppc64"
            :serial t
            :components ((:file "package")
                         (:file "ppc64-codegen")))
           (:file "package")))
