;;;; tests/wasm-tests.lisp - WebAssembly Backend Tests
;;;
;;; This module provides basic tests for the WASM/WAT code generation backend,
;;; including:
;;; - Module header presence
;;; - Predefined GC type section (cons, closure, etc.)
;;; - Function definition emission
;;; - Nil constant representation
;;; - compile-string :target :wasm integration

(in-package :cl-cc/codegen-native/targets/wasm/test)
;;; ──────────────────────────────────────────────────────────────────────────
;;; Helper: compile a source string to WAT, returning the assembly string.
;;; Compilation errors propagate to the test runner. Tests that expect them use
;;; %capture-wasm-error-message to assert the condition text.
;;; ──────────────────────────────────────────────────────────────────────────

(defun %direct-wasm-emit (inst)
  "Emit INST through the non-trampoline wasm target methods directly." 
  (let ((s (make-string-output-stream))
        (target (make-instance 'cl-cc/codegen-native/targets/wasm:wasm-target
                               :reg-map (cl-cc/codegen-native/targets/wasm::make-wasm-reg-map-for-function 0))))
    (cl-cc/codegen-native/targets/wasm::emit-instruction target inst s)
    (get-output-stream-string s)))

(defun %direct-wasm-emit* (instructions)
  "Emit a sequence of INSTRUCTIONS through wasm target methods directly." 
  (let ((s (make-string-output-stream))
        (target (make-instance 'cl-cc/codegen-native/targets/wasm:wasm-target
                               :reg-map (cl-cc/codegen-native/targets/wasm::make-wasm-reg-map-for-function 0))))
    (dolist (inst instructions)
      (cl-cc/codegen-native/targets/wasm::emit-instruction target inst s))
    (get-output-stream-string s)))
(defun %capture-wasm-error-message (thunk)
  (handler-case
      (funcall thunk)
    (error (condition)
      (princ-to-string condition))))

;;; ──────────────────────────────────────────────────────────────────────────
;;; Section 1-2: Module structure — always present in any WAT output
;;; ──────────────────────────────────────────────────────────────────────────

;;; ──────────────────────────────────────────────────────────────────────────
;;; Section 3: Function emission
;;; ──────────────────────────────────────────────────────────────────────────

;;; ──────────────────────────────────────────────────────────────────────────
;;; Section 4: Nil constant representation
;;; ──────────────────────────────────────────────────────────────────────────

;;; ──────────────────────────────────────────────────────────────────────────
;;; Section 5: compile-string integration
;;; ──────────────────────────────────────────────────────────────────────────

;;; ──────────────────────────────────────────────────────────────────────────
;;; Section 7: Arithmetic instruction coverage
;;; ──────────────────────────────────────────────────────────────────────────
;;; defun prevents the optimizer from constant-folding the args away.

;;; ──────────────────────────────────────────────────────────────────────────
;;; Section 8: Global variable access
;;; ──────────────────────────────────────────────────────────────────────────

;;; ──────────────────────────────────────────────────────────────────────────
;;; Section 9: Closure creation and function call dispatch
;;; ──────────────────────────────────────────────────────────────────────────

(it-sequential "wasm-tail-call-dispatch-uses-return-call-indirect"
  (let ((out (%direct-wasm-emit
              (cl-cc/vm:make-vm-tail-call :dst :r0 :func :r1 :args (list :r2)))))
    (let* ((assert-output out) (assert-substring "return_call_indirect")) (expect (and (stringp assert-output) (search assert-substring assert-output)) :to-be-truthy))
    (let* ((assert-output out) (assert-substring "$main_func_t")) (expect (and (stringp assert-output) (search assert-substring assert-output)) :to-be-truthy))
    (let* ((assert-output out) (assert-substring "(global.set $cl_arg0")) (expect (and (stringp assert-output) (search assert-substring assert-output)) :to-be-truthy))))

(it-sequential "wasm-tail-call-dispatch-requires-feature"
  (let ((cl-cc/codegen-native/targets/wasm::*wasm-tail-call-enabled* nil))
    (signals error (%direct-wasm-emit
       (cl-cc/vm:make-vm-tail-call :dst :r0 :func :r1 :args (list :r2))))))

(it-sequential "wasm-tail-call-direct-path-uses-return-call-when-callee-known"
  (let* ((module (cl-cc/codegen-native/targets/wasm::make-empty-wasm-module))
         (callee (cl-cc/codegen-native/targets/wasm::make-wasm-function-def
                  :index 0
                  :wat-name "$known_fn"))
         (stream (make-string-output-stream))
         (target (make-instance 'cl-cc/codegen-native/targets/wasm:wasm-target
                                :module module
                                :reg-map (cl-cc/codegen-native/targets/wasm::make-wasm-reg-map-for-function 0))))
    (cl-cc/codegen-native/targets/wasm::wasm-module-add-function module callee)
    (let ((cl-cc/codegen-native/targets/wasm::*wasm-tail-call-enabled* t))
      (dolist (inst (list
                     (cl-cc/vm:make-vm-func-ref :dst :r1 :label "known_fn")
                     (cl-cc/vm:make-vm-tail-call :dst :r0 :func :r1 :args (list :r2))))
        (cl-cc/codegen-native/targets/wasm::emit-instruction target inst stream)))
    (let ((out (get-output-stream-string stream)))
      (let* ((assert-output out) (assert-substring "(return_call $known_fn)")) (expect (and (stringp assert-output) (search assert-substring assert-output)) :to-be-truthy))
      (expect (search "return_call_indirect" out :test #'char=) :to-be-falsy))))

(it-sequential "wasm-tail-call-direct-path-requires-feature"
  (let ((cl-cc/codegen-native/targets/wasm::*wasm-tail-call-enabled* nil))
    (signals error (%direct-wasm-emit*
       (list (cl-cc/vm:make-vm-func-ref :dst :r1 :label "known_fn")
             (cl-cc/vm:make-vm-tail-call :dst :r0 :func :r1 :args (list :r2)))))))

(it-sequential "wasm-direct-bitcount-and-arith-emitters logcount"
  (destructuring-bind (expected-op inst) (list "i64.popcnt" (cl-cc/vm:make-vm-logcount :dst :r0 :src :r1))
    (let* ((assert-output (%direct-wasm-emit inst)) (assert-substring expected-op)) (expect (and (stringp assert-output) (search assert-substring assert-output)) :to-be-truthy))))

(it-sequential "wasm-direct-bitcount-and-arith-emitters integer-length"
  (destructuring-bind (expected-op inst) (list "i64.clz" (cl-cc/vm:make-vm-integer-length :dst :r0 :src :r1))
    (let* ((assert-output (%direct-wasm-emit inst)) (assert-substring expected-op)) (expect (and (stringp assert-output) (search assert-substring assert-output)) :to-be-truthy))))

(it-sequential "wasm-direct-bitcount-and-arith-emitters integer-add"
  (destructuring-bind (expected-op inst) (list "i64.add" (cl-cc/vm:make-vm-integer-add :dst :r0 :lhs :r1 :rhs :r2))
    (let* ((assert-output (%direct-wasm-emit inst)) (assert-substring expected-op)) (expect (and (stringp assert-output) (search assert-substring assert-output)) :to-be-truthy))))

(it-sequential "wasm-direct-bitcount-and-arith-emitters integer-sub"
  (destructuring-bind (expected-op inst) (list "i64.sub" (cl-cc/vm:make-vm-integer-sub :dst :r0 :lhs :r1 :rhs :r2))
    (let* ((assert-output (%direct-wasm-emit inst)) (assert-substring expected-op)) (expect (and (stringp assert-output) (search assert-substring assert-output)) :to-be-truthy))))

(it-sequential "wasm-direct-bitcount-and-arith-emitters integer-mul"
  (destructuring-bind (expected-op inst) (list "i64.mul" (cl-cc/vm:make-vm-integer-mul :dst :r0 :lhs :r1 :rhs :r2))
    (let* ((assert-output (%direct-wasm-emit inst)) (assert-substring expected-op)) (expect (and (stringp assert-output) (search assert-substring assert-output)) :to-be-truthy))))

(it-sequential "wasm-gc-array-new-get-set-emitters"
  (let ((mk (%direct-wasm-emit
             (cl-cc/vm:make-vm-make-array :dst :r0 :size-reg :r1 :initial-element nil)))
        (get (%direct-wasm-emit
              (cl-cc/vm:make-vm-aref :dst :r0 :array-reg :r1 :index-reg :r2)))
        (set (%direct-wasm-emit
              (cl-cc/vm:make-vm-aset :array-reg :r0 :index-reg :r1 :val-reg :r2))))
    (let* ((assert-output mk) (assert-substring "array.new $eqref_array_t")) (expect (and (stringp assert-output) (search assert-substring assert-output)) :to-be-truthy))
    (let* ((assert-output get) (assert-substring "array.get $eqref_array_t")) (expect (and (stringp assert-output) (search assert-substring assert-output)) :to-be-truthy))
    (let* ((assert-output set) (assert-substring "array.set $eqref_array_t")) (expect (and (stringp assert-output) (search assert-substring assert-output)) :to-be-truthy))))

(it-sequential "wasm-relaxed-simd-byte-encoding-wat-level-fixture"
  (let* ((bytes (coerce (cl-cc/codegen-native/targets/wasm::wasm-encode-simd-op
                         cl-cc/codegen-native/targets/wasm::+wasm-f32x4-relaxed-madd+)
                        'list))
         (fixture "(module (func (param v128 v128 v128) (result v128) f32x4.relaxed_madd))"))
    (expect bytes :to-equal '(#xfd #x85 #x01))
    (expect (search "f32x4.relaxed_madd" fixture :test #'char=) :to-be-truthy)))

(it-sequential "wasm-gc-array-bce-metadata-emits-elision-marker"
  (let ((get-inst (cl-cc/vm:make-vm-aref :dst :r0 :array-reg :r1 :index-reg :r2))
        (set-inst (cl-cc/vm:make-vm-aset :array-reg :r0 :index-reg :r1 :val-reg :r2)))
    (cl-cc/optimize:opt-mark-bounds-check-eliminable get-inst)
    (cl-cc/optimize:opt-mark-bounds-check-eliminable set-inst)
    (let ((get (%direct-wasm-emit get-inst))
          (set (%direct-wasm-emit set-inst)))
      (let* ((assert-output get) (assert-substring "BCE: explicit bounds check eliminated")) (expect (and (stringp assert-output) (search assert-substring assert-output)) :to-be-truthy))
      (let* ((assert-output get) (assert-substring "array.get $eqref_array_t")) (expect (and (stringp assert-output) (search assert-substring assert-output)) :to-be-truthy))
      (let* ((assert-output set) (assert-substring "BCE: explicit bounds check eliminated")) (expect (and (stringp assert-output) (search assert-substring assert-output)) :to-be-truthy))
      (let* ((assert-output set) (assert-substring "array.set $eqref_array_t")) (expect (and (stringp assert-output) (search assert-substring assert-output)) :to-be-truthy)))))

;; Positive GC class-layout and object-allocation coverage is tracked in cl-cc-codegen-native Issue #19.
(it-sequential "wasm-gc-slot-read-without-class-layout"
  (let* ((inst (cl-cc/vm:make-vm-slot-read :dst :r0 :obj-reg :r1 :slot-name :foo))
         (message (%capture-wasm-error-message (lambda () (%direct-wasm-emit inst)))))
    (expect message :to-equal
            "Unsupported WASM instruction: VM-SLOT-READ has no slot index for :FOO")))

(it-sequential "wasm-gc-slot-write-without-class-layout"
  (let* ((inst (cl-cc/vm:make-vm-slot-write :obj-reg :r1 :slot-name :foo :value-reg :r2))
         (message (%capture-wasm-error-message (lambda () (%direct-wasm-emit inst)))))
    (expect message :to-equal
            "Unsupported WASM instruction: VM-SLOT-WRITE has no slot index for :FOO")))

(it-sequential "wasm-gc-object-class-layout-rejects-unsupported-class-def"
  (let* ((inst (cl-cc/vm:make-vm-class-def :dst :r8
                                        :class-name :class-b
                                        :superclasses nil
                                        :slot-names (quote (bar foo))
                                        :slot-initargs nil
                                        :slot-initform-regs nil
                                        :slot-types nil
                                        :default-initarg-regs nil
                                        :class-slots nil
                                        :metaclass-reg nil))
         (message (%capture-wasm-error-message (lambda () (%direct-wasm-emit inst)))))
    (expect message :to-equal "Unsupported WASM instruction: VM-CLASS-DEF")))

(it-sequential "wasm-gc-inherited-layout-rejects-unsupported-class-def"
  (let* ((inst (cl-cc/vm:make-vm-class-def :dst :r8
                                        :class-name :sub-c
                                        :superclasses (quote (:super-c))
                                        :slot-names (quote (:sc))
                                        :slot-initargs nil
                                        :slot-initform-regs nil
                                        :slot-types nil
                                        :default-initarg-regs nil
                                        :class-slots nil
                                        :metaclass-reg nil))
         (message (%capture-wasm-error-message (lambda () (%direct-wasm-emit inst)))))
    (expect message :to-equal "Unsupported WASM instruction: VM-CLASS-DEF")))

(it-sequential "wasm-gc-class-def-reports-unsupported-instruction"
  (let* ((inst (cl-cc/vm:make-vm-class-def :dst :r7
                                        :class-name :my-class
                                        :superclasses nil
                                        :slot-names (quote (:a :b))
                                        :slot-initargs nil
                                        :slot-initform-regs nil
                                        :slot-types nil
                                        :default-initarg-regs nil
                                        :class-slots nil
                                        :metaclass-reg nil))
         (message (%capture-wasm-error-message (lambda () (%direct-wasm-emit inst)))))
    (expect message :to-equal "Unsupported WASM instruction: VM-CLASS-DEF")))

(it-sequential "wasm-gc-make-obj-reports-unsupported-instruction"
  (let* ((inst (cl-cc/vm:make-vm-make-obj :dst :r1 :class-reg :r8 :initarg-regs nil))
         (message (%capture-wasm-error-message (lambda () (%direct-wasm-emit inst)))))
    (expect message :to-equal "Unsupported WASM instruction: VM-MAKE-OBJ")))

(it-sequential "wasm-gc-register-method-runtime-bridge-emission"
  (let ((out (%direct-wasm-emit
              (cl-cc/vm:make-vm-register-method
               :gf-reg :r1
               :specializer 'my-class
               :qualifier nil
               :method-reg :r2))))
    (let* ((assert-output out) (assert-substring "call $host_rt_register_method")) (expect (and (stringp assert-output) (search assert-substring assert-output)) :to-be-truthy))
    ;; Symbol specializer should be passed as non-null staged symbol eqref.
    (let* ((assert-output out) (assert-substring "struct.new_immutable $symbol_t")) (expect (and (stringp assert-output) (search assert-substring assert-output)) :to-be-truthy))))

(it-sequential "wasm-gc-generic-call-runtime-bridge-emission"
  (let ((out (%direct-wasm-emit
              (cl-cc/vm:make-vm-generic-call :dst :r0 :gf-reg :r1 :args (list :r2 :r3)))))
    (let* ((assert-output out) (assert-substring "global.set $cl_arg0")) (expect (and (stringp assert-output) (search assert-substring assert-output)) :to-be-truthy))
    (let* ((assert-output out) (assert-substring "global.set $cl_arg1")) (expect (and (stringp assert-output) (search assert-substring assert-output)) :to-be-truthy))
    (let* ((assert-output out) (assert-substring "(call $host_rt_call_generic")) (expect (and (stringp assert-output) (search assert-substring assert-output)) :to-be-truthy))
    (let* ((assert-output out) (assert-substring "(i32.const 2)")) (expect (and (stringp assert-output) (search assert-substring assert-output)) :to-be-truthy))))

(it-sequential "wasm-gc-generic-call-runtime-bridge-supports-many-args"
  (let ((out (%direct-wasm-emit
              (cl-cc/vm:make-vm-generic-call :dst :r0 :gf-reg :r1
                                          :args (list :r2 :r3 :r4 :r5 :r6 :r7 :r8 :r9 :r10)))))
    (let* ((assert-output out) (assert-substring "global.set $cl_arg8")) (expect (and (stringp assert-output) (search assert-substring assert-output)) :to-be-truthy))
    (let* ((assert-output out) (assert-substring "(i32.const 9)")) (expect (and (stringp assert-output) (search assert-substring assert-output)) :to-be-truthy))))

;;; ──────────────────────────────────────────────────────────────────────────
;;; Section 10: Print support
;;; ──────────────────────────────────────────────────────────────────────────

(it-sequential "wasm-binary-opcode-bytes i64.const-42"
  (destructuring-bind (inst expected) (list (cl-cc/vm:make-vm-const :dst :r0 :value 42) '(#x42 #x2a))
    (expect (coerce (cl-cc/codegen-native/targets/wasm::wasm-encode-vm-instruction-opcode inst)
                        'list) :to-equal expected)))

(it-sequential "wasm-binary-opcode-bytes i64.add"
  (destructuring-bind (inst expected) (list (cl-cc/vm:make-vm-add :dst :r0 :lhs :r1 :rhs :r2) '(#x7c))
    (expect (coerce (cl-cc/codegen-native/targets/wasm::wasm-encode-vm-instruction-opcode inst)
                        'list) :to-equal expected)))

(it-sequential "wasm-binary-opcode-bytes i64.sub"
  (destructuring-bind (inst expected) (list (cl-cc/vm:make-vm-sub :dst :r0 :lhs :r1 :rhs :r2) '(#x7d))
    (expect (coerce (cl-cc/codegen-native/targets/wasm::wasm-encode-vm-instruction-opcode inst)
                        'list) :to-equal expected)))

(it-sequential "wasm-binary-opcode-bytes i64.mul"
  (destructuring-bind (inst expected) (list (cl-cc/vm:make-vm-mul :dst :r0 :lhs :r1 :rhs :r2) '(#x7e))
    (expect (coerce (cl-cc/codegen-native/targets/wasm::wasm-encode-vm-instruction-opcode inst)
                        'list) :to-equal expected)))

(it-sequential "wasm-binary-opcode-bytes call_indirect"
  (destructuring-bind (inst expected) (list (cl-cc/vm:make-vm-call :dst :r0 :func :r1 :args nil) '(#x11 0 0))
    (expect (coerce (cl-cc/codegen-native/targets/wasm::wasm-encode-vm-instruction-opcode inst)
                        'list) :to-equal expected)))

(it-sequential "wasm-binary-minimal-module-sections"
  (let* ((program (cl-cc/vm:make-vm-program :instructions nil))
         (bytes (cl-cc/codegen-native/targets/wasm:compile-to-wasm-binary program))
         (list-bytes (coerce bytes 'list)))
    (expect (typep bytes '(simple-array (unsigned-byte 8) (*))) :to-be-truthy)
    (expect (subseq list-bytes 0 8) :to-equal '(#x00 #x61 #x73 #x6d #x01 #x00 #x00 #x00))
    ;; section ids in order: type, function, export, code.  Payload sizes in
    ;; this minimal fixture are single-byte LEB128 values.
    (expect (loop with i = 8
                        while (< i (length list-bytes))
                        for id = (nth i list-bytes)
                        for size = (nth (1+ i) list-bytes)
                        collect id
                        do (incf i (+ 2 size))) :to-equal '(#x01 #x03 #x07 #x0a))
    (expect (search '(#x04 #x6d #x61 #x69 #x6e) list-bytes :test #'eql) :to-be-truthy)))
