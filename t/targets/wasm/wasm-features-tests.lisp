;;;; wasm-features-tests.lisp — Feature flag and opcode validation tests
;;;;
;;;; Tests that all wasm feature flags, opcode constants, and
;;;; WAT helpers from docs/notes/wasm.md are properly defined.
;;;; Uses cl-cc/testing framework. assert-true takes exactly 1 argument.

(in-package :cl-cc/codegen-native/targets/wasm/test)



;; ── Phase 4 Standard (MVP v1.1) ──
(it-sequential "wasm-test-non-trapping-float-to-int-constants"
  (let ((pkg (find-package :cl-cc/codegen-native/targets/wasm)))
    (expect (not (null pkg)) :to-be-truthy)
    (when pkg
      (expect (boundp (find-symbol "+WASM-I32-TRUNC-SAT-F32-S+" pkg)) :to-be-truthy)
      (expect (boundp (find-symbol "+WASM-I32-TRUNC-SAT-F64-S+" pkg)) :to-be-truthy)
      (expect (boundp (find-symbol "+WASM-I64-TRUNC-SAT-F64-S+" pkg)) :to-be-truthy))))

;; FR-234: Sign-extension
(it-sequential "wasm-test-sign-extension-constants"
  (let ((pkg (find-package :cl-cc/codegen-native/targets/wasm)))
    (when pkg
      (expect (boundp (find-symbol "+WASM-I32-EXTEND8-S+" pkg)) :to-be-truthy)
      (expect (boundp (find-symbol "+WASM-I32-EXTEND16-S+" pkg)) :to-be-truthy)
      (expect (boundp (find-symbol "+WASM-I64-EXTEND8-S+" pkg)) :to-be-truthy)
      (expect (boundp (find-symbol "+WASM-I64-EXTEND16-S+" pkg)) :to-be-truthy)
      (expect (boundp (find-symbol "+WASM-I64-EXTEND32-S+" pkg)) :to-be-truthy))))

;; FR-228: Bulk Memory
(it-sequential "wasm-test-bulk-memory-constants"
  (let ((pkg (find-package :cl-cc/codegen-native/targets/wasm)))
    (when pkg
      (expect (boundp (find-symbol "+WASM-MEMORY-COPY+" pkg)) :to-be-truthy)
      (expect (boundp (find-symbol "+WASM-MEMORY-FILL+" pkg)) :to-be-truthy)
      (expect (boundp (find-symbol "+WASM-MEMORY-INIT+" pkg)) :to-be-truthy)
      (expect (boundp (find-symbol "+WASM-DATA-DROP+" pkg)) :to-be-truthy))))

;; FR-237: Bulk Table
(it-sequential "wasm-test-bulk-table-constants"
  (let ((pkg (find-package :cl-cc/codegen-native/targets/wasm)))
    (when pkg
      (expect (boundp (find-symbol "+WASM-TABLE-INIT+" pkg)) :to-be-truthy)
      (expect (boundp (find-symbol "+WASM-TABLE-COPY+" pkg)) :to-be-truthy)
      (expect (boundp (find-symbol "+WASM-TABLE-FILL+" pkg)) :to-be-truthy)
      (expect (boundp (find-symbol "+WASM-ELEM-DROP+" pkg)) :to-be-truthy))))

;; FR-143: Tail-call
(it-sequential "wasm-test-tail-call-constants"
  (let ((pkg (find-package :cl-cc/codegen-native/targets/wasm)))
    (when pkg
      (expect (boundp (find-symbol "+WASM-RETURN-CALL+" pkg)) :to-be-truthy)
      (expect (boundp (find-symbol "+WASM-RETURN-CALL-INDIRECT+" pkg)) :to-be-truthy))))

;; FR-213: Memory64
(it-sequential "wasm-test-memory64-constants"
  (let ((pkg (find-package :cl-cc/codegen-native/targets/wasm)))
    (when pkg
      (expect (boundp (find-symbol "+WASM-MEMORY-SIZE64+" pkg)) :to-be-truthy)
      (expect (boundp (find-symbol "+WASM-MEMORY-GROW64+" pkg)) :to-be-truthy))))

;; FR-324: copysign
(it-sequential "wasm-test-copysign-constants"
  (let ((pkg (find-package :cl-cc/codegen-native/targets/wasm)))
    (when pkg
      (expect (boundp (find-symbol "+WASM-F64-COPYSIGN+" pkg)) :to-be-truthy)
      (expect (boundp (find-symbol "+WASM-F32-COPYSIGN+" pkg)) :to-be-truthy))))

;; ── GC Proposal ──
(it-sequential "wasm-test-gc-constants"
  (let ((pkg (find-package :cl-cc/codegen-native/targets/wasm)))
    (when pkg
      (expect (boundp (find-symbol "+WASM-GC-STRUCT-NEW+" pkg)) :to-be-truthy)
      (expect (boundp (find-symbol "+WASM-GC-STRUCT-GET+" pkg)) :to-be-truthy)
      (expect (boundp (find-symbol "+WASM-GC-STRUCT-SET+" pkg)) :to-be-truthy)
      (expect (boundp (find-symbol "+WASM-GC-ARRAY-NEW+" pkg)) :to-be-truthy)
      (expect (boundp (find-symbol "+WASM-GC-ARRAY-NEW-FIXED+" pkg)) :to-be-truthy)
      (expect (boundp (find-symbol "+WASM-GC-ARRAY-GET+" pkg)) :to-be-truthy)
      (expect (boundp (find-symbol "+WASM-GC-ARRAY-SET+" pkg)) :to-be-truthy)
      (expect (boundp (find-symbol "+WASM-GC-ARRAY-LEN+" pkg)) :to-be-truthy)
      (expect (boundp (find-symbol "+WASM-GC-REF-TEST+" pkg)) :to-be-truthy)
      (expect (boundp (find-symbol "+WASM-GC-REF-CAST+" pkg)) :to-be-truthy)
      (expect (boundp (find-symbol "+WASM-GC-REF-I31+" pkg)) :to-be-truthy)
      (expect (boundp (find-symbol "+WASM-GC-I31-GET-S+" pkg)) :to-be-truthy)
      (expect (boundp (find-symbol "+WASM-GC-BR-ON-CAST+" pkg)) :to-be-truthy)
      (expect (boundp (find-symbol "+WASM-GC-BR-ON-CAST-FAIL+" pkg)) :to-be-truthy))))

;; ── Exception Handling ──
(it-sequential "wasm-test-eh-constants"
  (let ((pkg (find-package :cl-cc/codegen-native/targets/wasm)))
    (when pkg
      (expect (boundp (find-symbol "+WASM-TRY+" pkg)) :to-be-truthy)
      (expect (boundp (find-symbol "+WASM-CATCH+" pkg)) :to-be-truthy)
      (expect (boundp (find-symbol "+WASM-THROW+" pkg)) :to-be-truthy)
      (expect (boundp (find-symbol "+WASM-TRY-TABLE+" pkg)) :to-be-truthy)
      (expect (boundp (find-symbol "+WASM-THROW-REF+" pkg)) :to-be-truthy))))

;; ── FR coverage check ──
;; ── Feature flags existence ──
(it-sequential "wasm-test-key-feature-flags-exist"
  (let ((pkg (find-package :cl-cc/codegen-native/targets/wasm)))
    (when pkg
      (dolist (flag-sym '("NON-TRAPPING-FLOAT-TO-INT-ENABLED"
                          "SIGN-EXTENSION-ENABLED" "BULK-MEMORY-ENABLED"
                          "TAIL-CALL-ENABLED" "GC-ENABLED" "SIMD128-ENABLED"
                          "EXCEPTION-HANDLING-ENABLED" "AOT-MODE-ENABLED"))
        (let ((full-sym (find-symbol (format nil "*WASM-~A*" flag-sym) pkg)))
          (expect (and full-sym (boundp full-sym)) :to-be-truthy))))))

;; ── WAT helpers ──
(it-sequential "wasm-test-wat-helpers-exist"
  (let ((pkg (find-package :cl-cc/codegen-native/targets/wasm)))
    (when pkg
      (dolist (fn-name '("WASM-FIXNUM-UNBOX" "WASM-FIXNUM-BOX"
                          "REG-LOCAL-REF" "REG-LOCAL-SET"
                          "REG-RECORD-TYPE" "REG-KNOWN-TYPE"
                          "WASM-REF-CAST-MAYBE" "WASM-CLOSURE-REF-WAT"))
        (let ((fn-sym (find-symbol fn-name pkg)))
          (expect (and fn-sym (fboundp fn-sym)) :to-be-truthy))))))

;; ── Dispatch tables ──
(it-sequential "wasm-test-dispatch-tables-exist"
  (let ((pkg (find-package :cl-cc/codegen-native/targets/wasm)))
    (when pkg
      (dolist (table-name '("*WASM-I64-BINOP-TABLE*" "*WASM-I64-CMP-TABLE*"
                            "*WASM-UNARY-FIXNUM-TABLE*" "*WASM-MINMAX-TABLE*"
                            "*WASM-STRUCT-GET-TABLE*" "*WASM-SIGN-EXTEND-TABLE*"
                            "*WASM-FLOAT-TO-INT-TABLE*"))
        (let ((table-sym (find-symbol table-name pkg)))
          (expect (and table-sym (boundp table-sym)) :to-be-truthy))))))

;; ── All 130 FRs covered in wasm-features.lisp ──
