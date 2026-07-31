;;;; cl-cc-emit.asd — object emission beyond the core native/WASM encoders
;;;;
;;;; Alternate and auxiliary emission targets that sit on top of
;;;; cl-cc-codegen rather than inside it: LLVM IR and MLIR text emission,
;;;; eBPF object emission, WASM extensions (threads, WASI, source maps, the
;;;; PC-dispatch trampoline), and BURS instruction selection consumed by the
;;;; cl-cc monorepo's own test suite rather than by anything in this repo.

(asdf:defsystem :cl-cc-emit
  :description "Alternate/auxiliary emission targets: LLVM IR, MLIR, eBPF, WASM extensions"
  :author "takeokunn"
  :license "MIT"
  :homepage "https://github.com/nerima-lisp/cl-cc"
  :version "0.1.0"
  :depends-on (:cl-cc-vm :cl-cc-ast :cl-cc-mir :cl-cc-optimize :cl-cc-codegen)
  :pathname "src"
  :serial t
  :components
  ((:file "package")
   (:file "wasm-types")
   (:file "wasm")
   (:file "wasm-trampoline")
   (:file "llvm-ir")
   (:file "mlir")
   (:file "wasm-source-map")
   (:file "wasm-wasi")
   (:file "ebpf")
   (:file "wasm-threads")
   (:file "regalloc-advanced")
   (:file "riscv64")))
