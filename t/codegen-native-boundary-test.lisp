;;;; t/codegen-native-boundary-test.lisp — module boundary tests
;;;;
;;;; cl-cc's own suite covers code generation against these systems. What is
;;;; pinned here is the property that made the extraction possible: none of the
;;;; three names a cl-cc/vm internal. While they did -- 100 references in
;;;; codegen alone -- no separate repository could have built, since an external
;;;; consumer cannot reach another package's internal symbols.

(in-package :cl-cc-codegen-native/test)

(defun %internal-vm-references-in (path)
  "Return the distinct CL-CC/VM internal symbol names named under PATH."
  (let ((names '()))
    (dolist (file (directory (merge-pathnames "**/*.lisp" path))
                  (sort (remove-duplicates names :test #'string=) #'string<))
      (with-open-file (in file :external-format :utf-8)
        (loop for line = (read-line in nil)
              while line
              do (let ((start 0))
                   (loop for hit = (search "cl-cc/vm::" line :start2 start
                                                             :test #'char-equal)
                         while hit
                         do (let* ((from (+ hit (length "cl-cc/vm::")))
                                   (to (or (position-if-not
                                            (lambda (c)
                                              (or (alphanumericp c)
                                                  (find c "%*+-/=<>?!_")))
                                            line :start from)
                                           (length line))))
                              (when (> to from) (push (subseq line from to) names))
                              (setf start (max (1+ hit) to))))))))))

(describe-sequential "boundary with cl-cc/vm"
  (it "names no cl-cc/vm internal symbol in any of the three systems"
    ;; §5-2 of cl-cc's split design, asserted rather than trusted. A new
    ;; reference would reintroduce the coupling and surface only as a broken
    ;; build here, long after it was written.
    (dolist (system '("cl-cc-regalloc" "cl-cc-codegen" "cl-cc-emit"))
      (expect (%internal-vm-references-in
               (asdf:system-relative-pathname system "src/"))
              :to-be nil))))

(describe-sequential "the three systems load together"
  (it "has all three packages present"
    (dolist (name '("CL-CC/REGALLOC" "CL-CC/CODEGEN" "CL-CC/EMIT"))
      (expect (find-package name) :to-be-truthy)))

  (it "has its dependencies present and the front end absent"
    ;; The native backend consumes the VM's IR and the target descriptions; it
    ;; has no business seeing the reader or the macroexpander.
    ;;
    ;; CL-CC/TYPE is not in that list even though nothing here names it: it
    ;; arrives through cl-cc-optimize, which the allocator's cost model depends
    ;; on. Asserting its absence would be asserting something about a
    ;; dependency's dependencies, which is not this repository's business.
    (dolist (name '("CL-CC/VM" "CL-CC/MIR" "CL-CC/TARGET"))
      (expect (find-package name) :to-be-truthy))
    (dolist (name '("CL-CC/PARSE" "CL-CC/EXPAND"))
      (expect (find-package name) :to-be nil))))

(describe-sequential "target coverage"
  (it "encodes for every target cl-cc-target describes"
    ;; A target described but not encodable is the failure mode this catches:
    ;; the description registry and the encoder tables are edited separately.
    (dolist (name '(:x86-64 :aarch64 :riscv64))
      (expect (cl-cc/target:find-target name) :to-be-truthy)))

  (it "reports AArch64 register-pool exhaustion without an unbound variable"
    (let ((condition
            (handler-case
                (progn
                  (cl-cc/codegen::target-register
                   (make-instance 'cl-cc/codegen:aarch64-target)
                   :r18)
                  nil)
              (error (caught) caught))))
      (expect condition :to-be-truthy)
      (expect (typep condition 'unbound-variable) :to-be nil)))

  (it "provides the short WASM function constructor"
    (let* ((constructor (find-symbol "MAKE-WASM-FUNC" "CL-CC/CODEGEN"))
           (function (and constructor (symbol-function constructor))))
      (expect constructor :to-be-truthy)
      (expect (funcall function :wat-name "$regression") :to-be-truthy)))

  (it "rejects heap opcodes interned in the caller package"
    (let ((condition
            (handler-case
                (progn
                  (cl-cc/emit:validate-ebpf-verifier-constraints
                   '((alloc) (:exit)))
                  nil)
              (error (caught) caught))))
      (expect condition :to-be-truthy))))

(describe-sequential "WASM slot layout resolution"
  (it "preserves a recorded slot at index zero"
    (let ((target (make-instance (quote cl-cc/emit:wasm-target))))
      (setf (gethash (quote first)
                     (cl-cc/codegen::wasm-target-known-slot-indexes target))
            0)
      (expect (cl-cc/codegen::wasm-slot-index-for target (quote first)) :to-be 0)
      (expect (cl-cc/codegen::wasm-slot-index-for-object-slot
               target :object (quote first))
              :to-be 0)))

  (it "uses an object-specific class layout"
    (let* ((target (make-instance (quote cl-cc/emit:wasm-target)))
           (layout (make-hash-table :test (function equal))))
      (setf (gethash :object
                     (cl-cc/codegen::wasm-target-known-object-class-by-reg target))
            (quote widget)
            (gethash (quote widget)
                     (cl-cc/codegen::wasm-target-class-slot-layouts target))
            layout
            (gethash (quote first) layout)
            0)
      (expect (cl-cc/codegen::wasm-slot-index-for-object-slot
               target :object (quote first))
              :to-be 0)))

  (it "rejects slots with no recorded layout"
    (let ((target (make-instance (quote cl-cc/emit:wasm-target))))
      (dolist (lookup (list
                        (lambda ()
                          (cl-cc/codegen::wasm-slot-index-for
                            target (quote missing)))
                        (lambda ()
                          (cl-cc/codegen::wasm-slot-index-for-object-slot
                            target :object (quote missing)))))
        (expect (handler-case
                    (progn (funcall lookup) nil)
                  (error (caught) caught))
                :to-be-truthy)))))

(describe-sequential "WASM float arithmetic fails closed"
  (it "rejects all float arithmetic in text and binary lowering"
    (let ((target (make-instance (quote cl-cc/emit:wasm-target))))
      (dolist (constructor '(cl-cc/vm:make-vm-float-add
                            cl-cc/vm:make-vm-float-sub
                            cl-cc/vm:make-vm-float-mul
                            cl-cc/vm:make-vm-float-div))
        (let ((inst (funcall constructor :dst :r2 :lhs :r0 :rhs :r1)))
          (expect (handler-case
                      (progn
                        (cl-cc/codegen::emit-instruction
                         target inst (make-string-output-stream))
                        nil)
                    (error () t))
                  :to-be-truthy)
          (expect (handler-case
                      (progn
                        (cl-cc/codegen::wasm-encode-vm-instruction-opcode inst)
                        nil)
                    (error () t))
                  :to-be-truthy))))))


(defun %native-emitter-octets (emitter inst)
  (let ((bytes (quote ())))
    (funcall
      emitter
      inst
      (lambda (byte)
        (push byte bytes)))
    (coerce (nreverse bytes) (quote (simple-array (unsigned-byte 8) (*))))))

(describe-sequential
  "native float precision lowering"
  (it
    "selects x86 scalar single and double encodings"
    (expect
      (cl-cc/codegen::with-output-to-vector
        (stream)
        (cl-cc/codegen::emit-vm-float-add
          (cl-cc/vm:make-vm-float-add :dst :r2 :lhs :r0 :rhs :r1 :precision :f32)
          stream))
      :to-equalp
      #(243 15 16 208 243 15 88 209))
    (expect
      (cl-cc/codegen::with-output-to-vector
        (stream)
        (cl-cc/codegen::emit-vm-float-add
          (cl-cc/vm:make-vm-float-add :dst :r2 :lhs :r0 :rhs :r1)
          stream))
      :to-equalp
      #(242 15 16 208 242 15 88 209)))
  (it
    "selects x86 scalar FMA precision"
    (expect
      (cl-cc/codegen::with-output-to-vector
        (stream)
        (cl-cc/codegen::emit-vm-fma
          (cl-cc/vm:make-vm-fma :dst :r3 :a :r0 :b :r1 :c :r2 :precision :f32)
          stream))
      :to-equalp
      #(243 15 16 216 196 226 105 153 217))
    (expect
      (cl-cc/codegen::with-output-to-vector
        (stream)
        (cl-cc/codegen::emit-vm-fma
          (cl-cc/vm:make-vm-fma :dst :r3 :a :r0 :b :r1 :c :r2)
          stream))
      :to-equalp
      #(242 15 16 216 196 226 233 153 217)))
  (it
    "selects AArch64 scalar and FMA precision"
    (expect
      (%native-emitter-octets
        (function cl-cc/codegen::emit-a64-vm-float-add)
        (cl-cc/vm:make-vm-float-add :dst :r2 :lhs :r0 :rhs :r1 :precision :f32))
      :to-equalp
      #(2 40 33 30))
    (expect
      (%native-emitter-octets
        (function cl-cc/codegen::emit-a64-vm-float-add)
        (cl-cc/vm:make-vm-float-add :dst :r2 :lhs :r0 :rhs :r1))
      :to-equalp
      #(2 40 97 30))
    (expect
      (%native-emitter-octets
        (function cl-cc/codegen::emit-a64-vm-fma)
        (cl-cc/vm:make-vm-fma :dst :r3 :a :r0 :b :r1 :c :r2 :precision :f32))
      :to-equalp
      #(3 8 1 31))
    (expect
      (%native-emitter-octets
        (function cl-cc/codegen::emit-a64-vm-fma)
        (cl-cc/vm:make-vm-fma :dst :r3 :a :r0 :b :r1 :c :r2))
      :to-equalp
      #(3 8 65 31)))
  (it
    "selects RISC-V scalar single and double encodings"
    (expect
      (%native-emitter-octets
        (function cl-cc/codegen::emit-riscv64-vm-float-add)
        (cl-cc/vm:make-vm-float-add :dst :f2 :lhs :f0 :rhs :f1 :precision :f32))
      :to-equalp
      #(83 1 16 0))
    (expect
      (%native-emitter-octets
        (function cl-cc/codegen::emit-riscv64-vm-float-add)
        (cl-cc/vm:make-vm-float-add :dst :f2 :lhs :f0 :rhs :f1))
      :to-equalp
      #(83 1 16 2))))

(describe-sequential "native packed F64 SIMD lowering"
  (it "encodes x86 packed F64 bytes with matching size and scale"
    (let* ((inst (cl-cc/vm:make-vm-simd-vector-op
                   :op :add :dst-array :r3 :lhs-array :r1 :rhs-array :r2
                   :index-reg :r4 :lanes 2 :element-type :f64))
           (bytes (cl-cc/codegen::with-output-to-vector
                    (stream)
                    (cl-cc/codegen::emit-vm-simd-vector-op inst stream))))
      (expect (cl-cc/codegen::x86-64-simd-element-scale :f64) :to-be 8)
      (expect (search #(102 15 88 193) bytes :test (function =)) :to-be-truthy)
      (expect (length bytes) :to-be (cl-cc/codegen::instruction-size inst))))
  (it "encodes AArch64 packed F64 words with matching size"
    (let* ((inst (cl-cc/vm:make-vm-simd-vector-op
                   :op :add :dst-array :r3 :lhs-array :r1 :rhs-array :r2
                   :index-reg :r4 :lanes 2 :element-type :f64))
           (bytes (%native-emitter-octets
                    (function cl-cc/codegen::emit-a64-vm-simd-vector-op)
                    inst)))
      (expect (cl-cc/codegen::encode-neon-fadd2d 0 0 1) :to-be #x4e61d400)
      (expect (cl-cc/codegen::encode-neon-fsub2d 0 0 1) :to-be #x4ee1d400)
      (expect (cl-cc/codegen::encode-neon-fmul2d 0 0 1) :to-be #x6e61dc00)
      (expect (search #(0 212 97 78) bytes :test (function =)) :to-be-truthy)
      (expect (length bytes) :to-be 40)
      (expect (cl-cc/codegen::a64-instruction-size inst) :to-be 40)))
  (it "rejects unsupported packed F64 SIMD shapes and operations"
    (dolist (validator (list (function cl-cc/codegen::x86-64-validate-simd-vector-op)
                             (function cl-cc/codegen::a64-validate-simd-vector-op)))
      (dolist (inst (list
                      (cl-cc/vm:make-vm-simd-vector-op
                        :op :add :dst-array :r3 :lhs-array :r1 :rhs-array :r2
                        :index-reg :r4 :lanes 4 :element-type :f64)
                      (cl-cc/vm:make-vm-simd-vector-op
                        :op :logand :dst-array :r3 :lhs-array :r1 :rhs-array :r2
                        :index-reg :r4 :lanes 2 :element-type :f64)))
        (expect
          (handler-case
              (progn (funcall validator inst) nil)
            (error () t))
          :to-be-truthy)))))
