;;;; cl-cc-codegen-native.asd — native code generation for cl-cc
;;;;
;;;; Extracted from the cl-cc monorepo. Three systems that only make sense
;;;; together: register allocation, instruction selection and encoding, and
;;;; object emission. The design document names this bundle as one repository
;;;; rather than three, because the boundaries between them move -- a new
;;;; addressing mode touches the encoder and the allocator's cost model at once
;;;; -- while the boundary around them does not.
;;;;
;;;; mir, target and binary are named in the same design as part of this bundle.
;;;; They are separate repositories instead, because each turned out to be a
;;;; dependency-free leaf that other things also use; nothing here needs them
;;;; vendored.
;;;;
;;;; This file defines no components of its own. It exists so the repository has
;;;; a system named after it, and so `asdf:load-system "cl-cc-codegen-native"`
;;;; pulls the whole native backend.

;;; This form comes first, before any defsystem. ASDF binds *package* to
;;; ASDF-USER only for a file it loads itself; read any other way -- a REPL
;;; `load`, an editor evaluating the buffer, flake.nix parsing :version -- the
;;; file is read in whatever package happens to be current. Saying it makes the
;;; file self-contained.
(in-package #:asdf-user)

(asdf:defsystem "cl-cc-codegen-native"
  :description "Native code generation for the cl-cc Common Lisp compiler: register allocation, instruction selection, encoding and object emission"
  :author "takeokunn <bararararatty@gmail.com>"
  :maintainer "takeokunn <bararararatty@gmail.com>"
  :license "MIT"
  :version "0.2.1"
  :homepage "https://github.com/nerima-lisp/cl-cc-codegen-native"
  :bug-tracker "https://github.com/nerima-lisp/cl-cc-codegen-native/issues"
  :source-control (:git "https://github.com/nerima-lisp/cl-cc-codegen-native.git")
  :depends-on ("cl-cc-regalloc" "cl-cc-codegen" "cl-cc-emit")
  :components ()
  :in-order-to ((asdf:test-op (asdf:test-op "cl-cc-codegen-native/test"))))

(asdf:defsystem "cl-cc-codegen-native/test"
  :description "Module boundary tests for cl-cc-codegen-native"
  :author "takeokunn <bararararatty@gmail.com>"
  :license "MIT"
  :depends-on ("cl-cc-codegen-native" "cl-weave")
  :pathname "t"
  :serial t
  :components ((:file "package")
 (:module "targets" :serial t
  :components ((:module "x86-64" :serial t
                :components ((:file "package")
                             (:file "x86-64-codegen-emitter-tests")
                             (:file "x86-64-codegen-insn-tests")
                             (:file "x86-64-codegen-tests")
                             (:file "x86-64-emit-logical-tests")
                             (:file "x86-64-emit-ops-tests")
                             (:file "x86-64-sequences-tests")))
               (:module "aarch64" :serial t
                :components ((:file "package")
                             (:file "aarch64-encoding-tests")))
               (:module "riscv64" :serial t
                :components ((:file "package")))
               (:module "wasm" :serial t
                :components ((:file "package")
                             (:file "wasm-binary-tests")
                             (:file "wasm-extract-tests")
                             (:file "wasm-features-tests")
                             (:file "wasm-ir-tests")
                             (:file "wasm-opcodes-tests")
                             (:file "wasm-tests")
                             (:file "wasm-trampoline-build-tests")
                             (:file "wasm-trampoline-tests")
                             (:file "wasm-types-tests")))
               (:module "ppc64" :serial t
                :components ((:file "package")
                             (:file "ppc64-codegen-tests")))))
 (:module "lowering" :serial t
  :components ((:file "package")
               (:file "mir-isel-tests")
               (:file "regalloc-isel-tests")))
 (:module "scheduling" :serial t
  :components ((:file "package")))
 (:module "hardening" :serial t
  :components ((:file "package")))
 (:module "sanitizer" :serial t
  :components ((:file "package")))
 (:module "emit" :serial t
  :components ((:module "llvm" :serial t
                :components ((:file "package")
                             (:file "llvm-ir-tests")))
               (:module "mlir" :serial t
                :components ((:file "package")
                             (:file "mlir-tests")))
               (:module "ebpf" :serial t
                :components ((:file "package")
                             (:file "ebpf-tests")))
               (:module "wasi" :serial t
                :components ((:file "package")))))
 (:module "regalloc" :serial t
  :components ((:file "package")
               (:file "regalloc-color-tests")
               (:file "regalloc-lsa-tests")
               (:file "regalloc-spill-tests")
               (:file "regalloc-tests")))
 (:file "mir-tests")
 (:file "mir-target-tests")
 (:file "target-tests")
 (:file "native-advanced-bridge-tests")
 (:file "codegen-native-export-surface-test")
 (:file "codegen-native-boundary-test")
 (:file "wasm-binary-golden-test")
 (:module "integration" :serial t :components ((:file "security-hardening-tests") (:file "regalloc-scheduling-tests") (:file "aarch64-codegen-tests") (:file "aarch64-emit-tests") (:file "riscv64-tests") (:file "x86-64-emit-tests") (:file "x86-64-encoding-size-tests") (:file "x86-64-encoding-tests") (:file "x86-64-regs-tests") (:file "x86-64-vm-emitter-tests"))))
  :perform (asdf:test-op (op system)
             (declare (ignore op system))
             ;; RUN-ALL, not RUN-ALL-TESTS: the cl-weave that reaches this
             ;; repository through its transitive inputs is the older API.
             ;;
             ;; Not HOST-KIT:SYMBOL-CALL: a .asd is read before :depends-on
             ;; is ever consulted, so a CL-HOST-KIT-prefixed token here would
             ;; be a read-time PACKAGE-DOES-NOT-EXIST error regardless of
             ;; what the system depends on. FIND-SYMBOL/FIND-PACKAGE/FUNCALL
             ;; are CL, always present.
             (unless (funcall (find-symbol "RUN-ALL" (find-package "CL-WEAVE")) :reporter :spec :pass-with-no-tests nil)
               (error "cl-cc-codegen-native test suite failed."))))
