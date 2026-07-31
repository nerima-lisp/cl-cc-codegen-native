;;;; t/codegen-native-boundary-test.lisp — module boundary and regression tests
;;;;
;;;; cl-cc's own suite covers code generation against these systems. What is
;;;; pinned here is the property that made the extraction possible: none of the
;;;; three names a cl-cc/vm internal. While they did -- 100 references in
;;;; codegen alone -- no separate repository could have built, since an external
;;;; consumer cannot reach another package's internal symbols.
;;;;
;;;; The rest of the file has grown past that original boundary-only scope
;;;; into this repository's general regression suite: target/encoding
;;;; coverage, data/logic-separation lookup tables, the cl-process-kit
;;;; migration's mocked integration tests (see project memory:
;;;; process-kit-real-invocation-crash-2026-07 for why those mock rather
;;;; than shell out to real sysctl/wasm-opt/wat2wasm), and cl-weave
;;;; IT-PROPERTY fuzz tests. The name is kept for history/URL stability
;;;; rather than split apart, since `cl-weave:run-all`'s reporting is by
;;;; DESCRIBE block, not by file.

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
    (signals error
      (cl-cc/emit:validate-ebpf-verifier-constraints
       (quote ((alloc) (:exit)))))))

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
        (signals error (funcall lookup))))))

(describe-sequential "WASM float arithmetic fails closed"
  (it "rejects all float arithmetic in text and binary lowering"
    (let ((target (make-instance (quote cl-cc/emit:wasm-target))))
      (dolist (constructor (quote (cl-cc/vm:make-vm-float-add
                                    cl-cc/vm:make-vm-float-sub
                                    cl-cc/vm:make-vm-float-mul
                                    cl-cc/vm:make-vm-float-div)))
        (let ((inst (funcall constructor :dst :r2 :lhs :r0 :rhs :r1)))
          (signals error
            (cl-cc/codegen::emit-instruction
             target inst (make-string-output-stream)))
          (signals error
            (cl-cc/codegen::wasm-encode-vm-instruction-opcode inst)))))))


(defun %collect-emitted-octets (invoke-emitter)
  "Collect the bytes an emitter writes into an octet vector.

INVOKE-EMITTER is itself a function of one argument: SINK, the byte-sink
continuation to drive an emitter with (every native emit-* function in this
codebase takes such a continuation as its STREAM parameter -- see
with-output-to-vector in x86-64-encoding.lisp for the same mechanism used
in production). This generalizes the two ad-hoc byte-collecting shapes the
test suite used to have (a with-output-to-vector call for x86, and a
two-argument emitter+inst helper for AArch64/RISC-V) into one: INVOKE-EMITTER
decides how many emitters to call and with what arguments, this function
only owns the accumulation."
  (let ((bytes (quote ())))
    (funcall invoke-emitter (lambda (byte) (push byte bytes)))
    (coerce (nreverse bytes) (quote (simple-array (unsigned-byte 8) (*))))))

(describe-sequential
  "native float precision lowering"
  (it-each ((:f32 #(243 15 16 208 243 15 88 209))
          (nil  #(242 15 16 208 242 15 88 209)))
    "selects x86 scalar float-add ~A encoding"
    (precision expected)
  (expect
    (%collect-emitted-octets
      (lambda (sink)
        (cl-cc/codegen::emit-vm-float-add
          (apply (function cl-cc/vm:make-vm-float-add)
                 :dst :r2 :lhs :r0 :rhs :r1
                 (when precision (list :precision precision)))
          sink)))
    :to-equalp
    expected))
  (it-each ((:f32 #(243 15 16 216 196 226 105 153 217))
          (nil  #(242 15 16 216 196 226 233 153 217)))
    "selects x86 scalar FMA ~A encoding"
    (precision expected)
  (expect
    (%collect-emitted-octets
      (lambda (sink)
        (cl-cc/codegen::emit-vm-fma
          (apply (function cl-cc/vm:make-vm-fma)
                 :dst :r3 :a :r0 :b :r1 :c :r2
                 (when precision (list :precision precision)))
          sink)))
    :to-equalp
    expected))
  (describe "selects AArch64 scalar and FMA precision"
    (it-each ((:f32 #(2 40 33 30))
              (nil  #(2 40 97 30)))
        "float-add ~A encoding"
        (precision expected)
      (expect
        (%collect-emitted-octets
          (lambda (sink)
            (funcall (function cl-cc/codegen::emit-a64-vm-float-add)
                     (apply (function cl-cc/vm:make-vm-float-add)
                            :dst :r2 :lhs :r0 :rhs :r1
                            (when precision (list :precision precision)))
                     sink)))
        :to-equalp
        expected))
    (it-each ((:f32 #(3 8 1 31))
              (nil  #(3 8 65 31)))
        "FMA ~A encoding"
        (precision expected)
      (expect
        (%collect-emitted-octets
          (lambda (sink)
            (funcall (function cl-cc/codegen::emit-a64-vm-fma)
                     (apply (function cl-cc/vm:make-vm-fma)
                            :dst :r3 :a :r0 :b :r1 :c :r2
                            (when precision (list :precision precision)))
                     sink)))
        :to-equalp
        expected)))
  (it-each ((:f32 #(83 1 16 0))
          (nil  #(83 1 16 2)))
    "selects RISC-V scalar float-add ~A encoding"
    (precision expected)
  (expect
    (%collect-emitted-octets
      (lambda (sink)
        (funcall (function cl-cc/codegen::emit-riscv64-vm-float-add)
                 (apply (function cl-cc/vm:make-vm-float-add)
                        :dst :f2 :lhs :f0 :rhs :f1
                        (when precision (list :precision precision)))
                 sink)))
    :to-equalp
    expected)))

(describe-sequential "native packed F64 SIMD lowering"
  (it "encodes x86 packed F64 bytes with matching size and scale"
    (let* ((inst (cl-cc/vm:make-vm-simd-vector-op
                   :op :add :dst-array :r3 :lhs-array :r1 :rhs-array :r2
                   :index-reg :r4 :lanes 2 :element-type :f64))
           (bytes (%collect-emitted-octets
                    (lambda (sink)
                      (cl-cc/codegen::emit-vm-simd-vector-op inst sink)))))
      (expect (cl-cc/codegen::x86-64-simd-element-scale :f64) :to-be 8)
      (expect (search #(102 15 88 193) bytes :test (function =)) :to-be-truthy)
      (expect (length bytes) :to-be (cl-cc/codegen::instruction-size inst))))
  (it "encodes AArch64 packed F64 words with matching size"
    (let* ((inst (cl-cc/vm:make-vm-simd-vector-op
                   :op :add :dst-array :r3 :lhs-array :r1 :rhs-array :r2
                   :index-reg :r4 :lanes 2 :element-type :f64))
           (bytes (%collect-emitted-octets
                    (lambda (sink)
                      (funcall (function cl-cc/codegen::emit-a64-vm-simd-vector-op)
                               inst sink)))))
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

(describe-sequential "data/logic separation: 2026-07 lookup-table extractions"
  (it-each ((:fixnum "$fixnum_array_t")
            (:float "$float_array_t")
            (:char "$char_array_t")
            (:eqref "$eqref_array_t")
            (:some-unrecognized-keyword "$eqref_array_t"))
      "wasm-array-type-name normalizes ~A to ~A"
      (kind expected)
    (expect (cl-cc/codegen::wasm-array-type-name kind) :to-equal expected))

  (it-each ((:fixnum "i64") (:integer "i64") (:any "i64")
            (:character "i8") (:char "i8")
            (:boolean "i1")
            (:pointer "ptr") (:function "ptr")
            (:void "void")
            (:some-unrecognized-keyword "i64"))
      "%llvm-type maps ~A to ~A"
      (type expected)
    (expect (cl-cc/emit::%llvm-type type) :to-equal expected))

  (it-each ((:fixnum "i64") (:character "i8") (:boolean "i1")
            (:pointer "!llvm.ptr") (:void "none"))
      "%mlir-type maps ~A to ~A"
      (type expected)
    (expect (cl-cc/emit::%mlir-type type) :to-equal expected))

  (it-each ((0 1) (1 2) (2 4) (3 8) (4 nil) (-1 nil))
      "x86-64-power-of-two-scale-from-shift maps shift ~A to scale ~A"
      (shift expected)
    (expect (cl-cc/codegen::x86-64-power-of-two-scale-from-shift shift)
            :to-be expected)))

(describe-sequential "cl-process-kit integration: wasm-aot.lisp external tools"
  ;; These mock PROCESS-KIT directly rather than shelling out to a real
  ;; shasum/wasm-opt/wat2wasm, so the suite is deterministic regardless of
  ;; which optional tools happen to be installed in the sandbox -- and so it
  ;; exercises the 2026-07 migration off bare UIOP:RUN-PROGRAM without
  ;; depending on external binaries.
  (it "wasm-run-tool-to-string returns the tool's stdout on success"
    (with-mocked-functions
        (((symbol-function 'cl-cc/codegen::wasm-tool-available-p)
          (lambda (program) (declare (ignore program)) t))
         ((symbol-function 'process-kit:run/checked)
          (lambda (program args &rest options)
            (declare (ignore options))
            (expect program :to-equal "shasum")
            (expect args :to-equal (list "-a" "256" "/tmp/x.wasm"))
            (process-kit:make-process-result :stdout "deadbeef  /tmp/x.wasm"))))
      (expect (cl-cc/codegen::wasm-run-tool-to-string
               (list "shasum" "-a" "256" "/tmp/x.wasm"))
              :to-equal "deadbeef  /tmp/x.wasm")))

  (it "wasm-run-tool-to-string returns NIL when the underlying process-kit call fails"
    (with-mocked-functions
        (((symbol-function 'cl-cc/codegen::wasm-tool-available-p)
          (lambda (program) (declare (ignore program)) t))
         ((symbol-function 'process-kit:run/checked)
          (lambda (&rest arguments)
            (declare (ignore arguments))
            (error 'process-kit:process-error))))
      (expect (cl-cc/codegen::wasm-run-tool-to-string (list "shasum" "-a" "256" "/tmp/x.wasm"))
              :to-be nil)))

  (it "wasm-run-tool-to-string returns NIL without invoking process-kit when the tool is unavailable"
    (with-mocked-functions
        (((symbol-function 'cl-cc/codegen::wasm-tool-available-p)
          (lambda (program) (declare (ignore program)) nil)))
      (expect (cl-cc/codegen::wasm-run-tool-to-string (list "nonexistent-tool")) :to-be nil)))

  (it "wasm-run-wasm-opt-passes returns the bytes process-kit's mocked wasm-opt wrote to the -o path"
    (with-mocked-functions
        (((symbol-function 'cl-cc/codegen::wasm-tool-available-p)
          (lambda (program) (declare (ignore program)) t))
         ((symbol-function 'process-kit:run/checked)
          (lambda (program args &rest options)
            (declare (ignore options))
            (expect program :to-equal "wasm-opt")
            (let ((out-path (nth (1+ (position "-o" args :test (function string=))) args)))
              (with-open-file (stream out-path :direction :output
                                               :element-type '(unsigned-byte 8)
                                               :if-exists :supersede
                                               :if-does-not-exist :create)
                (write-sequence #(9 9 9) stream)))
            (process-kit:make-process-result :stdout ""))))
      (expect (cl-cc/codegen::wasm-run-wasm-opt-passes #(1 2 3) :aot t)
              :to-equalp #(9 9 9))))

  (it "wasm-run-wasm-opt-passes falls back to the original bytes when wasm-opt fails"
    (with-mocked-functions
        (((symbol-function 'cl-cc/codegen::wasm-tool-available-p)
          (lambda (program) (declare (ignore program)) t))
         ((symbol-function 'process-kit:run/checked)
          (lambda (&rest arguments)
            (declare (ignore arguments))
            (error 'process-kit:process-error))))
      (expect (cl-cc/codegen::wasm-run-wasm-opt-passes #(1 2 3) :aot t)
              :to-equalp #(1 2 3)))))

(describe-sequential "x86-64-ibrs-token-present-p token boundary matching"
  (it-each (("cpu features: ibrs" t)
            ("CPU FEATURES: IBRS" t)
            ("flags: eibrs enabled" t)
            ("flags: EIBRS" t)
            ("fooibrs" nil)
            ("ibrsbar" nil)
            ("" nil)
            (nil nil))
      "x86-64-ibrs-token-present-p on ~S returns ~A"
      (text expected)
    (expect (cl-cc/codegen::x86-64-ibrs-token-present-p text) :to-be expected)))

(describe-sequential "x86-64-cpu-token-present-p token boundary matching"
  (it-each (("cpu: popcnt bmi1 bmi2" "popcnt" t)
            ("cpu: popcnt bmi1 bmi2" "bmi2" t)
            ("cpu: popcnt bmi1 bmi2" "avx512" nil)
            ("cpu: nopopcntx" "popcnt" nil)
            (nil "popcnt" nil))
      "x86-64-cpu-token-present-p(~S, ~S) => ~A"
      (text token expected)
    (expect (cl-cc/codegen::x86-64-cpu-token-present-p text token) :to-be expected)))

(describe-sequential "property-based coverage: 2026-07 cl-weave IT-PROPERTY adoption"
  ;; The example-based IT-EACH tables above pin a handful of hand-picked
  ;; cases; these use cl-weave's fuzz-testing generators (previously unused
  ;; in this repository, see the cl-weave advanced-feature survey in
  ;; project memory) to check the same functions' invariants across a much
  ;; wider input space than any fixed table could enumerate.
  (it-property "x86-64-ibrs-token-present-p finds ibrs as a separated whole word regardless of surrounding text"
      ((prefix (gen-string :min-length 0 :max-length 12))
       (suffix (gen-string :min-length 0 :max-length 12)))
    ;; The literal spaces around "ibrs" guarantee a word boundary on both
    ;; sides no matter what PREFIX/SUFFIX generate, so this should hold for
    ;; every case cl-weave's shrinker could find.
    (expect (cl-cc/codegen::x86-64-ibrs-token-present-p (format nil "~A ibrs ~A" prefix suffix))
            :to-be-truthy))

  (it-property "x86-64-power-of-two-scale-from-shift returns 2^shift for shift 0..3 and NIL otherwise"
      ((shift (gen-integer :min -50 :max 50)))
    (let ((result (cl-cc/codegen::x86-64-power-of-two-scale-from-shift shift)))
      (if (<= 0 shift 3)
          (expect result :to-be (expt 2 shift))
          (expect result :to-be nil))))

  (it-property "wasm-array-type-name is total: never signals for any keyword, known or not"
      ((kind (gen-keyword '("fixnum" "float" "char" "eqref" "unknown-a" "unknown-b" "random-tag"))))
    (expect (stringp (cl-cc/codegen::wasm-array-type-name kind)) :to-be-truthy))

  (it-property "wasm-normalize-array-element-kind is total: always one of the 4 valid kinds, for any designator"
      ((designator (gen-keyword '("fixnum" "integer" "float" "double-float" "character"
                                   "any" "eqref" "totally-unrecognized" "another-unknown"))))
    (expect (member (cl-cc/codegen::wasm-normalize-array-element-kind designator)
                     '(:fixnum :float :char :eqref))
            :to-be-truthy))

  (it-property "wasm-i31-range-p agrees with a direct interval check across a wide integer range"
      ((n (gen-integer :min -2000000000 :max 2000000000)))
    (expect (and (cl-cc/codegen::wasm-i31-range-p n) t)
            :to-be (and (<= cl-cc/codegen::+wasm-i31-min+ n cl-cc/codegen::+wasm-i31-max+) t))))

(describe-sequential "wasm-trampoline-proposals.lisp: copysign / storage-condition / table-index WAT primitives"
  (it "wasm-copysign-wat emits f64.copysign(magnitude, sign)"
    (expect (cl-cc/codegen::wasm-copysign-wat "(local.get 0)" "(local.get 1)")
            :to-equal "(f64.copysign (local.get 0) (local.get 1))"))
  (it "wasm-storage-condition-wat encodes the 17-character symbol name as fixed i32.const byte elements"
    (expect (cl-cc/codegen::wasm-storage-condition-wat)
            :to-equal "(struct.new $symbol_t (struct.new $string_t (array.new_fixed $bytes_array_t 17 (i32.const 83) (i32.const 84) (i32.const 79) (i32.const 82) (i32.const 65) (i32.const 71) (i32.const 69) (i32.const 45) (i32.const 67) (i32.const 79) (i32.const 78) (i32.const 68) (i32.const 73) (i32.const 84) (i32.const 73) (i32.const 79) (i32.const 78))) (ref.null eq))"))
  (it "wasm-table-index-type-wat is i32 by default (*wasm-table64-enabled* and *wasm-memory64-enabled* both default NIL)"
    (expect (cl-cc/codegen::wasm-table-index-type-wat) :to-equal "i32"))
  (it "wasm-table-const-wat formats VALUE at the active (default i32) table-index width"
    (expect (cl-cc/codegen::wasm-table-const-wat 42) :to-equal "(i32.const 42)"))
  (it "wasm-memory-fill-wat omits the (memory N) clause by default (*wasm-multiple-memories-enabled* defaults NIL)"
    (expect (cl-cc/codegen::wasm-memory-fill-wat "(local.get 0)" "(i32.const 0)" "(local.get 1)")
            :to-equal "(memory.fill (local.get 0) (i32.const 0) (local.get 1))")))

(describe-sequential "x86-64-codegen-emitters.lisp: speculation-barrier / CFI-entry / phys-code lookup"
  (it "emit-x86-64-speculation-barrier emits a fixed 3-byte LFENCE (0F AE E8)"
    (expect (%collect-emitted-octets
             (lambda (sink) (cl-cc/codegen::emit-x86-64-speculation-barrier sink)))
            :to-equalp #(#x0F #xAE #xE8)))
  (it "emit-x86-64-cfi-entry emits 4-byte ENDBR64 (F3 0F 1E FA) when the plan requests it"
    (expect (%collect-emitted-octets
             (lambda (sink)
               (cl-cc/codegen::emit-x86-64-cfi-entry sink (list :entry-opcode :endbr64))))
            :to-equalp #(#xF3 #x0F #x1E #xFA)))
  (it "emit-x86-64-cfi-entry emits nothing when the plan doesn't request :endbr64"
    (expect (%collect-emitted-octets
             (lambda (sink) (cl-cc/codegen::emit-x86-64-cfi-entry sink nil)))
            :to-equalp #()))
  (it "x86-64-speculative-execution-mitigation-enabled-p is NIL by default, T when either flag is set"
    (expect (cl-cc/codegen::x86-64-speculative-execution-mitigation-enabled-p) :to-be nil)
    (let ((cl-cc/codegen::*x86-64-spectre-mitigations-enabled* t))
      (expect (and (cl-cc/codegen::x86-64-speculative-execution-mitigation-enabled-p) t) :to-be t))
    (let ((cl-cc/codegen::*x86-64-use-retpoline* t))
      (expect (and (cl-cc/codegen::x86-64-speculative-execution-mitigation-enabled-p) t) :to-be t)))
  (it "x86-64-phys-code->keyword reverse-looks-up a known code, and returns NIL for RSP (deliberately not GP-allocatable)"
    (expect (cl-cc/codegen::x86-64-phys-code->keyword 0) :to-be :rax)
    (expect (cl-cc/codegen::x86-64-phys-code->keyword 5) :to-be :rbp)
    (expect (cl-cc/codegen::x86-64-phys-code->keyword 4) :to-be nil)))

(describe-sequential "x86-64-codegen-emitters.lisp: x86-64-relaxable-branch-p / x86-64-branch-target-offset"
  (it "x86-64-relaxable-branch-p is T for vm-jump/vm-jump-zero, NIL for an unrelated instruction"
    (expect (and (cl-cc/codegen::x86-64-relaxable-branch-p
                  (cl-cc/vm:make-vm-jump :label "L1"))
                 t)
            :to-be t)
    (expect (and (cl-cc/codegen::x86-64-relaxable-branch-p
                  (cl-cc/vm:make-vm-jump-zero :reg :r0 :label "L1"))
                 t)
            :to-be t)
    (expect (cl-cc/codegen::x86-64-relaxable-branch-p
             (cl-cc/vm:make-vm-add :dst :r0 :lhs :r1 :rhs :r2))
            :to-be nil))
  (it "x86-64-branch-target-offset returns the label's recorded position"
    (let ((h (make-hash-table :test 'equal)))
      (setf (gethash "L1" h) 42)
      (expect (cl-cc/codegen::x86-64-branch-target-offset
               (cl-cc/vm:make-vm-jump :label "L1") h)
              :to-be 42)))
  (it "x86-64-branch-target-offset signals an error for a label absent from LABEL-OFFSETS"
    (signals error
      (cl-cc/codegen::x86-64-branch-target-offset
       (cl-cc/vm:make-vm-jump :label "unknown-label")
       (make-hash-table :test 'equal)))))

(describe-sequential "x86-64-codegen-emitters.lisp: emit-x86-64-stack-probes"
  ;; Emits one 9-byte OR [RSP-page*4096], 0 per guard page; PAGE runs 1..N,
  ;; so a 2-probe call must show two DIFFERENT displacements (-4096, -8192),
  ;; verifying the loop actually increments rather than repeating page 1.
  (it "emits one 9-byte OR probe per guard page, at increasing negative displacements"
    (expect (%collect-emitted-octets
             (lambda (sink) (cl-cc/codegen::emit-x86-64-stack-probes sink 2)))
            :to-equalp #(#x48 #x83 #x8C #x24 #x00 #xF0 #xFF #xFF #x00   ; page 1: [RSP-4096]
                         #x48 #x83 #x8C #x24 #x00 #xE0 #xFF #xFF #x00)))) ; page 2: [RSP-8192]

(describe-sequential "x86-64-emit-ops.lisp: define-checked-binary-alu-emitter family (add/sub/mul-checked)"
  ;; MOV dst,lhs + ASM-OP dst,rhs + JNO rel32 +2 (skip UD2) + UD2 trap.
  (it "emit-vm-add-checked: MOV + ADD + JNO +2 + UD2"
    (expect (%collect-emitted-octets
             (lambda (sink)
               (cl-cc/codegen::emit-vm-add-checked
                (cl-cc/vm:make-vm-add-checked :dst :r0 :lhs :r1 :rhs :r2) sink)))
            :to-equalp #(#x48 #x89 #xC8   ; MOV RAX, RCX
                         #x48 #x01 #xD0   ; ADD RAX, RDX
                         #x0F #x81 #x02 #x00 #x00 #x00 ; JNO +2
                         #x0F #x0B)))     ; UD2
  (it "emit-vm-sub-checked: MOV + SUB + JNO +2 + UD2"
    (expect (%collect-emitted-octets
             (lambda (sink)
               (cl-cc/codegen::emit-vm-sub-checked
                (cl-cc/vm:make-vm-sub-checked :dst :r0 :lhs :r1 :rhs :r2) sink)))
            :to-equalp #(#x48 #x89 #xC8
                         #x48 #x29 #xD0   ; SUB RAX, RDX
                         #x0F #x81 #x02 #x00 #x00 #x00
                         #x0F #x0B)))
  (it "emit-vm-mul-checked: MOV + IMUL (0F AF, reg=dst rm=src -- opposite operand order from ADD/SUB) + JNO +2 + UD2"
    (expect (%collect-emitted-octets
             (lambda (sink)
               (cl-cc/codegen::emit-vm-mul-checked
                (cl-cc/vm:make-vm-mul-checked :dst :r0 :lhs :r1 :rhs :r2) sink)))
            :to-equalp #(#x48 #x89 #xC8
                         #x48 #x0F #xAF #xC2 ; IMUL RAX, RDX
                         #x0F #x81 #x02 #x00 #x00 #x00
                         #x0F #x0B))))

(describe-sequential "x86-64-codegen-emitters.lisp: emit-x86-64-stack-canary-prologue / -epilogue"
  ;; Both guard on (AND FRAME-POINTER-P (GETF CANARY-PLAN :ENABLED-P)) --
  ;; covering the emission case plus both ways the guard can be false.
  (it "prologue emits MOV RAX,FS:[0x28] + MOV [RBP+8],RAX when enabled and frame-pointer-p"
    (expect (%collect-emitted-octets
             (lambda (sink)
               (cl-cc/codegen::emit-x86-64-stack-canary-prologue
                sink (list :enabled-p t :guard-slot 8) t)))
            :to-equalp #(#x64 #x48 #x8B #x04 #x25 #x28 #x00 #x00 #x00   ; MOV RAX, FS:[0x28]
                         #x48 #x89 #x45 #x08)))                          ; MOV [RBP+8], RAX
  (it "prologue emits nothing when the plan is disabled"
    (expect (%collect-emitted-octets
             (lambda (sink)
               (cl-cc/codegen::emit-x86-64-stack-canary-prologue
                sink (list :enabled-p nil :guard-slot 8) t)))
            :to-equalp #()))
  (it "prologue emits nothing when there is no frame pointer, even if enabled"
    (expect (%collect-emitted-octets
             (lambda (sink)
               (cl-cc/codegen::emit-x86-64-stack-canary-prologue
                sink (list :enabled-p t :guard-slot 8) nil)))
            :to-equalp #()))
  (it "epilogue emits the reload + FS compare + JE +2 + UD2 trap idiom when enabled"
    (expect (%collect-emitted-octets
             (lambda (sink)
               (cl-cc/codegen::emit-x86-64-stack-canary-epilogue
                sink (list :enabled-p t :guard-slot 8) t)))
            :to-equalp #(#x48 #x8B #x45 #x08                            ; MOV RAX, [RBP+8]
                         #x64 #x48 #x3B #x04 #x25 #x28 #x00 #x00 #x00   ; CMP RAX, FS:[0x28]
                         #x0F #x84 #x02 #x00 #x00 #x00                  ; JE +2
                         #x0F #x0B)))                                    ; UD2
  (it "epilogue emits nothing when the plan is disabled"
    (expect (%collect-emitted-octets
             (lambda (sink)
               (cl-cc/codegen::emit-x86-64-stack-canary-epilogue
                sink (list :enabled-p nil :guard-slot 8) t)))
            :to-equalp #())))

(describe-sequential "x86-64-codegen-emitters.lisp: emit-x86-64-function-prologue / -epilogue"
  ;; Frame-pointer functions use PUSH RBP; MOV RBP,RSP; PUSH (CDR save-regs),
  ;; and LEAVE;RET on exit. Frame-pointer-omitted functions just PUSH/POP
  ;; every save-reg directly, ending in a bare RET.
  (it "prologue (frame-pointer-p): PUSH RBP + MOV RBP,RSP + PUSH the rest of SAVE-REGS"
    (expect (%collect-emitted-octets
             (lambda (sink)
               (cl-cc/codegen::emit-x86-64-function-prologue sink t (list 5 3))))
            :to-equalp #(#x55           ; PUSH RBP
                         #x48 #x89 #xE5 ; MOV RBP, RSP
                         #x53)))        ; PUSH RBX
  (it "prologue (no frame pointer): PUSH every SAVE-REGS entry directly, incl. REX.B for R12"
    (expect (%collect-emitted-octets
             (lambda (sink)
               (cl-cc/codegen::emit-x86-64-function-prologue sink nil (list 3 12))))
            :to-equalp #(#x53           ; PUSH RBX
                         #x41 #x54)))   ; PUSH R12 (REX.B needed for code >= 8)
  (it "epilogue (frame-pointer-p): POP the non-RBP saves in reverse, then LEAVE + RET"
    (expect (%collect-emitted-octets
             (lambda (sink)
               (cl-cc/codegen::emit-x86-64-function-epilogue sink t (list 5 3))))
            :to-equalp #(#x5B           ; POP RBX
                         #xC9           ; LEAVE
                         #xC3)))        ; RET
  (it "epilogue (no frame pointer): POP every SAVE-REGS entry in reverse, then bare RET"
    (expect (%collect-emitted-octets
             (lambda (sink)
               (cl-cc/codegen::emit-x86-64-function-epilogue sink nil (list 3 12))))
            :to-equalp #(#x41 #x5C      ; POP R12
                         #x5B           ; POP RBX
                         #xC3))))       ; RET

(describe-sequential "x86-64-codegen-emitters.lisp: %native-inst-touches-phys-p / %native-inst-reads-phys-p"
  ;; VM-MOVE defines its DST and uses its SRC (regalloc-defs-uses.lisp).
  ;; TOUCHES-PHYS-P checks defs OR uses; READS-PHYS-P checks uses only --
  ;; so a phys-key matching only the DST register must differ between them.
  (let ((inst (cl-cc/vm:make-vm-move :dst :r0 :src :r1))
        (assignment (make-hash-table :test 'eq)))
    (setf (gethash :r0 assignment) :phys-a
          (gethash :r1 assignment) :phys-b)
    (it "touches-phys-p is T for the DST's phys assignment (via defs), reads-phys-p is NIL for it (defs aren't uses)"
      (expect (and (cl-cc/codegen::%native-inst-touches-phys-p inst :phys-a assignment) t)
              :to-be t)
      (expect (cl-cc/codegen::%native-inst-reads-phys-p inst :phys-a assignment)
              :to-be nil))
    (it "both are T for the SRC's phys assignment (a genuine use)"
      (expect (and (cl-cc/codegen::%native-inst-touches-phys-p inst :phys-b assignment) t)
              :to-be t)
      (expect (and (cl-cc/codegen::%native-inst-reads-phys-p inst :phys-b assignment) t)
              :to-be t))
    (it "both are NIL for a phys-key neither register is assigned to"
      (expect (cl-cc/codegen::%native-inst-touches-phys-p inst :phys-unrelated assignment)
              :to-be nil)
      (expect (cl-cc/codegen::%native-inst-reads-phys-p inst :phys-unrelated assignment)
              :to-be nil))))

(describe-sequential "wasm-trampoline-gc.lisp: wasm-array-reg-record-kind / -kind / -copy-kind"
  (it "record then read round-trips through the same normalization as WASM-NORMALIZE-ARRAY-ELEMENT-KIND"
    (let ((reg-map (cl-cc/codegen::make-wasm-reg-map-for-function 1)))
      (cl-cc/codegen::wasm-array-reg-record-kind reg-map :r0 'single-float)
      (expect (cl-cc/codegen::wasm-array-reg-kind reg-map :r0) :to-be :float)))
  (it "defaults to :eqref for a register with no recorded kind"
    (let ((reg-map (cl-cc/codegen::make-wasm-reg-map-for-function 1)))
      (expect (cl-cc/codegen::wasm-array-reg-kind reg-map :r0) :to-be :eqref)))
  (it "copy-kind propagates a recorded kind from src to dst"
    (let ((reg-map (cl-cc/codegen::make-wasm-reg-map-for-function 2)))
      (cl-cc/codegen::wasm-array-reg-record-kind reg-map :r0 :char)
      (cl-cc/codegen::wasm-array-reg-copy-kind reg-map :r1 :r0)
      (expect (cl-cc/codegen::wasm-array-reg-kind reg-map :r1) :to-be :char)))
  (it "copy-kind CLEARS any existing kind on dst when src has none recorded (does not leave stale data)"
    (let ((reg-map (cl-cc/codegen::make-wasm-reg-map-for-function 2)))
      (cl-cc/codegen::wasm-array-reg-record-kind reg-map :r1 :char)
      (cl-cc/codegen::wasm-array-reg-copy-kind reg-map :r1 :r0)
      (expect (cl-cc/codegen::wasm-array-reg-kind reg-map :r1) :to-be :eqref))))

(describe-sequential "riscv64-codegen.lisp: emit-riscv64-vm-ret / -halt / -move"
  ;; RISCV64-REG has NO :Rn-digit generic fallback (unlike AArch64/x86-64) --
  ;; it only resolves real ABI register keywords (:t0, :a0, ...) via
  ;; *RISCV64-REG-NUMBER*, so fixtures must use those, not :r0-style keys.
  (it "emit-riscv64-vm-ret encodes JALR x0,ra,0 (0x8067) as 4 little-endian bytes"
    (expect (%collect-emitted-octets
             (lambda (sink) (cl-cc/codegen::emit-riscv64-vm-ret
                             (cl-cc/vm:make-vm-ret) sink)))
            :to-equalp #(#x67 #x80 #x00 #x00)))
  (it "emit-riscv64-vm-halt emits ADDI a0,t0,0 when the result register isn't already A0"
    (expect (%collect-emitted-octets
             (lambda (sink) (cl-cc/codegen::emit-riscv64-vm-halt
                             (cl-cc/vm:make-vm-halt :reg :t0) sink)))
            :to-equalp #(#x13 #x85 #x02 #x00)))
  (it "emit-riscv64-vm-halt emits nothing when the result is already in A0"
    (expect (%collect-emitted-octets
             (lambda (sink) (cl-cc/codegen::emit-riscv64-vm-halt
                             (cl-cc/vm:make-vm-halt :reg :a0) sink)))
            :to-equalp #()))
  (it "emit-riscv64-vm-move emits ADDI dst,src,0 when dst and src differ"
    (expect (%collect-emitted-octets
             (lambda (sink) (cl-cc/codegen::emit-riscv64-vm-move
                             (cl-cc/vm:make-vm-move :dst :t1 :src :t0) sink)))
            :to-equalp #(#x13 #x83 #x02 #x00)))
  (it "emit-riscv64-vm-move emits nothing when dst and src are the same register"
    (expect (%collect-emitted-octets
             (lambda (sink) (cl-cc/codegen::emit-riscv64-vm-move
                             (cl-cc/vm:make-vm-move :dst :t0 :src :t0) sink)))
            :to-equalp #())))

(describe-sequential "riscv64-codegen.lisp: emit-riscv64-vm-spill-store / -load"
  ;; *CURRENT-RISCV64-SPILL-BASE-REG* defaults to +RV-FP+ (X8/S0);
  ;; RISCV64-SPILL-SLOT-OFFSET(1) = 0 - 1*8 = -8, a negative S/I-type
  ;; immediate -- covers RISCV-SIGNED-FIELD's two's-complement packing
  ;; with a real negative value, not just the field-packing unit tests.
  (it "emit-riscv64-vm-spill-store encodes SD t0,-8(fp)"
    (expect (%collect-emitted-octets
             (lambda (sink)
               (cl-cc/codegen::emit-riscv64-vm-spill-store
                (cl-cc/regalloc:make-vm-spill-store :src-reg :t0 :slot 1) sink)))
            :to-equalp #(#x23 #x3C #x54 #xFE)))
  (it "emit-riscv64-vm-spill-load encodes LD t1,-8(fp)"
    (expect (%collect-emitted-octets
             (lambda (sink)
               (cl-cc/codegen::emit-riscv64-vm-spill-load
                (cl-cc/regalloc:make-vm-spill-load :dst-reg :t1 :slot 1) sink)))
            :to-equalp #(#x03 #x33 #x84 #xFF))))

(describe-sequential "riscv64-codegen.lisp: emit-riscv64-vm-jump / -jump-zero"
  (it "emit-riscv64-vm-jump encodes JAL x0,+16 for a forward jump"
    (expect (%collect-emitted-octets
             (lambda (sink)
               (cl-cc/codegen::emit-riscv64-vm-jump
                (cl-cc/vm:make-vm-jump :label "L1") sink 0
                (let ((h (make-hash-table :test 'equal)))
                  (setf (gethash "L1" h) 16)
                  h))))
            :to-equalp #(#x6F #x00 #x00 #x01)))
  (it "emit-riscv64-vm-jump-zero encodes BEQ t0,x0,+16 for a forward jump"
    (expect (%collect-emitted-octets
             (lambda (sink)
               (cl-cc/codegen::emit-riscv64-vm-jump-zero
                (cl-cc/vm:make-vm-jump-zero :reg :t0 :label "L1") sink 0
                (let ((h (make-hash-table :test 'equal)))
                  (setf (gethash "L1" h) 16)
                  h))))
            :to-equalp #(#x63 #x88 #x02 #x00))))

(describe-sequential "riscv64-codegen.lisp: emit-riscv64-vm-select (*riscv64-zicond-enabled* branch)"
  ;; Default T: branchless via Zicond CZERO.EQZ/CZERO.NEZ/OR. Disabled:
  ;; falls back to a placeholder ADDI dst,then,0 that ignores cond/else
  ;; entirely -- per the function's own docstring, a known-incomplete
  ;; non-Zicond path, not a real conditional select.
  (it "with Zicond enabled (default): CZERO.EQZ t0,then,cond + CZERO.NEZ dst,else,cond + OR dst,dst,t0"
    (expect (%collect-emitted-octets
             (lambda (sink)
               (cl-cc/codegen::emit-riscv64-vm-select
                (cl-cc/vm:make-vm-select :dst :a0 :cond-reg :t3
                                          :then-reg :t1 :else-reg :t2)
                sink)))
            :to-equalp #(#xB3 #x52 #xC3 #x0F   ; CZERO.EQZ t0, t1, t3
                         #x33 #xF5 #xC3 #x0F   ; CZERO.NEZ a0, t2, t3
                         #x33 #x65 #x55 #x00))) ; OR a0, a0, t0
  (it "with Zicond disabled: emits only the placeholder ADDI dst,then,0"
    (let ((cl-cc/codegen::*riscv64-zicond-enabled* nil))
      (expect (%collect-emitted-octets
               (lambda (sink)
                 (cl-cc/codegen::emit-riscv64-vm-select
                  (cl-cc/vm:make-vm-select :dst :a0 :cond-reg :t3
                                            :then-reg :t1 :else-reg :t2)
                  sink)))
              :to-equalp #(#x13 #x05 #x03 #x00)))))

(describe-sequential "riscv64-codegen.lisp: define-riscv64-binary-emitter family (add/sub/mul/div/rem)"
  ;; Each is a single R-type instruction differing only in funct3/funct7 --
  ;; add/sub share funct3=0 (differing only in funct7's bit 5), mul/div/rem
  ;; share the M-extension's funct7=1 (differing only in funct3).
  (it "emit-riscv64-vm-add encodes ADD a0,t0,t1 (funct3=0, funct7=0)"
    (expect (%collect-emitted-octets
             (lambda (sink) (cl-cc/codegen::emit-riscv64-vm-add
                             (cl-cc/vm:make-vm-add :dst :a0 :lhs :t0 :rhs :t1) sink)))
            :to-equalp #(#x33 #x85 #x62 #x00)))
  (it "emit-riscv64-vm-sub encodes SUB a0,t0,t1 (funct3=0, funct7=0x20)"
    (expect (%collect-emitted-octets
             (lambda (sink) (cl-cc/codegen::emit-riscv64-vm-sub
                             (cl-cc/vm:make-vm-sub :dst :a0 :lhs :t0 :rhs :t1) sink)))
            :to-equalp #(#x33 #x85 #x62 #x40)))
  (it "emit-riscv64-vm-mul encodes MUL a0,t0,t1 (M-extension, funct3=0, funct7=1)"
    (expect (%collect-emitted-octets
             (lambda (sink) (cl-cc/codegen::emit-riscv64-vm-mul
                             (cl-cc/vm:make-vm-mul :dst :a0 :lhs :t0 :rhs :t1) sink)))
            :to-equalp #(#x33 #x85 #x62 #x02)))
  (it "emit-riscv64-vm-div encodes DIV a0,t0,t1 (M-extension, funct3=4, funct7=1)"
    (expect (%collect-emitted-octets
             (lambda (sink) (cl-cc/codegen::emit-riscv64-vm-div
                             (cl-cc/vm:make-vm-div :dst :a0 :lhs :t0 :rhs :t1) sink)))
            :to-equalp #(#x33 #xC5 #x62 #x02)))
  (it "emit-riscv64-vm-rem encodes REM a0,t0,t1 (M-extension, funct3=6, funct7=1)"
    (expect (%collect-emitted-octets
             (lambda (sink) (cl-cc/codegen::emit-riscv64-vm-rem
                             (cl-cc/vm:make-vm-rem :dst :a0 :lhs :t0 :rhs :t1) sink)))
            :to-equalp #(#x33 #xE5 #x62 #x02))))

(describe-sequential "riscv64-codegen.lisp: emit-riscv64-vm-float-add (precision-dispatched)"
  ;; RISCV64-FREG resolves the *separate* FP register file (:fa0/:fa1/...),
  ;; not RISCV64-REG's integer file -- FADD.S/FADD.D share funct3=rm=0,
  ;; differing only in funct7 (0 vs 1), the F/D extension split.
  (it "at :f32 precision: FADD.S fa0,fa1,fa2 (funct7=0)"
    (expect (%collect-emitted-octets
             (lambda (sink)
               (cl-cc/codegen::emit-riscv64-vm-float-add
                (cl-cc/vm:make-vm-float-add :dst :fa0 :lhs :fa1 :rhs :fa2 :precision :f32)
                sink)))
            :to-equalp #(#x53 #x85 #xC5 #x00)))
  (it "at :f64 precision (default): FADD.D fa0,fa1,fa2 (funct7=1)"
    (expect (%collect-emitted-octets
             (lambda (sink)
               (cl-cc/codegen::emit-riscv64-vm-float-add
                (cl-cc/vm:make-vm-float-add :dst :fa0 :lhs :fa1 :rhs :fa2)
                sink)))
            :to-equalp #(#x53 #x85 #xC5 #x02))))

(describe-sequential "riscv64-codegen.lisp: emit-riscv64-vm-float-sub / -mul / -div (default :f64)"
  ;; Same precision-dispatch shape as float-add; only the funct7 differs
  ;; per operation (F/D extension funct7 assignments: SUB=4/5, MUL=8/9,
  ;; DIV=12/13 for single/double).
  (it "emit-riscv64-vm-float-sub encodes FSUB.D fa0,fa1,fa2 (funct7=5)"
    (expect (%collect-emitted-octets
             (lambda (sink)
               (cl-cc/codegen::emit-riscv64-vm-float-sub
                (cl-cc/vm:make-vm-float-sub :dst :fa0 :lhs :fa1 :rhs :fa2) sink)))
            :to-equalp #(#x53 #x85 #xC5 #x0A)))
  (it "emit-riscv64-vm-float-mul encodes FMUL.D fa0,fa1,fa2 (funct7=9)"
    (expect (%collect-emitted-octets
             (lambda (sink)
               (cl-cc/codegen::emit-riscv64-vm-float-mul
                (cl-cc/vm:make-vm-float-mul :dst :fa0 :lhs :fa1 :rhs :fa2) sink)))
            :to-equalp #(#x53 #x85 #xC5 #x12)))
  (it "emit-riscv64-vm-float-div encodes FDIV.D fa0,fa1,fa2 (funct7=13)"
    (expect (%collect-emitted-octets
             (lambda (sink)
               (cl-cc/codegen::emit-riscv64-vm-float-div
                (cl-cc/vm:make-vm-float-div :dst :fa0 :lhs :fa1 :rhs :fa2) sink)))
            :to-equalp #(#x53 #x85 #xC5 #x1A))))

(describe-sequential "x86-64-emit-ops.lisp: emit-vm-neg (define-unary-mov-emitter)"
  (it "emits MOV RAX,RCX then NEG RAX (two's complement negation)"
    (expect (%collect-emitted-octets
             (lambda (sink)
               (cl-cc/codegen::emit-vm-neg
                (cl-cc/vm:make-vm-neg :dst :r0 :src :r1) sink)))
            :to-equalp #(#x48 #x89 #xC8   ; MOV RAX, RCX
                         #x48 #xF7 #xD8)))) ; NEG RAX

(describe-sequential "x86-64-emit-ops-logical.lisp: emit-vm-logbitp"
  ;; PUSH RCX; MOV RCX,lhs (bit position); MOV dst,rhs (integer); SAR
  ;; dst,CL; AND dst,1; POP RCX -- the only x86-64 emitter this session
  ;; needing RCX explicitly for a variable shift count (x86-64 shifts by
  ;; a runtime count always read CL, not any other register).
  (it "emits the PUSH/MOV/MOV/SAR/AND/POP sequence to test bit LHS of integer RHS"
    (expect (%collect-emitted-octets
             (lambda (sink)
               (cl-cc/codegen::emit-vm-logbitp
                (cl-cc/vm:make-vm-logbitp :dst :r0 :lhs :r3 :rhs :r2) sink)))
            :to-equalp #(#x51                  ; PUSH RCX
                         #x48 #x89 #xD9        ; MOV RCX, RBX (lhs, the bit position)
                         #x48 #x89 #xD0        ; MOV RAX, RDX (rhs, the integer)
                         #x48 #xD3 #xF8        ; SAR RAX, CL
                         #x48 #x83 #xE0 #x01   ; AND RAX, 1
                         #x59))))              ; POP RCX

(describe-sequential "x86-64-emit-ops-logical.lisp: emit-vm-logeqv / emit-vm-logtest"
  (it "emit-vm-logeqv emits MOV dst,lhs + XOR dst,rhs + NOT dst (bitwise XNOR)"
    (expect (%collect-emitted-octets
             (lambda (sink)
               (cl-cc/codegen::emit-vm-logeqv
                (cl-cc/vm:make-vm-logeqv :dst :r0 :lhs :r1 :rhs :r2) sink)))
            :to-equalp #(#x48 #x89 #xC8   ; MOV RAX, RCX
                         #x48 #x31 #xD0   ; XOR RAX, RDX
                         #x48 #xF7 #xD0))) ; NOT RAX
  (it "emit-vm-logtest emits MOV dst,lhs + AND dst,rhs + SETNE dst8 + MOVZX dst,dst8"
    (expect (%collect-emitted-octets
             (lambda (sink)
               (cl-cc/codegen::emit-vm-logtest
                (cl-cc/vm:make-vm-logtest :dst :r0 :lhs :r1 :rhs :r2) sink)))
            :to-equalp #(#x48 #x89 #xC8       ; MOV RAX, RCX
                         #x48 #x21 #xD0       ; AND RAX, RDX (sets ZF)
                         #x0F #x95 #xC0       ; SETNE AL
                         #x48 #x0F #xB6 #xC0)))) ; MOVZX RAX, AL

(describe-sequential "isel-core.lisp: %isel-variable-pattern-p pattern-variable detection"
  (it-each ((?x t) (?lhs t) (x nil) (:reg nil) (1 nil))
      "?-prefixed symbols are pattern variables: ~S => ~A"
      (pattern expected)
    (expect (cl-cc/codegen::%isel-variable-pattern-p pattern) :to-be expected)))

(describe-sequential "isel-core.lisp: %isel-tree-op and %isel-tree-children"
  (it "returns the tree's head for a compound tree"
    (expect (cl-cc/codegen::%isel-tree-op '(:add (:reg r1) (:const 2))) :to-be :add))
  (it "returns the atom itself for a leaf atom"
    (expect (cl-cc/codegen::%isel-tree-op :reg) :to-be :reg))
  (it "returns child subtrees for a compound tree"
    (expect (cl-cc/codegen::%isel-tree-children '(:add (:reg r1) (:const 2)))
            :to-equal '((:reg r1) (:const 2))))
  (it "treats :reg/:const/:literal heads as leaves with no children"
    (dolist (leaf '((:reg r1) (:const 2) (:literal "x")))
      (expect (cl-cc/codegen::%isel-tree-children leaf) :to-be nil))))

(describe-sequential "isel-core.lisp: %isel-bind-pattern tree matching"
  ;; Every call seeds bindings with the (:matched . t) sentinel, mirroring
  ;; %ISEL-RULE-MATCH's own call shape: a successful match with zero new
  ;; variable bindings still needs to return non-NIL, distinguishable from
  ;; a failed match (which is also NIL) -- an easy trap to miss reading the
  ;; code cold, so the tests below deliberately exercise it.
  (it "binds a pattern variable to whatever subtree it matches"
    (expect (cl-cc/codegen::%isel-bind-pattern '?x '(:reg r1) '((:matched . t)))
            :to-equal '((?x . (:reg r1)) (:matched . t))))
  (it "requires the same pattern variable to bind consistently across the pattern"
    (expect (cl-cc/codegen::%isel-bind-pattern
             '?x '(:reg r1) '((?x . (:reg r1)) (:matched . t)))
            :to-equal '((?x . (:reg r1)) (:matched . t)))
    (expect (cl-cc/codegen::%isel-bind-pattern
             '?x '(:reg r2) '((?x . (:reg r1)) (:matched . t)))
            :to-be nil))
  (it "matches a compound pattern against a compound tree of the same shape and arity"
    (expect (cl-cc/codegen::%isel-bind-pattern
             '(:add ?a ?b) '(:add (:reg r1) (:const 2)) '((:matched . t)))
            :to-equal '((?b . (:const 2)) (?a . (:reg r1)) (:matched . t))))
  (it "rejects a compound pattern against a tree with a different head or arity"
    (expect (cl-cc/codegen::%isel-bind-pattern
             '(:add ?a ?b) '(:sub (:reg r1) (:const 2)) '((:matched . t)))
            :to-be nil)
    (expect (cl-cc/codegen::%isel-bind-pattern
             '(:add ?a ?b) '(:add (:reg r1)) '((:matched . t)))
            :to-be nil))
  (it "matches an atom pattern only against an identical tree op, preserving bindings"
    (expect (cl-cc/codegen::%isel-bind-pattern :reg :reg '((:matched . t)))
            :to-equal '((:matched . t)))
    (expect (cl-cc/codegen::%isel-bind-pattern :reg :const '((:matched . t)))
            :to-be nil)))

(describe-sequential "isel-core.lisp: %isel-rule-match and %isel-best-rule selection"
  (it "matches a rule when its pattern fits the tree"
    (let ((rule (cl-cc/codegen::make-isel-rule
                 :name :add-rule :target :test-target
                 :pattern '(:add ?a ?b) :result-op :vm-add :cost 1 :size 2)))
      (expect (cl-cc/codegen::%isel-rule-match rule '(:add (:reg r1) (:const 2)))
              :to-be-truthy)
      (expect (cl-cc/codegen::%isel-rule-match rule '(:sub (:reg r1) (:const 2)))
              :to-be nil)))
  (it "prefers the larger tile, then the cheaper one, among matching rules"
    (let* ((small (cl-cc/codegen::make-isel-rule
                   :name :small :target :test-target
                   :pattern '?a :result-op :vm-move :cost 1 :size 1))
           (large-expensive (cl-cc/codegen::make-isel-rule
                              :name :large-expensive :target :test-target
                              :pattern '(:add ?a ?b) :result-op :vm-add :cost 5 :size 2))
           (large-cheap (cl-cc/codegen::make-isel-rule
                         :name :large-cheap :target :test-target
                         :pattern '(:add ?a ?b) :result-op :vm-add :cost 1 :size 2))
           (tree '(:add (:reg r1) (:const 2))))
      (expect (cl-cc/codegen::isel-rule-name
               (cl-cc/codegen::%isel-best-rule tree (list small large-expensive)))
              :to-be :large-expensive)
      (expect (cl-cc/codegen::isel-rule-name
               (cl-cc/codegen::%isel-best-rule tree (list large-expensive large-cheap)))
              :to-be :large-cheap))))

(describe-sequential "isel-core.lisp: isel-maximal-munch tree covering"
  ;; :RULES is passed explicitly rather than via REGISTER-ISEL-RULE, so
  ;; these test-only rules never touch the global *ISEL-RULE-TABLE* real
  ;; targets read from.
  (it "post-order covers a tree: children's tiles first, then the tile that matched the whole subtree"
    (let* ((leaf-rule (cl-cc/codegen::make-isel-rule
                       :name :leaf :target :test-target
                       :pattern '?a :result-op :vm-move :cost 1 :size 1))
           (add-rule (cl-cc/codegen::make-isel-rule
                     :name :add-tile :target :test-target
                     :pattern '(:add ?a ?b) :result-op :vm-add :cost 1 :size 2))
           (tree '(:add (:reg r1) (:const 2)))
           (tiles (cl-cc/codegen::isel-maximal-munch
                   tree :test-target :rules (list leaf-rule add-rule))))
      (expect (mapcar (lambda (tile) (cl-cc/codegen::isel-rule-name (car tile))) tiles)
              :to-equal '(:leaf :leaf :add-tile))))
  (it "signals isel-diagnostic when no rule covers a node"
    (let ((add-rule (cl-cc/codegen::make-isel-rule
                     :name :add-tile :target :test-target
                     :pattern '(:add ?a ?b) :result-op :vm-add :cost 1 :size 2)))
      ;; No leaf rule provided -- the :reg/:const children have nothing to
      ;; cover them with.
      (signals error
        (cl-cc/codegen::isel-maximal-munch
         '(:add (:reg r1) (:const 2)) :test-target :rules (list add-rule))))))

(describe-sequential "isel-core.lisp: %const-mir-type CL-value-to-MIR-type mapping"
  (it-each ((1 :integer) (-5 :integer) (0 :integer)
            (nil :boolean) (t :boolean)
            ("x" :any) (:keyword :any) (1.5 :any) (#\a :any))
      "%const-mir-type maps ~S to ~A"
      (value expected)
    (expect (cl-cc/codegen::%const-mir-type value) :to-be expected)))

(describe-sequential "regalloc-color.lisp: %intervals-overlap-p live-interval interference"
  (it-each ((0 5 3 8 t)     ; genuinely overlapping
            (0 5 6 8 nil)   ; disjoint, b starts after a ends
            (6 8 0 5 nil)   ; disjoint, a starts after b ends
            (0 5 5 8 t)     ; touching at the boundary counts as overlap (<=, not <)
            (0 10 2 4 t))   ; b fully inside a
      "intervals [~A,~A] and [~A,~A] overlap => ~A"
      (a-start a-end b-start b-end expected)
    (expect (cl-cc/regalloc::%intervals-overlap-p
             (cl-cc/regalloc::make-live-interval :start a-start :end a-end)
             (cl-cc/regalloc::make-live-interval :start b-start :end b-end))
            :to-be expected)))

(describe-sequential "regalloc-color.lisp: %vreg< deterministic virtual-register ordering"
  (it-each ((|R1| |R2| t) (|R2| |R1| nil) (|R1| |R1| nil)
            (|A| |B| t) (|B| |A| nil))
      "%vreg< orders ~A before ~A => ~A"
      (a b expected)
    ;; STRING< returns a mismatch index (an integer), not literally T, on a
    ;; true comparison -- normalize to strict T/NIL before comparing, since
    ;; %VREG< is used as a generalized-boolean predicate at its call sites,
    ;; not compared for EQ-ness to T.
    (expect (and (cl-cc/regalloc::%vreg< a b) t) :to-be expected)))

(describe-sequential "regalloc-color.lisp: %graph-nodes and %graph-degree"
  (it "returns interference-graph nodes sorted deterministically by %vreg<"
    (let ((graph (make-hash-table :test 'eq)))
      (setf (gethash '|C| graph) nil
            (gethash '|A| graph) nil
            (gethash '|B| graph) nil)
      (expect (cl-cc/regalloc::%graph-nodes graph) :to-equal '(|A| |B| |C|))))
  (it "returns a node's neighbor count as its degree"
    (let ((graph (make-hash-table :test 'eq)))
      (setf (gethash '|A| graph) (list '|B| '|C|)
            (gethash '|B| graph) (list '|A|))
      (expect (cl-cc/regalloc::%graph-degree graph '|A|) :to-be 2)
      (expect (cl-cc/regalloc::%graph-degree graph '|B|) :to-be 1)
      (expect (cl-cc/regalloc::%graph-degree graph '|Z|) :to-be 0))))

(describe-sequential "regalloc-color.lisp: %spill-weight greedy spill priority"
  (it "sums use-position count plus call-crossing and return-value bonuses"
    (expect (cl-cc/regalloc::%spill-weight
             (cl-cc/regalloc::make-live-interval :use-positions '(1 2 3)))
            :to-be 3)
    (expect (cl-cc/regalloc::%spill-weight
             (cl-cc/regalloc::make-live-interval :use-positions '(1 2 3)
                                                  :crosses-call-p t))
            :to-be 4)
    (expect (cl-cc/regalloc::%spill-weight
             (cl-cc/regalloc::make-live-interval :use-positions '(1 2 3)
                                                  :crosses-call-p t
                                                  :return-value-p t))
            :to-be 5)))

(describe-sequential "regalloc-policy.lisp: %allocation-strategy plist lookup with default"
  (it "prefers :allocator over :register-allocator over the *regalloc-allocation-strategy* default"
    (expect (cl-cc/regalloc::%allocation-strategy '(:allocator :graph-color))
            :to-be :graph-color)
    (expect (cl-cc/regalloc::%allocation-strategy '(:register-allocator :graph-color))
            :to-be :graph-color)
    (expect (cl-cc/regalloc::%allocation-strategy nil)
            :to-be cl-cc/regalloc::*regalloc-allocation-strategy*)))

(describe-sequential "regalloc-policy.lisp: %interval-next-use-after"
  (it "returns the first use position strictly after POSITION"
    (expect (cl-cc/regalloc::%interval-next-use-after
             (cl-cc/regalloc::make-live-interval :use-positions '(2 5 9)) 4)
            :to-be 5))
  (it "returns NIL when no use position is after POSITION"
    (expect (cl-cc/regalloc::%interval-next-use-after
             (cl-cc/regalloc::make-live-interval :use-positions '(2 5 9)) 9)
            :to-be nil)))

(describe-sequential "regalloc-policy.lisp: regalloc-target-fp-registers"
  (it "returns the 16 XMM registers for :x86-64"
    (expect (cl-cc/regalloc::regalloc-target-fp-registers
             (cl-cc/target:find-target :x86-64))
            :to-equal '(:xmm0 :xmm1 :xmm2 :xmm3 :xmm4 :xmm5 :xmm6 :xmm7
                        :xmm8 :xmm9 :xmm10 :xmm11 :xmm12 :xmm13 :xmm14 :xmm15)))
  (it "returns the 32 V registers for :aarch64"
    (expect (cl-cc/regalloc::regalloc-target-fp-registers
             (cl-cc/target:find-target :aarch64))
            :to-equal '(:v0 :v1 :v2 :v3 :v4 :v5 :v6 :v7
                        :v8 :v9 :v10 :v11 :v12 :v13 :v14 :v15
                        :v16 :v17 :v18 :v19 :v20 :v21 :v22 :v23
                        :v24 :v25 :v26 :v27 :v28 :v29 :v30 :v31)))
  (it "falls back to deduped fp-arg-regs + fp-ret-reg for other targets, e.g. :riscv64"
    (expect (cl-cc/regalloc::regalloc-target-fp-registers
             (cl-cc/target:find-target :riscv64))
            :to-equal '(:fa1 :fa2 :fa3 :fa4 :fa5 :fa6 :fa7 :fa0))))

(describe-sequential "regalloc-policy.lisp: regalloc-ml-spill-cost"
  (it "weights each use position by 1 plus 8x its loop depth, summed"
    (expect (cl-cc/regalloc::regalloc-ml-spill-cost
             (cl-cc/regalloc::make-live-interval :use-positions '(1 2 3)))
            :to-be 3))
  (it "looks up loop depth per use position in the supplied table"
    (let ((depths (make-hash-table)))
      (setf (gethash 2 depths) 3)
      (expect (cl-cc/regalloc::regalloc-ml-spill-cost
               (cl-cc/regalloc::make-live-interval :use-positions '(1 2 3))
               depths)
              :to-be 27)))
  (it "adds +2 crosses-call, +4 return-value, -6 remat-const bonuses"
    (expect (cl-cc/regalloc::regalloc-ml-spill-cost
             (cl-cc/regalloc::make-live-interval :use-positions '(1 2 3)
                                                  :crosses-call-p t
                                                  :return-value-p t
                                                  :remat-const t))
            :to-be 3))
  (it "adds -3 for remat-inst on an interval with no uses"
    (expect (cl-cc/regalloc::regalloc-ml-spill-cost
             (cl-cc/regalloc::make-live-interval :remat-inst t))
            :to-be -3)))

(describe-sequential "regalloc-policy.lisp: %return-value-preferred-reg"
  (it "prefers the ABI return register when it is free"
    (expect (cl-cc/regalloc::%return-value-preferred-reg
             (cl-cc/regalloc::make-live-interval :return-value-p t)
             (cl-cc/target:find-target :x86-64)
             '(:rax :rcx))
            :to-be :rax))
  (it "returns NIL when the return register is not in the free set"
    (expect (cl-cc/regalloc::%return-value-preferred-reg
             (cl-cc/regalloc::make-live-interval :return-value-p t)
             (cl-cc/target:find-target :x86-64)
             '(:rcx))
            :to-be nil))
  (it "returns NIL for non-return-value intervals"
    (expect (cl-cc/regalloc::%return-value-preferred-reg
             (cl-cc/regalloc::make-live-interval)
             (cl-cc/target:find-target :x86-64)
             '(:rax))
            :to-be nil))
  (it "uses the FP return register for fp-p intervals"
    (expect (cl-cc/regalloc::%return-value-preferred-reg
             (cl-cc/regalloc::make-live-interval :return-value-p t :fp-p t)
             (cl-cc/target:find-target :x86-64)
             '(:xmm0))
            :to-be :xmm0)))

(describe-sequential "regalloc-policy.lisp: %call-crossing-preferred-reg"
  (it "prefers the first free callee-saved register for call-crossing intervals"
    (expect (cl-cc/regalloc::%call-crossing-preferred-reg
             (cl-cc/regalloc::make-live-interval :crosses-call-p t)
             (cl-cc/target:find-target :x86-64)
             '(:r12 :r14))
            :to-be :r12))
  (it "returns NIL for intervals that do not cross a call"
    (expect (cl-cc/regalloc::%call-crossing-preferred-reg
             (cl-cc/regalloc::make-live-interval)
             (cl-cc/target:find-target :x86-64)
             '(:r12))
            :to-be nil))
  (it "returns NIL for fp-p intervals, even if call-crossing"
    (expect (cl-cc/regalloc::%call-crossing-preferred-reg
             (cl-cc/regalloc::make-live-interval :crosses-call-p t :fp-p t)
             (cl-cc/target:find-target :x86-64)
             '(:r12))
            :to-be nil))
  (it "returns NIL when no callee-saved register is free"
    (expect (cl-cc/regalloc::%call-crossing-preferred-reg
             (cl-cc/regalloc::make-live-interval :crosses-call-p t)
             (cl-cc/target:find-target :x86-64)
             '(:rax))
            :to-be nil)))

(describe-sequential "regalloc-policy.lisp: %param-preferred-reg"
  (it "prefers the ABI arg register matching the parameter index"
    (expect (cl-cc/regalloc::%param-preferred-reg
             (cl-cc/regalloc::make-live-interval :parameter-index 0)
             (cl-cc/target:find-target :x86-64)
             '(:rdi :rsi))
            :to-be :rdi))
  (it "returns NIL when that arg register is not free"
    (expect (cl-cc/regalloc::%param-preferred-reg
             (cl-cc/regalloc::make-live-interval :parameter-index 2)
             (cl-cc/target:find-target :x86-64)
             '(:rdi))
            :to-be nil))
  (it "returns NIL when there is no parameter index"
    (expect (cl-cc/regalloc::%param-preferred-reg
             (cl-cc/regalloc::make-live-interval)
             (cl-cc/target:find-target :x86-64)
             '(:rdi))
            :to-be nil))
  (it "returns NIL when the parameter index is out of the arg-regs range"
    (expect (cl-cc/regalloc::%param-preferred-reg
             (cl-cc/regalloc::make-live-interval :parameter-index 10)
             (cl-cc/target:find-target :x86-64)
             '(:rdi))
            :to-be nil))
  (it "uses the FP arg-regs list for fp-p intervals"
    (expect (cl-cc/regalloc::%param-preferred-reg
             (cl-cc/regalloc::make-live-interval :parameter-index 1 :fp-p t)
             (cl-cc/target:find-target :x86-64)
             '(:xmm1))
            :to-be :xmm1)))

(describe-sequential "regalloc-policy.lisp: %hint-policy-preferred-reg"
  (it "prefers the first free caller-saved register when the policy hints so"
    (let ((cl-cc/regalloc::*current-allocation-policy* '(:prefer-caller-saved-p t)))
      (expect (cl-cc/regalloc::%hint-policy-preferred-reg
               (cl-cc/regalloc::make-live-interval)
               (cl-cc/target:find-target :x86-64)
               '(:rdx :r9))
              :to-be :rdx)))
  (it "returns NIL when the policy does not hint caller-saved preference"
    (let ((cl-cc/regalloc::*current-allocation-policy* nil))
      (expect (cl-cc/regalloc::%hint-policy-preferred-reg
               (cl-cc/regalloc::make-live-interval)
               (cl-cc/target:find-target :x86-64)
               '(:rdx))
              :to-be nil)))
  (it "returns NIL for call-crossing intervals even when the policy hints so"
    (let ((cl-cc/regalloc::*current-allocation-policy* '(:prefer-caller-saved-p t)))
      (expect (cl-cc/regalloc::%hint-policy-preferred-reg
               (cl-cc/regalloc::make-live-interval :crosses-call-p t)
               (cl-cc/target:find-target :x86-64)
               '(:rdx))
              :to-be nil)))
  (it "returns NIL for fp-p intervals even when the policy hints so"
    (let ((cl-cc/regalloc::*current-allocation-policy* '(:prefer-caller-saved-p t)))
      (expect (cl-cc/regalloc::%hint-policy-preferred-reg
               (cl-cc/regalloc::make-live-interval :fp-p t)
               (cl-cc/target:find-target :x86-64)
               '(:rdx))
              :to-be nil))))

(describe-sequential "mlir.lisp: %mlir-downcase-name"
  (it-each ((:foo "foo") (bar "bar") ("Baz" "baz") (42 "42"))
      "%mlir-downcase-name maps ~S to ~S"
      (name expected)
    (expect (cl-cc/emit::%mlir-downcase-name name) :to-equal expected)))

(describe-sequential "mlir.lisp: %mlir-identifier-char-p"
  (it-each ((#\a t) (#\Z t) (#\5 t) (#\_ t) (#\$ t) (#\. t)
            (#\- nil) (#\Space nil) (#\% nil))
      "%mlir-identifier-char-p on ~S => ~A"
      (ch expected)
    ;; ALPHANUMERICP/FIND return generalized booleans (the character
    ;; itself, or an implementation-defined true value for ALPHANUMERICP)
    ;; on success, not literally T -- normalize before comparing.
    (expect (and (cl-cc/emit::%mlir-identifier-char-p ch) t) :to-be expected)))

(describe-sequential "mlir.lisp: %mlir-sanitize-name"
  (it "downcases and passes through a valid identifier unchanged"
    (expect (cl-cc/emit::%mlir-sanitize-name "Valid_Name.1") :to-equal "valid_name.1"))
  (it "replaces invalid characters with underscores"
    (expect (cl-cc/emit::%mlir-sanitize-name "a-b c!d") :to-equal "a_b_c_d"))
  (it "prefixes with FALLBACK when the sanitized name starts with a digit"
    (expect (cl-cc/emit::%mlir-sanitize-name "3abc") :to-equal "clcc_3abc")
    (expect (cl-cc/emit::%mlir-sanitize-name "9xyz" :fallback "f") :to-equal "f_9xyz"))
  (it "prefixes with FALLBACK when the sanitized name is empty"
    (expect (cl-cc/emit::%mlir-sanitize-name "") :to-equal "clcc_")))

(describe-sequential "llvm-ir.lisp: %llvm-string-prefix-p"
  ;; <= and STRING= are both properly boolean-specced (T/NIL, not a
  ;; generalized boolean), unlike FIND/STRING</etc, so no (AND ... T)
  ;; normalization is needed here.
  (it-each (("cl_cc" "cl_cc_foo" t) ("cl_cc" "cl_cc" t)
            ("foo" "cl_cc" nil) ("cl_cc_long" "cl_cc" nil))
      "%llvm-string-prefix-p(~S, ~S) => ~A"
      (prefix string expected)
    (expect (cl-cc/emit::%llvm-string-prefix-p prefix string) :to-be expected)))

(describe-sequential "llvm-ir.lisp: %llvm-downcase-name"
  (it-each ((:foo "foo") (bar "bar") ("Baz" "baz") (42 "42"))
      "%llvm-downcase-name maps ~S to ~S"
      (name expected)
    (expect (cl-cc/emit::%llvm-downcase-name name) :to-equal expected)))

(describe-sequential "llvm-ir.lisp: %llvm-identifier-char-p"
  ;; Differs from CL-CC/EMIT::%MLIR-IDENTIFIER-CHAR-P by ONE character:
  ;; LLVM identifiers also permit a bare hyphen, MLIR's do not. Worth
  ;; pinning explicitly since the two "sibling" sanitizers otherwise read
  ;; as identical and a future edit could accidentally unify them.
  (it-each ((#\a t) (#\Z t) (#\5 t) (#\_ t) (#\$ t) (#\. t) (#\- t)
            (#\Space nil) (#\% nil))
      "%llvm-identifier-char-p on ~S => ~A"
      (ch expected)
    (expect (and (cl-cc/emit::%llvm-identifier-char-p ch) t) :to-be expected)))

(describe-sequential "llvm-ir.lisp: %llvm-sanitize-name"
  (it "downcases and passes through a valid identifier, hyphen included, unchanged"
    (expect (cl-cc/emit::%llvm-sanitize-name "Valid-Name.1") :to-equal "valid-name.1"))
  (it "replaces invalid characters (but not a hyphen) with underscores"
    (expect (cl-cc/emit::%llvm-sanitize-name "a-b c!d") :to-equal "a-b_c_d"))
  (it "prefixes with FALLBACK when the sanitized name starts with a digit"
    (expect (cl-cc/emit::%llvm-sanitize-name "3abc") :to-equal "clcc_3abc"))
  (it "prefixes with FALLBACK when the sanitized name is empty"
    (expect (cl-cc/emit::%llvm-sanitize-name "") :to-equal "clcc_")))

(describe-sequential "stack-maps.lisp: %cg-root-keyword-p and %cg-root-type-p"
  ;; SEARCH (inside %CG-ROOT-KEYWORD-P) returns the match position, a
  ;; generalized boolean, not literally T -- normalized throughout.
  (it-each ((:root t) (:my-root-thing t) (:pointer t) (:pointer-field t)
            (:object t) (:gc-managed t) (:foo nil) ("not-a-keyword" nil) (42 nil))
      "%cg-root-keyword-p on ~S => ~A"
      (value expected)
    (expect (and (cl-cc/codegen::%cg-root-keyword-p value) t) :to-be expected))
  (it-each ((:pointer t) (:object t) (:root t) (:integer nil) (:boolean nil))
      "%cg-root-type-p on ~S => ~A"
      (value expected)
    (expect (and (cl-cc/codegen::%cg-root-type-p value) t) :to-be expected)))

(describe-sequential "stack-maps.lisp: %cg-plist-value"
  (it "returns the value following KEY in PLIST"
    (expect (cl-cc/codegen::%cg-plist-value '(:a 1 :b 2) :b) :to-be 2))
  (it "returns NIL when KEY is absent"
    (expect (cl-cc/codegen::%cg-plist-value '(:a 1 :b 2) :c) :to-be nil))
  (it "returns NIL for a non-list PLIST rather than erroring"
    (expect (cl-cc/codegen::%cg-plist-value 42 :a) :to-be nil)))

(describe-sequential "stack-maps.lisp: %cg-bitmask-for-indexes"
  (it "ORs a 1-bit into the mask for each in-range index"
    (expect (cl-cc/codegen::%cg-bitmask-for-indexes '(0 1 3)) :to-be #b1011))
  (it "silently drops indexes outside [0,62] rather than erroring or wrapping"
    (expect (cl-cc/codegen::%cg-bitmask-for-indexes '(0 63 -1 "x")) :to-be 1))
  (it "returns 0 for an empty index list"
    (expect (cl-cc/codegen::%cg-bitmask-for-indexes '()) :to-be 0)))

(describe-sequential "x86-64-regs.lisp: x86-64-spill-slot-offset"
  (it "returns *current-spill-offset-bias* minus 8*slot"
    (let ((cl-cc/codegen::*current-spill-offset-bias* 16))
      (expect (cl-cc/codegen::x86-64-spill-slot-offset 0) :to-be 16)
      (expect (cl-cc/codegen::x86-64-spill-slot-offset 1) :to-be 8)
      (expect (cl-cc/codegen::x86-64-spill-slot-offset 2) :to-be 0))))

(describe-sequential "x86-64-regs.lisp: x86-64-red-zone-spill-p"
  (it-each ((t 1 t) (t 16 t) (t 17 nil) (t 0 nil) (nil 1 nil))
      "leaf-p=~A spill-count=~A => ~A"
      (leaf-p spill-count expected)
    (expect (cl-cc/codegen::x86-64-red-zone-spill-p leaf-p spill-count) :to-be expected)))

(describe-sequential "x86-64-regs.lisp: %x86-64-normalize-frame-local"
  (it "normalizes plist format (:name n :size s :align a)"
    (expect (cl-cc/codegen::%x86-64-normalize-frame-local '(:name foo :size 8 :align 4))
            :to-equal '(foo 8 4)))
  (it "defaults align to size when absent in plist format"
    (expect (cl-cc/codegen::%x86-64-normalize-frame-local '(:name foo :size 8))
            :to-equal '(foo 8 8)))
  (it "normalizes triple format (name size &optional align)"
    (expect (cl-cc/codegen::%x86-64-normalize-frame-local '(foo 8 4))
            :to-equal '(foo 8 4)))
  (it "defaults align to size in triple format when omitted"
    (expect (cl-cc/codegen::%x86-64-normalize-frame-local '(foo 8))
            :to-equal '(foo 8 8)))
  (it "signals an error for an invalid descriptor"
    (signals error (cl-cc/codegen::%x86-64-normalize-frame-local 42))))

(describe-sequential "x86-64-regs.lisp: %x86-64-align-up"
  (it-each ((10 8 16) (16 8 16) (0 8 0) (5 nil 5) (5 1 5) (5 0 5))
      "align-up(~A, ~A) => ~A"
      (value alignment expected)
    (expect (cl-cc/codegen::%x86-64-align-up value alignment) :to-be expected)))

(describe-sequential "aarch64-codegen-labels.lisp: a64-imm64-size chunked-load instruction count"
  (it-each ((0 1) (#xFFFF 1)
            (#x10000 2) (#xFFFFFFFF 2)
            (#x100000000 3) (#xFFFFFFFFFFFF 3)
            (#x1000000000000 4))
      "a64-imm64-size(#x~16,'0X) => ~A instructions"
      (value expected)
    (expect (cl-cc/codegen::a64-imm64-size value) :to-be expected)))

(describe-sequential "aarch64-codegen-labels.lisp: a64-safe-stack-*-size gates"
  (it "returns 8 bytes when *aarch64-safe-stack-enabled* is true, 0 when false"
    (let ((cl-cc/codegen::*aarch64-safe-stack-enabled* t))
      (expect (cl-cc/codegen::a64-safe-stack-pointer-size) :to-be 8)
      (expect (cl-cc/codegen::a64-safe-stack-prologue-size) :to-be 8)
      (expect (cl-cc/codegen::a64-safe-stack-epilogue-size) :to-be 8))
    (let ((cl-cc/codegen::*aarch64-safe-stack-enabled* nil))
      (expect (cl-cc/codegen::a64-safe-stack-pointer-size) :to-be 0)
      (expect (cl-cc/codegen::a64-safe-stack-prologue-size) :to-be 0)
      (expect (cl-cc/codegen::a64-safe-stack-epilogue-size) :to-be 0))))

(describe-sequential "ppc64-codegen.lisp: %ppc64-u5 5-bit field mask"
  (it-each ((0 0) (31 31) (32 0) (5 5) (-1 31))
      "%ppc64-u5(~A) => ~A"
      (value expected)
    (expect (cl-cc/codegen::%ppc64-u5 value) :to-be expected)))

(describe-sequential "ppc64-codegen.lisp: %ppc64-s16 signed 16-bit D-form immediate"
  (it "returns the two's-complement 16-bit bit pattern for an in-range value"
    (expect (cl-cc/codegen::%ppc64-s16 0) :to-be 0)
    (expect (cl-cc/codegen::%ppc64-s16 32767) :to-be 32767)
    (expect (cl-cc/codegen::%ppc64-s16 -32768) :to-be 32768)
    (expect (cl-cc/codegen::%ppc64-s16 -1) :to-be 65535))
  (it "signals an error outside [-32768,32767]"
    (signals error (cl-cc/codegen::%ppc64-s16 32768))
    (signals error (cl-cc/codegen::%ppc64-s16 -32769))))

(describe-sequential "ppc64-codegen.lisp: %ppc64-branch-disp alignment and range validation"
  (it "returns VALUE unchanged when aligned and in range"
    (expect (cl-cc/codegen::%ppc64-branch-disp 100 16 4) :to-be 100))
  (it "signals an error when VALUE is not a multiple of ALIGNMENT"
    (signals error (cl-cc/codegen::%ppc64-branch-disp 101 16 4)))
  (it "signals an error when VALUE is outside the BITS-wide signed range"
    (signals error (cl-cc/codegen::%ppc64-branch-disp 40000 16 4))))

(describe-sequential "ppc64-codegen.lisp: %ppc64-spr-field split SPR encoding"
  (it-each ((0 0) (31 2031616) (32 2048) (33 67584))
      "%ppc64-spr-field(~A) => ~A"
      (spr expected)
    (expect (cl-cc/codegen::%ppc64-spr-field spr) :to-be expected)))

(describe-sequential "wasm-extract.lisp: entry-label-to-wat-name"
  (it-each (("func_3_entry" "$func_3_entry") ("lambda_7" "$lambda_7") ("" "$"))
      "entry-label-to-wat-name(~S) => ~S"
      (label expected)
    (expect (cl-cc/codegen::entry-label-to-wat-name label) :to-equal expected)))

(describe-sequential "wasm-extract.lisp: %wasm-instruction-pc-index"
  (it "maps each instruction object to its flat position, by EQ identity"
    (let* ((a (list :a)) (b (list :b)) (c (list :c))
           (index (cl-cc/codegen::%wasm-instruction-pc-index (list a b c))))
      (expect (gethash a index) :to-be 0)
      (expect (gethash b index) :to-be 1)
      (expect (gethash c index) :to-be 2)))
  (it "distinguishes EQUAL-but-not-EQ instructions, since it is keyed by EQ identity"
    (let* ((a (list :x)) (a2 (list :x))
           (index (cl-cc/codegen::%wasm-instruction-pc-index (list a a2))))
      (expect (gethash a index) :to-be 0)
      (expect (gethash a2 index) :to-be 1))))

(describe-sequential "post-ra-scheduler.lisp: %post-ra-canonical-phys-reg"
  (it-each ((:eax :rax) (:al :rax) (:r8d :r8) (:ymm3 :xmm3) (:rax :rax) (:xmm5 :xmm5))
      "%post-ra-canonical-phys-reg(~A) => ~A"
      (reg expected)
    (expect (cl-cc/codegen::%post-ra-canonical-phys-reg reg) :to-be expected)))

(describe-sequential "post-ra-scheduler.lisp: %post-ra-reg-intersect-p"
  ;; INTERSECTION returns the shared elements (a generalized boolean), not
  ;; literally T, on a true comparison -- normalized.
  (it-each (((:rax :rbx) (:rbx :rcx) t) ((:rax) (:rbx) nil)
            (nil (:rax) nil) ((:rax) nil nil))
      "intersect ~A ~A => ~A"
      (a b expected)
    (expect (and (cl-cc/codegen::%post-ra-reg-intersect-p a b) t) :to-be expected)))

(describe-sequential "calling-convention.lisp: calling-convention-for-name"
  (it "returns the internal convention for :internal"
    (expect (cl-cc/codegen::calling-convention-for-name :internal)
            :to-be cl-cc/codegen::*internal-calling-convention*))
  (it "returns the external convention for :external or any other name"
    (expect (cl-cc/codegen::calling-convention-for-name :external)
            :to-be cl-cc/codegen::*external-calling-convention*)
    (expect (cl-cc/codegen::calling-convention-for-name :bogus)
            :to-be cl-cc/codegen::*external-calling-convention*)))

(describe-sequential "calling-convention.lisp: calling-convention-internal-p"
  (it "is true for the internal convention, false for the external one"
    (expect (cl-cc/codegen::calling-convention-internal-p
             cl-cc/codegen::*internal-calling-convention*)
            :to-be t)
    (expect (cl-cc/codegen::calling-convention-internal-p
             cl-cc/codegen::*external-calling-convention*)
            :to-be nil)))

(describe-sequential "calling-convention.lisp: calling-convention-target-value"
  ;; Reads real per-target data off the live *INTERNAL-CALLING-CONVENTION*
  ;; against a real CL-CC/TARGET:FIND-TARGET object, rather than a
  ;; synthetic fixture.
  (it "returns the internal convention's real x86-64 arg-regs list"
    (expect (cl-cc/codegen::calling-convention-target-value
             cl-cc/codegen::*internal-calling-convention*
             (cl-cc/target:find-target :x86-64)
             (function cl-cc/codegen::calling-convention-arg-regs))
            :to-equal '(:rdi :rsi :rdx :rcx :r8 :r9 :r10)))
  (it "returns NIL for the external convention, which carries no per-target override data"
    (expect (cl-cc/codegen::calling-convention-target-value
             cl-cc/codegen::*external-calling-convention*
             (cl-cc/target:find-target :x86-64)
             (function cl-cc/codegen::calling-convention-arg-regs))
            :to-be nil)))

(describe-sequential "ebpf.lisp: ebpf-target-flag-p"
  (it-each ((:ebpf t) ("--target=ebpf" t) ("ebpf" t)
            (:x86-64 nil) ("bogus" nil) (42 nil))
      "ebpf-target-flag-p(~S) => ~A"
      (target expected)
    (expect (cl-cc/emit::ebpf-target-flag-p target) :to-be expected)))

(describe-sequential "ebpf.lisp: %u8/%u16/%u32 truncation"
  (it "masks to 8/16/32 bits respectively"
    (expect (cl-cc/emit::%u8 #x1FF) :to-be #xFF)
    (expect (cl-cc/emit::%u8 5) :to-be 5)
    (expect (cl-cc/emit::%u16 #x1FFFF) :to-be #xFFFF)
    (expect (cl-cc/emit::%u32 #x1FFFFFFFF) :to-be #xFFFFFFFF)))

(describe-sequential "ebpf.lisp: %ebpf-valid-register-p"
  (it-each ((0 t) (10 t) (5 t) (11 nil) (-1 nil) ("r0" nil) (nil nil))
      "%ebpf-valid-register-p(~S) => ~A"
      (reg expected)
    (expect (cl-cc/emit::%ebpf-valid-register-p reg) :to-be expected)))

(describe-sequential "ebpf.lisp: %align-up"
  ;; Unlike CL-CC/CODEGEN::%X86-64-ALIGN-UP, this one has no NIL/<=1
  ;; short-circuit -- it always multiplies. A different, simpler function
  ;; despite the similar name; not the same code under two names.
  (it-each ((10 8 16) (16 8 16) (0 8 0) (1 4 4))
      "align-up(~A,~A) => ~A"
      (value alignment expected)
    (expect (cl-cc/emit::%align-up value alignment) :to-be expected)))

(describe-sequential "ebpf.lisp: %section-name-offsets"
  (it "assigns sequential offsets starting at 1, each name plus its NUL terminator wide"
    (let ((table (cl-cc/emit::%section-name-offsets '("" "foo" "barbaz"))))
      (expect (gethash "" table) :to-be 1)
      (expect (gethash "foo" table) :to-be 2)
      (expect (gethash "barbaz" table) :to-be 6))))

(describe-sequential "wasm-imports.lisp: %wasm-call-string-mentions-p"
  ;; SEARCH returns the match position, a generalized boolean, not
  ;; literally T -- normalized.
  (it-each (("foo" "foobar" t) ("baz" "foobar" nil) ("foo" nil nil) ("" "x" t))
      "mentions(~S, ~S) => ~A"
      (needle string expected)
    (expect (and (cl-cc/codegen::%wasm-call-string-mentions-p needle string) t)
            :to-be expected)))

(describe-sequential "wasm-imports.lisp: %wasm-import-needed-p"
  (it "is always needed when dead-import elimination is disabled"
    (let ((cl-cc/codegen::*wasm-dead-import-elimination-enabled* nil))
      (expect (cl-cc/codegen::%wasm-import-needed-p "host_print_val") :to-be-truthy)))
  (it "is always needed when elimination is enabled but no used-imports set has been tracked"
    (let ((cl-cc/codegen::*wasm-dead-import-elimination-enabled* t)
          (cl-cc/codegen::*wasm-aot-current-used-imports* nil))
      (expect (cl-cc/codegen::%wasm-import-needed-p "host_print_val") :to-be-truthy)))
  (it "is needed only when present in the tracked used-imports set"
    (let ((cl-cc/codegen::*wasm-dead-import-elimination-enabled* t)
          (used (make-hash-table :test 'equal)))
      (setf (gethash "host_print_val" used) t)
      (let ((cl-cc/codegen::*wasm-aot-current-used-imports* used))
        (expect (cl-cc/codegen::%wasm-import-needed-p "host_print_val") :to-be-truthy)
        (expect (cl-cc/codegen::%wasm-import-needed-p "host_other") :to-be nil)))))

(describe-sequential "aarch64.lisp: %aarch64-virtual-register-index"
  (it-each ((:r0 0) (:r10 10) (:r1 1) (:foo 0))
      "%aarch64-virtual-register-index(~A) => ~A"
      (vreg expected)
    (expect (cl-cc/codegen::%aarch64-virtual-register-index vreg) :to-be expected)))

(describe-sequential "aarch64.lisp: %aarch64-register-from-pool"
  ;; Reads the real, live *AARCH64-REGISTER-POOL* (18 caller-saved
  ;; registers x0..x17), not a synthetic fixture.
  (it "returns the pool's register name string for an in-range index"
    (expect (cl-cc/codegen::%aarch64-register-from-pool 0) :to-equal "x0")
    (expect (cl-cc/codegen::%aarch64-register-from-pool 17) :to-equal "x17"))
  (it "returns NIL for an out-of-pool index"
    (expect (cl-cc/codegen::%aarch64-register-from-pool 18) :to-be nil)))

(describe-sequential "aarch64.lisp: %aarch64-vm-register-p"
  ;; MEMBER returns the matching tail (a generalized boolean), not
  ;; literally T -- normalized.
  (it-each ((:r0 t) (:r7 t) (:r8 nil) (:foo nil) ("r0" nil) (42 nil))
      "%aarch64-vm-register-p(~S) => ~A"
      (x expected)
    (expect (and (cl-cc/codegen::%aarch64-vm-register-p x) t) :to-be expected)))

(describe-sequential "wasm-threads.lisp: %wasm-encode-u32-leb128"
  ;; Known reference encodings (WebAssembly/DWARF spec examples).
  (it-each ((0 #(0)) (127 #(127)) (128 #(128 1)) (300 #(172 2)))
      "u32-leb128(~A) => ~A"
      (value expected)
    (expect (cl-cc/emit::%wasm-encode-u32-leb128 value) :to-equalp expected)))

(describe-sequential "wasm-threads.lisp: %wasm-encode-s32-leb128"
  (it-each ((0 #(0)) (-1 #(127)) (64 #(192 0)) (-64 #(64)))
      "s32-leb128(~A) => ~A"
      (value expected)
    (expect (cl-cc/emit::%wasm-encode-s32-leb128 value) :to-equalp expected)))

(describe-sequential "wasm-threads.lisp: %wasm-encode-s64-leb128"
  (it-each ((0 #(0)) (-1 #(127)) (64 #(192 0)))
      "s64-leb128(~A) => ~A"
      (value expected)
    (expect (cl-cc/emit::%wasm-encode-s64-leb128 value) :to-equalp expected)))

(describe-sequential "riscv64-codegen.lisp: encode-rv-r R-type field packing"
  ;; Each field isolated to one nonzero argument at a time -- independently
  ;; hand-computed literal integers (not (ash ...) forms), so the test
  ;; can't accidentally reproduce a wrong shift amount from the code under
  ;; test.
  (it "packs OPCODE unshifted into bits 0-6"
    (expect (cl-cc/codegen::encode-rv-r #x33 0 0 0 0 0) :to-be 51))
  (it "packs RD, masked to 5 bits, at bit 7"
    (expect (cl-cc/codegen::encode-rv-r 0 1 0 0 0 0) :to-be 128)
    (expect (cl-cc/codegen::encode-rv-r 0 32 0 0 0 0) :to-be 0))
  (it "packs FUNCT3, masked to 3 bits, at bit 12"
    (expect (cl-cc/codegen::encode-rv-r 0 0 1 0 0 0) :to-be 4096))
  (it "packs RS1, masked to 5 bits, at bit 15"
    (expect (cl-cc/codegen::encode-rv-r 0 0 0 1 0 0) :to-be 32768))
  (it "packs RS2, masked to 5 bits, at bit 20"
    (expect (cl-cc/codegen::encode-rv-r 0 0 0 0 1 0) :to-be 1048576))
  (it "packs FUNCT7, masked to 7 bits, at bit 25"
    (expect (cl-cc/codegen::encode-rv-r 0 0 0 0 0 1) :to-be 33554432))
  (it "combines all fields without overlap for a real ADD x1, x2, x3 encoding"
    (expect (cl-cc/codegen::encode-rv-r #x33 1 0 2 3 0) :to-be 3211443)))

(describe-sequential "riscv64-codegen.lisp: riscv-signed-field"
  (it-each ((1 12 1) (-1 12 4095) (-2048 12 2048) (0 12 0))
      "riscv-signed-field(~A, ~A) => ~A"
      (value bits expected)
    (expect (cl-cc/codegen::riscv-signed-field value bits) :to-be expected)))

(describe-sequential "riscv64-codegen.lisp: riscv-check-signed"
  (it "returns VALUE unchanged when it fits the signed BITS-wide range"
    (expect (cl-cc/codegen::riscv-check-signed 2047 12 "test") :to-be 2047)
    (expect (cl-cc/codegen::riscv-check-signed -2048 12 "test") :to-be -2048))
  (it "signals an error one past either boundary"
    (signals error (cl-cc/codegen::riscv-check-signed 2048 12 "test"))
    (signals error (cl-cc/codegen::riscv-check-signed -2049 12 "test"))))

(describe-sequential "riscv64-codegen.lisp: riscv-check-branch-aligned"
  (it "returns OFFSET unchanged when 2-byte aligned"
    (expect (cl-cc/codegen::riscv-check-branch-aligned 4 "test") :to-be 4)
    (expect (cl-cc/codegen::riscv-check-branch-aligned 0 "test") :to-be 0))
  (it "signals an error for an odd (unaligned) offset"
    (signals error (cl-cc/codegen::riscv-check-branch-aligned 3 "test"))))

(describe-sequential "riscv64-codegen.lisp: encode-rv-i I-type field packing"
  (it "combines all fields for a real ADDI x1, x2, 100 encoding"
    (expect (cl-cc/codegen::encode-rv-i #x13 1 0 2 100) :to-be 104923283))
  (it "signals an error when the immediate does not fit signed 12 bits"
    (signals error (cl-cc/codegen::encode-rv-i #x13 1 0 2 2048))))

(describe-sequential "riscv64-codegen.lisp: encode-rv-u U-type field packing"
  ;; Expected values written as hex literals, computed by direct
  ;; concatenation (no digit overlap between OPCODE|RD and the masked
  ;; IMM), not decimal addition -- lower arithmetic-error risk than the
  ;; encode-rv-r/rv-i tests' hand-summed decimal integers.
  (it "packs OPCODE and RD, masking IMM to its upper 20 bits"
    (expect (cl-cc/codegen::encode-rv-u #x37 1 #xABCDE000) :to-be #xABCDE0B7))
  (it "clears IMM's low 12 bits regardless of what garbage they contain"
    (expect (cl-cc/codegen::encode-rv-u #x37 1 #xABCDEFFF) :to-be #xABCDE0B7))
  (it "is all-zero for all-zero inputs"
    (expect (cl-cc/codegen::encode-rv-u 0 0 0) :to-be 0)))

(describe-sequential "riscv64-codegen.lisp: encode-rv-s S-type field packing"
  ;; Each field isolated to one nonzero argument at a time, as with
  ;; encode-rv-r above.
  (it "packs OPCODE unshifted into bits 0-6"
    (expect (cl-cc/codegen::encode-rv-s #x23 0 0 0 0) :to-be 35))
  (it "packs FUNCT3 at bit 12"
    (expect (cl-cc/codegen::encode-rv-s 0 1 0 0 0) :to-be 4096))
  (it "packs RS1 at bit 15"
    (expect (cl-cc/codegen::encode-rv-s 0 0 1 0 0) :to-be 32768))
  (it "packs RS2 at bit 20"
    (expect (cl-cc/codegen::encode-rv-s 0 0 0 1 0) :to-be 1048576))
  (it "packs IMM[4:0] at bit 7"
    (expect (cl-cc/codegen::encode-rv-s 0 0 0 0 1) :to-be 128))
  (it "packs IMM[11:5] at bit 25"
    (expect (cl-cc/codegen::encode-rv-s 0 0 0 0 32) :to-be 33554432))
  (it "signals an error when IMM does not fit signed 12 bits"
    (signals error (cl-cc/codegen::encode-rv-s 0 0 0 0 2048))))

(describe-sequential "riscv64-codegen.lisp: encode-rv-b B-type field packing"
  (it "packs OPCODE unshifted into bits 0-6"
    (expect (cl-cc/codegen::encode-rv-b #x63 0 0 0 0) :to-be 99))
  (it "packs FUNCT3 at bit 12"
    (expect (cl-cc/codegen::encode-rv-b 0 1 0 0 0) :to-be 4096))
  (it "packs RS1 at bit 15"
    (expect (cl-cc/codegen::encode-rv-b 0 0 1 0 0) :to-be 32768))
  (it "packs RS2 at bit 20"
    (expect (cl-cc/codegen::encode-rv-b 0 0 0 1 0) :to-be 1048576))
  (it "packs OFFSET bit 11 at word bit 7"
    (expect (cl-cc/codegen::encode-rv-b 0 0 0 0 2048) :to-be 128))
  (it "packs OFFSET bits[4:1] at word bit 8"
    (expect (cl-cc/codegen::encode-rv-b 0 0 0 0 2) :to-be 256))
  (it "packs OFFSET's sign bit (bit 12 of the 13-bit signed field) at word bit 31"
    (expect (cl-cc/codegen::encode-rv-b 0 0 0 0 -4096) :to-be 2147483648))
  (it "signals an error for an odd (unaligned) offset"
    (signals error (cl-cc/codegen::encode-rv-b 0 0 0 0 1)))
  (it "signals an error when OFFSET does not fit signed 13 bits"
    (signals error (cl-cc/codegen::encode-rv-b 0 0 0 0 4096))))

(describe-sequential "riscv64-codegen.lisp: encode-rv-j J-type field packing"
  ;; Completes the RISC-V R/I/S/B/U/J instruction-format family.
  (it "packs OPCODE unshifted into bits 0-6"
    (expect (cl-cc/codegen::encode-rv-j #x6F 0 0) :to-be 111))
  (it "packs RD at bit 7"
    (expect (cl-cc/codegen::encode-rv-j 0 1 0) :to-be 128))
  (it "packs OFFSET[19:12] at word bit 12"
    (expect (cl-cc/codegen::encode-rv-j 0 0 4096) :to-be 4096))
  (it "packs OFFSET[11] at word bit 20"
    (expect (cl-cc/codegen::encode-rv-j 0 0 2048) :to-be 1048576))
  (it "packs OFFSET[10:1] at word bit 21"
    (expect (cl-cc/codegen::encode-rv-j 0 0 2) :to-be 2097152))
  (it "packs OFFSET's sign bit (bit 20 of the 21-bit signed field) at word bit 31"
    (expect (cl-cc/codegen::encode-rv-j 0 0 -1048576) :to-be 2147483648))
  (it "signals an error for an odd (unaligned) offset"
    (signals error (cl-cc/codegen::encode-rv-j 0 0 1)))
  (it "signals an error when OFFSET does not fit signed 21 bits"
    (signals error (cl-cc/codegen::encode-rv-j 0 0 1048576))))

(describe-sequential "x86-64-encoding.lisp: rex-prefix"
  (it "sets the 0x40 base bit plus one bit per flag, at bits 3/2/1/0"
    (expect (cl-cc/codegen::rex-prefix) :to-be #x40)
    (expect (cl-cc/codegen::rex-prefix :w 1) :to-be #x48)
    (expect (cl-cc/codegen::rex-prefix :r 1) :to-be #x44)
    (expect (cl-cc/codegen::rex-prefix :x 1) :to-be #x42)
    (expect (cl-cc/codegen::rex-prefix :b 1) :to-be #x41)
    (expect (cl-cc/codegen::rex-prefix :w 1 :r 1 :x 1 :b 1) :to-be #x4F)))

(describe-sequential "x86-64-encoding.lisp: modrm"
  (it "packs MOD/REG/RM into bits 6-7/3-5/0-2, each masked to its field width"
    (expect (cl-cc/codegen::modrm 3 0 0) :to-be #xC0)
    (expect (cl-cc/codegen::modrm 0 1 2) :to-be 10)
    (expect (cl-cc/codegen::modrm 7 0 0) :to-be #xC0)))

(describe-sequential "x86-64-encoding.lisp: sib"
  (it "packs SCALE/INDEX/BASE into bits 6-7/3-5/0-2"
    (expect (cl-cc/codegen::sib 0 4 5) :to-be 37)
    (expect (cl-cc/codegen::sib 3 0 0) :to-be #xC0)))

(describe-sequential "x86-64-encoding.lisp: scale->sib-bits"
  (it-each ((1 0) (2 1) (4 2) (8 3))
      "scale->sib-bits(~A) => ~A"
      (scale expected)
    (expect (cl-cc/codegen::scale->sib-bits scale) :to-be expected))
  (it "signals an error for an unsupported scale factor"
    (signals error (cl-cc/codegen::scale->sib-bits 3))))

(describe-sequential "x86-64-encoding.lisp: x86-64-memory-mod"
  (it "uses MOD=0 for a zero offset on a non-RBP/R13 base"
    (expect (cl-cc/codegen::x86-64-memory-mod 0 0) :to-be 0))
  (it "forces MOD=1 (disp8) for RBP/R13 bases even at offset zero"
    (expect (cl-cc/codegen::x86-64-memory-mod 5 0) :to-be 1)
    (expect (cl-cc/codegen::x86-64-memory-mod 13 0) :to-be 1))
  (it "uses MOD=1 when the offset fits a signed byte, MOD=2 otherwise"
    (expect (cl-cc/codegen::x86-64-memory-mod 0 100) :to-be 1)
    (expect (cl-cc/codegen::x86-64-memory-mod 0 127) :to-be 1)
    (expect (cl-cc/codegen::x86-64-memory-mod 0 128) :to-be 2)))

(describe-sequential "x86-64.lisp: %x86-64-vm-register-p"
  ;; MEMBER returns the matching tail (a generalized boolean), not
  ;; literally T -- normalized.
  (it-each ((:r0 t) (:r7 t) (:r8 nil) (:foo nil) ("r0" nil) (42 nil))
      "%x86-64-vm-register-p(~S) => ~A"
      (x expected)
    (expect (and (cl-cc/codegen::%x86-64-vm-register-p x) t) :to-be expected)))

(describe-sequential "x86-64-codegen-helpers.lisp: populate-size-table"
  (it "maps a single type key to its size"
    (let ((ht (cl-cc/codegen::populate-size-table '((vm-add 3)))))
      (expect (gethash 'vm-add ht) :to-be 3)))
  (it "maps every type in a list-of-types entry to the same size"
    (let ((ht (cl-cc/codegen::populate-size-table '(((vm-add vm-sub vm-mul) 3)))))
      (expect (gethash 'vm-add ht) :to-be 3)
      (expect (gethash 'vm-sub ht) :to-be 3)
      (expect (gethash 'vm-mul ht) :to-be 3)))
  (it "combines multiple entries into one table, leaving unlisted keys absent"
    (let ((ht (cl-cc/codegen::populate-size-table '((vm-add 3) ((vm-sub vm-mul) 5)))))
      (expect (gethash 'vm-add ht) :to-be 3)
      (expect (gethash 'vm-sub ht) :to-be 5)
      (expect (gethash 'vm-mul ht) :to-be 5)
      (expect (gethash 'vm-missing ht) :to-be nil))))

(describe-sequential "sanitizer.lisp: sanitizer-enabled-p"
  (it "is true when OPTIONS has :address or :undefined set"
    (expect (cl-cc/codegen::sanitizer-enabled-p
             (cl-cc/codegen::make-sanitizer-options :address t))
            :to-be-truthy)
    (expect (cl-cc/codegen::sanitizer-enabled-p
             (cl-cc/codegen::make-sanitizer-options :undefined t))
            :to-be-truthy))
  (it "is false when OPTIONS has neither :address nor :undefined set"
    (expect (cl-cc/codegen::sanitizer-enabled-p (cl-cc/codegen::make-sanitizer-options))
            :to-be nil))
  (it "is false for an explicit NIL OPTIONS argument (distinct from no argument at all)"
    (expect (cl-cc/codegen::sanitizer-enabled-p nil) :to-be nil))
  (it "falls back to the global *asan/*ubsan* flags when no OPTIONS argument is supplied"
    (let ((cl-cc/codegen::*asan-instrumentation-enabled* t)
          (cl-cc/codegen::*ubsan-instrumentation-enabled* nil))
      (expect (cl-cc/codegen::sanitizer-enabled-p) :to-be-truthy))
    (let ((cl-cc/codegen::*asan-instrumentation-enabled* nil)
          (cl-cc/codegen::*ubsan-instrumentation-enabled* nil))
      (expect (cl-cc/codegen::sanitizer-enabled-p) :to-be nil))))

(describe-sequential "win-cfg.lisp: GuardCF function-id table registry"
  ;; *WIN-CFG-FUNCTION-TABLE* is rebound to a fresh hash table per test via
  ;; LET, so these never touch (or are affected by) the real global table.
  (it "registers, queries, and unregisters a target"
    (let ((cl-cc/codegen::*win-cfg-function-table* (make-hash-table :test #'eq)))
      (expect (cl-cc/codegen::win-cfg-function-registered-p 'my-func) :to-be nil)
      (cl-cc/codegen::win-cfg-register-function 'my-func)
      (expect (cl-cc/codegen::win-cfg-function-registered-p 'my-func) :to-be-truthy)
      (cl-cc/codegen::win-cfg-unregister-function 'my-func)
      (expect (cl-cc/codegen::win-cfg-function-registered-p 'my-func) :to-be nil)))
  (it "registers with an explicit :name distinct from the target"
    (let ((cl-cc/codegen::*win-cfg-function-table* (make-hash-table :test #'eq)))
      (cl-cc/codegen::win-cfg-register-function 'my-func :name 'exported-name)
      (expect (cl-cc/codegen::win-cfg-function-table-entries)
              :to-equal '((my-func . exported-name)))))
  (it "lists all registered entries as (target . name) pairs"
    (let ((cl-cc/codegen::*win-cfg-function-table* (make-hash-table :test #'eq)))
      (cl-cc/codegen::win-cfg-register-function 'a)
      (cl-cc/codegen::win-cfg-register-function 'b)
      (expect (length (cl-cc/codegen::win-cfg-function-table-entries)) :to-be 2))))

(describe-sequential "atomics.lisp: codegen-memory-order"
  (it-each ((nil :seq-cst) (:seq-cst :seq-cst) (:acquire :acquire) (:release :release)
            (:relaxed :relaxed) (:acq-rel :seq-cst))
      "codegen-memory-order(~S) => ~S"
      (order expected)
    (expect (cl-cc/codegen::codegen-memory-order order) :to-be expected))
  (it "signals an error for an invalid memory order"
    (signals error (cl-cc/codegen::codegen-memory-order :bogus))))

(describe-sequential "x86-64-codegen-dispatch.lisp: fits-in-rel8-p"
  (it-each ((0 t) (127 t) (-128 t) (128 nil) (-129 nil))
      "fits-in-rel8-p(~A) => ~A"
      (offset expected)
    (expect (cl-cc/codegen::fits-in-rel8-p offset) :to-be expected)))

(describe-sequential "atomics.lisp: AArch64 atomic instruction encoders"
  ;; Expected values are hex literals computed by direct digit
  ;; concatenation: each base opcode constant's low bits are all zero
  ;; where the register/immediate field is packed, confirmed once by
  ;; reading the base constant's low byte(s) before relying on it across
  ;; every case below.
  (it "encode-a64-dmb-ish is the fixed DMB ISH barrier encoding"
    (expect (cl-cc/codegen::encode-a64-dmb-ish) :to-be #xD5033BBF))
  (it "encode-a64-ldxr packs RT at bits 0-4 and RN at bits 5-9 over its base opcode"
    (expect (cl-cc/codegen::encode-a64-ldxr 0 0) :to-be #xC85F7C00)
    (expect (cl-cc/codegen::encode-a64-ldxr 1 0) :to-be #xC85F7C01)
    (expect (cl-cc/codegen::encode-a64-ldxr 0 1) :to-be #xC85F7C20))
  (it "encode-a64-stxr packs RS at bits 0-4, RN at bits 5-9, RT at bits 16-20"
    (expect (cl-cc/codegen::encode-a64-stxr 0 0 0) :to-be #xC8007C00)
    (expect (cl-cc/codegen::encode-a64-stxr 1 0 0) :to-be #xC8007C01)
    (expect (cl-cc/codegen::encode-a64-stxr 0 1 0) :to-be #xC8017C00)
    (expect (cl-cc/codegen::encode-a64-stxr 0 0 1) :to-be #xC8007C20))
  (it "encode-a64-cbnz packs RN at bits 0-4"
    (expect (cl-cc/codegen::encode-a64-cbnz 0 0) :to-be #xB5000000)
    (expect (cl-cc/codegen::encode-a64-cbnz 1 0) :to-be #xB5000001))
  (it "encode-a64-casal packs RT at bits 0-4, RN at bits 5-9, RS at bits 16-20"
    (expect (cl-cc/codegen::encode-a64-casal 0 0 0) :to-be #xC8E0FC00)
    (expect (cl-cc/codegen::encode-a64-casal 0 1 0) :to-be #xC8E0FC01)))

(describe-sequential "wasm-trampoline-tables.lisp: %make-eq-hash-table"
  ;; Another data/logic-separation helper in the same family as
  ;; POPULATE-SIZE-TABLE: real dispatch tables throughout this codebase
  ;; (*wasm-i64-binop-table* etc.) are declared as literal alists and
  ;; turned into real hash tables by this one function -- it accepts
  ;; either alist entry shape so table authors can pick whichever reads
  ;; more naturally for a given table.
  (it "accepts dotted-pair (key . value) alist entries"
    (let ((ht (cl-cc/codegen::%make-eq-hash-table '((a . 1) (b . 2)))))
      (expect (gethash 'a ht) :to-be 1)
      (expect (gethash 'b ht) :to-be 2)))
  (it "accepts list (key value) alist entries"
    (let ((ht (cl-cc/codegen::%make-eq-hash-table '((a 1) (b 2)))))
      (expect (gethash 'a ht) :to-be 1)
      (expect (gethash 'b ht) :to-be 2)))
  (it "returns an empty table for an empty alist"
    (expect (hash-table-count (cl-cc/codegen::%make-eq-hash-table '())) :to-be 0)))

(describe-sequential "regalloc-defs-uses.lisp: instruction-defs / instruction-uses"
  ;; Real CL-CC/VM instruction instances, not guessed fixtures -- MAKE-VM-*
  ;; keyword args mirror each struct's own slot names exactly (verified by
  ;; reading cl-cc-vm's DEFINE-VM-INSTRUCTION forms directly), the same
  ;; discipline as the pre-existing MAKE-VM-FLOAT-ADD usage above.
  (it "the base vm-instruction catch-all defines and uses nothing"
    (let ((inst (cl-cc/vm:make-vm-instruction)))
      (expect (cl-cc/regalloc:instruction-defs inst) :to-be nil)
      (expect (cl-cc/regalloc:instruction-uses inst) :to-be nil)))
  (it "vm-const defines its dst and uses nothing"
    (let ((inst (cl-cc/vm:make-vm-const :dst :r0 :value 42)))
      (expect (cl-cc/regalloc:instruction-defs inst) :to-equal '(:r0))
      (expect (cl-cc/regalloc:instruction-uses inst) :to-be nil)))
  (it "vm-move defines dst and uses src"
    (let ((inst (cl-cc/vm:make-vm-move :dst :r0 :src :r1)))
      (expect (cl-cc/regalloc:instruction-defs inst) :to-equal '(:r0))
      (expect (cl-cc/regalloc:instruction-uses inst) :to-equal '(:r1))))
  (it "vm-add (a vm-binop) defines dst and uses lhs+rhs, dispatched via the parent class"
    (let ((inst (cl-cc/vm:make-vm-add :dst :r0 :lhs :r1 :rhs :r2)))
      (expect (cl-cc/regalloc:instruction-defs inst) :to-equal '(:r0))
      (expect (cl-cc/regalloc:instruction-uses inst) :to-equal '(:r1 :r2))))
  (it "vm-prefetch uses only whichever of base/index reg is non-NIL"
    (expect (cl-cc/regalloc:instruction-uses
             (cl-cc/vm:make-vm-prefetch :base-reg :r0 :index-reg :r1))
            :to-equal '(:r0 :r1))
    (expect (cl-cc/regalloc:instruction-uses
             (cl-cc/vm:make-vm-prefetch :base-reg :r0 :index-reg nil))
            :to-equal '(:r0))
    (expect (cl-cc/regalloc:instruction-uses
             (cl-cc/vm:make-vm-prefetch :base-reg nil :index-reg nil))
            :to-be nil))
  (it "vm-select defines dst and uses cond/then/else in that order"
    (let ((inst (cl-cc/vm:make-vm-select :dst :r0 :cond-reg :r1
                                          :then-reg :r2 :else-reg :r3)))
      (expect (cl-cc/regalloc:instruction-defs inst) :to-equal '(:r0))
      (expect (cl-cc/regalloc:instruction-uses inst) :to-equal '(:r1 :r2 :r3))))
  (it "vm-call defines dst and uses func consed onto args"
    (let ((inst (cl-cc/vm:make-vm-call :dst :r0 :func :rf :args '(:r1 :r2))))
      (expect (cl-cc/regalloc:instruction-defs inst) :to-equal '(:r0))
      (expect (cl-cc/regalloc:instruction-uses inst) :to-equal '(:rf :r1 :r2))))
  (it "vm-tail-call uses the same func+args as vm-call but defines NOTHING (control never returns)"
    (let ((inst (cl-cc/vm:make-vm-tail-call :dst :r0 :func :rf :args '(:r1 :r2))))
      (expect (cl-cc/regalloc:instruction-defs inst) :to-be nil)
      (expect (cl-cc/regalloc:instruction-uses inst) :to-equal '(:rf :r1 :r2))))
  (it "vm-values-regs uses only whichever of reg0/reg1/reg2 is non-NIL"
    (expect (cl-cc/regalloc:instruction-uses
             (cl-cc/vm:make-vm-values-regs :reg0 :r0 :reg1 nil :reg2 :r2))
            :to-equal '(:r0 :r2))
    (expect (cl-cc/regalloc:instruction-uses
             (cl-cc/vm:make-vm-values-regs :reg0 nil :reg1 nil :reg2 nil))
            :to-be nil)))

(describe-sequential "regalloc-spill.lisp: %regalloc-map-tree"
  (it "maps FN over every leaf of a cons tree, preserving its shape"
    (expect (cl-cc/regalloc::%regalloc-map-tree
             (lambda (x) (if (eq x :a) :z x))
             '(:a (:b . :a) :c))
            :to-equal '(:z (:b . :z) :c))))

(describe-sequential "regalloc-spill.lisp: %split-vreg-at-position"
  (it "returns the vreg of whichever child interval covers POSITION"
    (let ((children (list (cl-cc/regalloc::make-live-interval :vreg :a :start 0 :end 5)
                          (cl-cc/regalloc::make-live-interval :vreg :b :start 6 :end 10))))
      (expect (cl-cc/regalloc::%split-vreg-at-position children 3) :to-be :a)
      (expect (cl-cc/regalloc::%split-vreg-at-position children 6) :to-be :b)
      (expect (cl-cc/regalloc::%split-vreg-at-position children 20) :to-be nil))))

(describe-sequential "regalloc-spill.lisp: %assign-live-range-split-slots"
  (it "assigns sequential 1-based slots to each boundary, in order, and returns the count"
    (let ((boundaries (list (cl-cc/regalloc::make-live-range-split-boundary)
                            (cl-cc/regalloc::make-live-range-split-boundary)
                            (cl-cc/regalloc::make-live-range-split-boundary))))
      (expect (cl-cc/regalloc::%assign-live-range-split-slots boundaries) :to-be 3)
      (expect (mapcar #'cl-cc/regalloc::split-boundary-slot boundaries) :to-equal '(1 2 3))))
  (it "returns 0 for an empty boundary list"
    (expect (cl-cc/regalloc::%assign-live-range-split-slots nil) :to-be 0)))

(describe-sequential "regalloc-spill.lisp: %boundaries-by-position"
  (it "indexes boundaries into lists keyed by KEYFN, most-recently-seen first"
    (let* ((b1 (cl-cc/regalloc::make-live-range-split-boundary :before-position 5))
           (b2 (cl-cc/regalloc::make-live-range-split-boundary :before-position 5))
           (b3 (cl-cc/regalloc::make-live-range-split-boundary :before-position 7))
           (table (cl-cc/regalloc::%boundaries-by-position
                   (list b1 b2 b3) #'cl-cc/regalloc::split-boundary-before-position)))
      (expect (gethash 5 table) :to-equal (list b2 b1))
      (expect (gethash 7 table) :to-equal (list b3))
      (expect (gethash 99 table) :to-be nil))))

(describe-sequential "regalloc-spill.lisp: %regalloc-rematerialize-inst"
  (it "rematerializes a (:const . value) descriptor as a fresh vm-const into SCRATCH"
    (expect (cl-cc/regalloc::%regalloc-rematerialize-inst '(:const 42) :scratch)
            :to-equalp (list (cl-cc/vm:make-vm-const :dst :scratch :value 42))))
  (it "rematerializes a bare literal (integer/symbol/character/string) the same way"
    (expect (cl-cc/regalloc::%regalloc-rematerialize-inst 42 :scratch)
            :to-equalp (list (cl-cc/vm:make-vm-const :dst :scratch :value 42)))
    (expect (cl-cc/regalloc::%regalloc-rematerialize-inst "hi" :scratch)
            :to-equalp (list (cl-cc/vm:make-vm-const :dst :scratch :value "hi"))))
  (it "returns NIL for a value it does not know how to rematerialize, e.g. a float"
    (expect (cl-cc/regalloc::%regalloc-rematerialize-inst 3.14 :scratch) :to-be nil)))

(describe-sequential "regalloc-spill.lisp: %regalloc-reserved-scratch-regs"
  (it "reserves the target's first scratch register for mul-high/div-family x86-64 instructions"
    (expect (cl-cc/regalloc::%regalloc-reserved-scratch-regs
             (cl-cc/vm:make-vm-truncate :dst :r0 :lhs :r1 :rhs :r2)
             (cl-cc/target:find-target :x86-64))
            :to-equal '(:r11)))
  (it "reserves nothing for an instruction outside that family"
    (expect (cl-cc/regalloc::%regalloc-reserved-scratch-regs
             (cl-cc/vm:make-vm-add :dst :r0 :lhs :r1 :rhs :r2)
             (cl-cc/target:find-target :x86-64))
            :to-be nil))
  (it "reserves nothing on non-x86-64 targets, even for a truncate instruction"
    (expect (cl-cc/regalloc::%regalloc-reserved-scratch-regs
             (cl-cc/vm:make-vm-truncate :dst :r0 :lhs :r1 :rhs :r2)
             (cl-cc/target:find-target :aarch64))
            :to-be nil)))

(describe-sequential "regalloc-spill.lisp: %regalloc-scratch-candidates"
  (it "excludes a reserved register (mul-high/div-family) from the GPR pool"
    (expect (and (member :r11 (cl-cc/regalloc::%regalloc-scratch-candidates
                                (cl-cc/target:find-target :x86-64) nil nil nil))
                 t)
            :to-be t)
    (expect (and (member :r11 (cl-cc/regalloc::%regalloc-scratch-candidates
                                (cl-cc/target:find-target :x86-64) nil
                                (cl-cc/vm:make-vm-truncate :dst :r0 :lhs :r1 :rhs :r2) nil))
                 t)
            :to-be nil))
  (it "excludes a register already in USED-PHYS from the GPR pool"
    (expect (and (member :rax (cl-cc/regalloc::%regalloc-scratch-candidates
                                (cl-cc/target:find-target :x86-64) '(:rax) nil nil))
                 t)
            :to-be nil))
  (it "returns the FP register pool, filtered by USED-PHYS, when FP-P is true"
    (expect (cl-cc/regalloc::%regalloc-scratch-candidates
             (cl-cc/target:find-target :x86-64) '(:xmm0 :xmm2) nil t)
            :to-equal (remove-if (lambda (r) (member r '(:xmm0 :xmm2)))
                                  (cl-cc/regalloc::regalloc-target-fp-registers
                                   (cl-cc/target:find-target :x86-64))))))

(describe-sequential "regalloc-allocate.lisp: regalloc-lookup"
  (it "returns the assigned physical register, or NIL if unassigned"
    (let* ((ht (make-hash-table :test 'eq))
           (result (cl-cc/regalloc::make-regalloc-result :assignment ht)))
      (setf (gethash :v1 ht) :rax)
      (expect (cl-cc/regalloc:regalloc-lookup result :v1) :to-be :rax)
      (expect (cl-cc/regalloc:regalloc-lookup result :v2) :to-be nil))))

(describe-sequential "regalloc-allocate.lisp: %lsa-interval-pool / %lsa-set-interval-pool"
  (it "reads and writes the GPR or FP free-register pool by the interval's register class"
    (let ((state (cl-cc/regalloc::make-lsa-state :free-regs '(:rax :rcx)
                                                  :free-fp-regs '(:xmm0 :xmm1))))
      (expect (cl-cc/regalloc::%lsa-interval-pool
               state (cl-cc/regalloc::make-live-interval :fp-p nil))
              :to-equal '(:rax :rcx))
      (expect (cl-cc/regalloc::%lsa-interval-pool
               state (cl-cc/regalloc::make-live-interval :fp-p t))
              :to-equal '(:xmm0 :xmm1))
      (cl-cc/regalloc::%lsa-set-interval-pool
       state (cl-cc/regalloc::make-live-interval :fp-p nil) '(:rdx))
      (expect (cl-cc/regalloc::lsa-free-regs state) :to-equal '(:rdx))
      (cl-cc/regalloc::%lsa-set-interval-pool
       state (cl-cc/regalloc::make-live-interval :fp-p t) '(:xmm2))
      (expect (cl-cc/regalloc::lsa-free-fp-regs state) :to-equal '(:xmm2)))))

(describe-sequential "regalloc-allocate.lisp: %lsa-expire-old"
  (it "removes intervals ending before the new interval starts, freeing their register"
    (let* ((a1 (cl-cc/regalloc::make-live-interval :vreg :a :start 0 :end 5 :phys-reg :rax))
           (a2 (cl-cc/regalloc::make-live-interval :vreg :b :start 0 :end 15 :phys-reg :rcx))
           (new (cl-cc/regalloc::make-live-interval :vreg :c :start 10 :end 20))
           (state (cl-cc/regalloc::make-lsa-state :active (list a1 a2))))
      (cl-cc/regalloc::%lsa-expire-old state new)
      (expect (cl-cc/regalloc::lsa-active state) :to-equal (list a2))
      (expect (cl-cc/regalloc::lsa-free-regs state) :to-equal '(:rax))))
  (it "expires nothing when every active interval still overlaps the new one"
    (let* ((a1 (cl-cc/regalloc::make-live-interval :vreg :a :start 0 :end 15 :phys-reg :rax))
           (new (cl-cc/regalloc::make-live-interval :vreg :b :start 10 :end 20))
           (state (cl-cc/regalloc::make-lsa-state :active (list a1))))
      (cl-cc/regalloc::%lsa-expire-old state new)
      (expect (cl-cc/regalloc::lsa-active state) :to-equal (list a1))
      (expect (cl-cc/regalloc::lsa-free-regs state) :to-be nil))))

(describe-sequential "regalloc-allocate.lisp: %lsa-assign"
  (it "records the physical register on the interval and in the assignment table"
    (let* ((state (cl-cc/regalloc::make-lsa-state))
           (interval (cl-cc/regalloc::make-live-interval :vreg :a :end 10)))
      (cl-cc/regalloc::%lsa-assign state interval :rax)
      (expect (cl-cc/regalloc::interval-phys-reg interval) :to-be :rax)
      (expect (gethash :a (cl-cc/regalloc::lsa-assignment state)) :to-be :rax)
      (expect (cl-cc/regalloc::lsa-active state) :to-equal (list interval))))
  (it "inserts into the active list sorted by interval end, not assignment order"
    (let* ((state (cl-cc/regalloc::make-lsa-state))
           (later (cl-cc/regalloc::make-live-interval :vreg :a :end 20))
           (sooner (cl-cc/regalloc::make-live-interval :vreg :b :end 10)))
      (cl-cc/regalloc::%lsa-assign state later :rax)
      (cl-cc/regalloc::%lsa-assign state sooner :rcx)
      (expect (cl-cc/regalloc::lsa-active state) :to-equal (list sooner later)))))

(describe-sequential "regalloc-color.lisp: %color-build-interference-graph"
  (it "connects intervals whose live ranges overlap, and leaves non-overlapping ones isolated"
    (let* ((a (cl-cc/regalloc::make-live-interval :vreg '|A| :start 0 :end 5))
           (b (cl-cc/regalloc::make-live-interval :vreg '|B| :start 3 :end 8))
           (c (cl-cc/regalloc::make-live-interval :vreg '|C| :start 10 :end 15))
           (graph (cl-cc/regalloc::%color-build-interference-graph (list a b c))))
      (expect (gethash '|A| graph) :to-equal '(|B|))
      (expect (gethash '|B| graph) :to-equal '(|A|))
      (expect (gethash '|C| graph) :to-be nil)
      (expect (nth-value 1 (gethash '|C| graph)) :to-be t))))

(describe-sequential "regalloc-color.lisp: %copy-interference-graph"
  (it "returns a hash table whose neighbor lists are independent of the original"
    (let* ((graph (make-hash-table :test 'eq)))
      (setf (gethash '|A| graph) (list '|B|))
      (let ((copy (cl-cc/regalloc::%copy-interference-graph graph)))
        (push '|C| (gethash '|A| graph))
        (expect (gethash '|A| graph) :to-equal '(|C| |B|))
        (expect (gethash '|A| copy) :to-equal '(|B|))))))

(describe-sequential "regalloc-color.lisp: %graph-remove-node"
  (it "deletes the node and strips it from every neighbor's edge list"
    (let ((graph (make-hash-table :test 'eq)))
      (setf (gethash '|A| graph) (list '|B| '|C|)
            (gethash '|B| graph) (list '|A|)
            (gethash '|C| graph) (list '|A|))
      (cl-cc/regalloc::%graph-remove-node graph '|A|)
      (expect (gethash '|B| graph) :to-be nil)
      (expect (gethash '|C| graph) :to-be nil)
      (expect (nth-value 1 (gethash '|A| graph)) :to-be nil))))

(describe-sequential "regalloc-color.lisp: %color-spill-priority"
  (it "scores use-density (uses / live-range length) plus call-crossing and return-value bonuses"
    (expect (cl-cc/regalloc::%color-spill-priority
             (cl-cc/regalloc::make-live-interval :start 0 :end 10 :use-positions '(1 2 3)))
            :to-be 3/10)
    (expect (cl-cc/regalloc::%color-spill-priority
             (cl-cc/regalloc::make-live-interval :start 0 :end 10 :use-positions '(1 2 3)
                                                  :crosses-call-p t :return-value-p t))
            :to-be 23/10))
  (it "floors the live-range length at 1, so a zero-length interval does not divide by zero"
    (expect (cl-cc/regalloc::%color-spill-priority
             (cl-cc/regalloc::make-live-interval :start 5 :end 5 :use-positions '(1 2)))
            :to-be 2)))

(describe-sequential "regalloc-color.lisp: %interval-map"
  (it "maps vreg to interval, skipping intervals with no vreg"
    (let* ((a (cl-cc/regalloc::make-live-interval :vreg '|A|))
           (b (cl-cc/regalloc::make-live-interval :vreg nil))
           (c (cl-cc/regalloc::make-live-interval :vreg '|C|))
           (map (cl-cc/regalloc::%interval-map (list a b c))))
      (expect (gethash '|A| map) :to-be a)
      (expect (gethash '|C| map) :to-be c)
      (expect (hash-table-count map) :to-be 2))))

(describe-sequential "regalloc-color.lisp: %color-ordered-registers-for-interval"
  (it "moves the interval's preferred register to the front when CC picks one"
    (expect (cl-cc/regalloc::%color-ordered-registers-for-interval
             (cl-cc/regalloc::make-live-interval :return-value-p t)
             (cl-cc/target:find-target :x86-64)
             '(:rcx :rax))
            :to-equal '(:rax :rcx)))
  (it "leaves AVAILABLE-REGS unchanged when the interval has no preference"
    (expect (cl-cc/regalloc::%color-ordered-registers-for-interval
             (cl-cc/regalloc::make-live-interval)
             (cl-cc/target:find-target :x86-64)
             '(:rcx :rax))
            :to-equal '(:rcx :rax)))
  (it "leaves AVAILABLE-REGS unchanged when CC is NIL"
    (expect (cl-cc/regalloc::%color-ordered-registers-for-interval
             (cl-cc/regalloc::make-live-interval :return-value-p t)
             nil
             '(:rcx :rax))
            :to-equal '(:rcx :rax))))

(describe-sequential "regalloc-color.lisp: %color-select-register"
  (it "excludes registers already assigned to a graph neighbor"
    (let ((graph (make-hash-table :test 'eq))
          (assignment (make-hash-table :test 'eq)))
      (setf (gethash '|A| graph) (list '|B|)
            (gethash '|B| assignment) :rax)
      (expect (cl-cc/regalloc::%color-select-register '|A| graph assignment '(:rax :rcx))
              :to-be :rcx)))
  (it "returns the first available register when no neighbor is colored yet"
    (let ((graph (make-hash-table :test 'eq))
          (assignment (make-hash-table :test 'eq)))
      (setf (gethash '|A| graph) (list '|B|))
      (expect (cl-cc/regalloc::%color-select-register '|A| graph assignment '(:rax :rcx))
              :to-be :rax))))

(describe-sequential "regalloc.lisp: build-label-map"
  (it "maps each vm-label's name to its instruction index, ignoring non-label instructions"
    (let ((map (cl-cc/regalloc::build-label-map
                (list (cl-cc/vm:make-vm-label :name 'foo)
                      (cl-cc/vm:make-vm-move :dst :r0 :src :r1)
                      (cl-cc/vm:make-vm-label :name 'bar)))))
      (expect (gethash 'foo map) :to-be 0)
      (expect (gethash 'bar map) :to-be 2)
      (expect (hash-table-count map) :to-be 2))))

(describe-sequential "regalloc.lisp: regalloc-collect-linear-functions"
  (it "groups instructions under the label that precedes them, excluding the label itself"
    (let* ((m1 (cl-cc/vm:make-vm-move :dst :r0 :src :r1))
           (m2 (cl-cc/vm:make-vm-move :dst :r2 :src :r3))
           (table (cl-cc/regalloc::regalloc-collect-linear-functions
                   (list (cl-cc/vm:make-vm-label :name 'foo) m1
                         (cl-cc/vm:make-vm-label :name 'bar) m2))))
      (expect (gethash 'foo table) :to-equal (list m1))
      (expect (gethash 'bar table) :to-equal (list m2)))))

(describe-sequential "regalloc.lisp: regalloc-function-leaf-p"
  (it "is T for a body with no direct, tail, or apply calls"
    (expect (cl-cc/regalloc::regalloc-function-leaf-p
             (list (cl-cc/vm:make-vm-move :dst :r0 :src :r1)))
            :to-be t))
  (it "is NIL when the body contains a vm-call"
    (expect (cl-cc/regalloc::regalloc-function-leaf-p
             (list (cl-cc/vm:make-vm-call :dst :r0 :func :rf :args nil)))
            :to-be nil))
  (it "is NIL when the body contains a vm-tail-call"
    (expect (cl-cc/regalloc::regalloc-function-leaf-p
             (list (cl-cc/vm:make-vm-tail-call :dst :r0 :func :rf :args nil)))
            :to-be nil))
  (it "is NIL when the body contains a vm-apply"
    (expect (cl-cc/regalloc::regalloc-function-leaf-p
             (list (cl-cc/vm:make-vm-apply :dst :r0 :func :rf :args nil :tail-p nil)))
            :to-be nil)))

(describe-sequential "regalloc.lisp: regalloc-build-allocation-policy-from-hints"
  (it "prefers caller-saved registers for a leaf function whose callees are all leaves too"
    (let ((hints (make-hash-table :test 'equal)))
      (setf (gethash 'foo hints) (list :leaf-p t :leaf-callee-chain-p t))
      (expect (cl-cc/regalloc::regalloc-build-allocation-policy-from-hints hints 'foo)
              :to-equal '(:prefer-callee-saved-p nil :prefer-caller-saved-p t))))
  (it "prefers callee-saved registers when the callee chain is not all leaves"
    (let ((hints (make-hash-table :test 'equal)))
      (setf (gethash 'bar hints) (list :leaf-p nil :leaf-callee-chain-p nil))
      (expect (cl-cc/regalloc::regalloc-build-allocation-policy-from-hints hints 'bar)
              :to-equal '(:prefer-callee-saved-p t :prefer-caller-saved-p nil))))
  (it "defaults to the callee-saved-preferring policy when the label has no hints entry"
    (expect (cl-cc/regalloc::regalloc-build-allocation-policy-from-hints nil 'unknown)
            :to-equal '(:prefer-callee-saved-p t :prefer-caller-saved-p nil))))

(describe-sequential "regalloc.lisp: regalloc-register-pressure"
  (it "counts an end-at-I interval as expired before a start-at-I interval begins"
    (expect (cl-cc/regalloc::regalloc-register-pressure
             (list (cl-cc/regalloc::make-live-interval :start 0 :end 5)
                   (cl-cc/regalloc::make-live-interval :start 6 :end 10))
             :fp-p nil)
            :to-be 1))
  (it "counts overlapping intervals as simultaneously live"
    (expect (cl-cc/regalloc::regalloc-register-pressure
             (list (cl-cc/regalloc::make-live-interval :start 0 :end 10)
                   (cl-cc/regalloc::make-live-interval :start 5 :end 15))
             :fp-p nil)
            :to-be 2))
  (it "only counts intervals in the requested register class"
    (let ((intervals (list (cl-cc/regalloc::make-live-interval :start 0 :end 10 :fp-p nil)
                           (cl-cc/regalloc::make-live-interval :start 0 :end 10 :fp-p t))))
      (expect (cl-cc/regalloc::regalloc-register-pressure intervals :fp-p nil) :to-be 1)
      (expect (cl-cc/regalloc::regalloc-register-pressure intervals :fp-p t) :to-be 1))))

(describe-sequential "wasm-source-map.lisp: %source-map-json-string / %source-map-json-string-array"
  (it "wraps a string in double quotes"
    (expect (cl-cc/emit::%source-map-json-string "hello") :to-equal "\"hello\""))
  (it "treats NIL as the empty string"
    (expect (cl-cc/emit::%source-map-json-string nil) :to-equal "\"\""))
  (it "escapes embedded quotes, backslashes, and control characters"
    (expect (cl-cc/emit::%source-map-json-string "a\"b") :to-equal "\"a\\\"b\"")
    (expect (cl-cc/emit::%source-map-json-string "a\\b") :to-equal "\"a\\\\b\"")
    (expect (cl-cc/emit::%source-map-json-string (format nil "a~%b")) :to-equal "\"a\\nb\""))
  (it "joins a list of strings into a JSON array"
    (expect (cl-cc/emit::%source-map-json-string-array '("a" "b")) :to-equal "[\"a\",\"b\"]")
    (expect (cl-cc/emit::%source-map-json-string-array nil) :to-equal "[]")))

(describe-sequential "wasm-source-map.lisp: %source-map-vlq-signed / source-map-encode-vlq"
  (it "zig-zags negative values to odd, non-negative values to even (Source Map VLQ sign convention)"
    (expect (cl-cc/emit::%source-map-vlq-signed 5) :to-be 10)
    (expect (cl-cc/emit::%source-map-vlq-signed -5) :to-be 11)
    (expect (cl-cc/emit::%source-map-vlq-signed 0) :to-be 0))
  (it-each ((0 "A") (1 "C") (-1 "D") (16 "gB"))
      "source-map-encode-vlq(~A) => ~S"
      (value expected)
    (expect (cl-cc/emit:source-map-encode-vlq value) :to-equal expected)))

(describe-sequential "wasm-source-map.lisp: %source-map-source-index"
  (it "assigns each distinct source a stable, first-seen-order index"
    (let ((sources-ref (list nil))
          (table (make-hash-table :test 'equal)))
      (expect (cl-cc/emit::%source-map-source-index "a.lisp" sources-ref table) :to-be 0)
      (expect (cl-cc/emit::%source-map-source-index "b.lisp" sources-ref table) :to-be 1)
      (expect (cl-cc/emit::%source-map-source-index "a.lisp" sources-ref table) :to-be 0)
      (expect (car sources-ref) :to-equal '("a.lisp" "b.lisp")))))

(describe-sequential "wasm-source-map.lisp: %source-map-normalize-entry"
  (it "encodes each field as a VLQ delta from the previous segment's state"
    (multiple-value-bind (segment next-previous)
        (cl-cc/emit::%source-map-normalize-entry
         '(:offset 5 :source "a.lisp" :line 3 :column 2)
         (list nil) (make-hash-table :test 'equal) '(0 0 0 0))
      (expect segment :to-equal "KAEE")
      (expect next-previous :to-equal '(5 0 2 2)))))

(describe-sequential "wasm-source-map.lisp: source-map-encode-mappings"
  (it "encodes a single entry as one VLQ segment and returns its source list"
    (multiple-value-bind (mappings sources)
        (cl-cc/emit::source-map-encode-mappings
         '((:offset 5 :source "a.lisp" :line 3 :column 2)))
      (expect mappings :to-equal "KAEE")
      (expect sources :to-equal '("a.lisp")))))

(describe-sequential "wasm-source-map.lisp: build-wasm-source-map-v3"
  (it "renders a Source Map v3 JSON document with no entries"
    (expect (cl-cc/emit:build-wasm-source-map-v3 nil :file "myfile")
            :to-equal
            (format nil "{~%  \"version\": 3,~%  \"file\": \"myfile\",~%  \"sourceRoot\": \"\",~%  \"sources\": [],~%  \"names\": [],~%  \"mappings\": \"\"~%}~%"))))

(describe-sequential "wasm-source-map.lisp: wasm-source-map-path"
  (it "appends .map to the Wasm output path"
    (expect (namestring (cl-cc/emit::wasm-source-map-path "/tmp/out.wasm"))
            :to-equal "/tmp/out.wasm.map")))

(describe-sequential "wasm-source-map.lisp: %source-map-symbol-call"
  (it "returns NIL when the package does not exist"
    (expect (cl-cc/emit::%source-map-symbol-call "NO-SUCH-PACKAGE-XYZ" "FOO" 42) :to-be nil))
  (it "returns NIL when the symbol does not exist in an existing package"
    (expect (cl-cc/emit::%source-map-symbol-call "COMMON-LISP" "NO-SUCH-SYMBOL-XYZ" 42) :to-be nil))
  (it "calls the resolved function when both the package and fbound symbol exist"
    (expect (cl-cc/emit::%source-map-symbol-call "COMMON-LISP" "CAR" (cons 1 2)) :to-be 1)))

(describe-sequential "wasm-wasi.lisp: make-wasi-p2-imports"
  (it "defaults to the three stdio imports (stdin/stdout/stderr)"
    (let ((imports (cl-cc/emit:make-wasi-p2-imports)))
      (expect (length imports) :to-be 3)
      (expect (mapcar #'cl-cc/emit::wasi-import-name imports)
              :to-equal '("get-stdin" "get-stdout" "get-stderr"))))
  (it "adds one import per requested capability, in stdio/random/clocks/filesystem order"
    (let ((imports (cl-cc/emit:make-wasi-p2-imports
                     :stdio nil :random t :clocks t :filesystem t)))
      (expect (mapcar #'cl-cc/emit::wasi-import-name imports)
              :to-equal '("get-random-bytes" "now" "get-directories"))))
  (it "returns NIL when no capability is requested"
    (expect (cl-cc/emit:make-wasi-p2-imports :stdio nil) :to-be nil)))

(describe-sequential "wasm-wasi.lisp: wasi-p2-import->wat"
  (it "renders a WAT import stub with the world/interface comment and readable import form"
    (let ((import (cl-cc/emit::make-wasi-import
                   :world "wasi:cli/command@0.2.0"
                   :interface "wasi:cli/stdout@0.2.0"
                   :name "get-stdout")))
      (expect (cl-cc/emit:wasi-p2-import->wat import)
              :to-equal
              (format nil ";; WASI p2 ~A ~A~%(import ~S ~S (func $~A))"
                      "wasi:cli/command@0.2.0" "wasi:cli/stdout@0.2.0"
                      "wasi:cli/stdout@0.2.0" "get-stdout" "get-stdout"))))
  (it "substitutes slashes in the import name with underscores for the WAT function id"
    (let ((import (cl-cc/emit::make-wasi-import :name "wasi/get")))
      (expect (search "$wasi_get" (cl-cc/emit:wasi-p2-import->wat import)) :to-be-truthy))))

(describe-sequential "wasm-wasi.lisp: inject-wasi-p2-imports-into-wat"
  (it "inserts the import payload right after the opening (module when present"
    (let* ((import (cl-cc/emit::make-wasi-import :name "get-stdout"))
           (payload (format nil "~A~%" (cl-cc/emit:wasi-p2-import->wat import))))
      (expect (cl-cc/emit:inject-wasi-p2-imports-into-wat "(module (func))" (list import))
              :to-equal (concatenate 'string "(module" (string #\Newline) payload " (func))"))))
  (it "wraps the WAT in a synthetic (module ...) when no (module form is present"
    (let* ((import (cl-cc/emit::make-wasi-import :name "get-stdout"))
           (payload (format nil "~A~%" (cl-cc/emit:wasi-p2-import->wat import))))
      (expect (cl-cc/emit:inject-wasi-p2-imports-into-wat "no-module-here" (list import))
              :to-equal (concatenate 'string "(module" (string #\Newline)
                                     payload "no-module-here" (string #\Newline) ")")))))

(describe-sequential "wasm-threads.lisp: %wasm-u8"
  (it-each ((255 255) (256 0) (-1 255) (0 0))
      "%wasm-u8(~A) => ~A"
      (value expected)
    (expect (cl-cc/emit::%wasm-u8 value) :to-be expected)))

(describe-sequential "wasm-threads.lisp: %wasm-emit-byte / %wasm-emit-bytes"
  (it "emits to a function sink, masked to 8 bits"
    (let ((bytes nil))
      (cl-cc/emit::%wasm-emit-byte (lambda (b) (push b bytes)) 300)
      (expect bytes :to-equal (list 44))))
  (it "emits to a fill-pointer vector sink"
    (let ((vec (make-array 0 :element-type '(unsigned-byte 8) :adjustable t :fill-pointer 0)))
      (cl-cc/emit::%wasm-emit-byte vec 7)
      (expect (coerce vec 'list) :to-equal '(7))))
  (it "signals an error for an unsupported sink type"
    (signals error (cl-cc/emit::%wasm-emit-byte :not-a-sink 1)))
  (it "emits each byte of a sequence, in order, via %wasm-emit-bytes"
    (let ((bytes nil))
      (cl-cc/emit::%wasm-emit-bytes (lambda (b) (push b bytes)) #(1 2 3))
      (expect (nreverse bytes) :to-equal '(1 2 3)))))

(describe-sequential "wasm-threads.lisp: wasm-threads-flag-enabled-p"
  (it "reads *wasm-threads-enabled* when no ARGS are supplied"
    (let ((cl-cc/emit:*wasm-threads-enabled* t))
      (expect (cl-cc/emit:wasm-threads-flag-enabled-p) :to-be t))
    (let ((cl-cc/emit:*wasm-threads-enabled* nil))
      (expect (cl-cc/emit:wasm-threads-flag-enabled-p) :to-be nil)))
  (it "recognizes the --wasm-threads token when ARGS is supplied"
    (expect (cl-cc/emit:wasm-threads-flag-enabled-p '("--wasm-threads" "--other")) :to-be t)
    (expect (cl-cc/emit:wasm-threads-flag-enabled-p '("--other")) :to-be nil)
    (expect (cl-cc/emit:wasm-threads-flag-enabled-p nil) :to-be nil)))

(describe-sequential "wasm-threads.lisp: wasm-shared-memory-wat"
  (it "renders a shared memory declaration without an export"
    (expect (cl-cc/emit:wasm-shared-memory-wat :min-pages 1 :max-pages 2)
            :to-equal "(memory 1 2 shared)"))
  (it "renders a shared memory declaration with an export name"
    (expect (cl-cc/emit:wasm-shared-memory-wat :min-pages 1 :max-pages 1 :export-name "mem")
            :to-equal "(memory (export \"mem\") 1 1 shared)"))
  (it "signals an error when the maximum is smaller than the minimum"
    (signals error (cl-cc/emit:wasm-shared-memory-wat :min-pages 2 :max-pages 1))))

(describe-sequential "wasm-threads.lisp: wasm-atomic-wat"
  (it "renders the i32-add RMW sequence"
    (expect (cl-cc/emit:wasm-atomic-wat :i32-add :address 4 :value 1)
            :to-equal (format nil "i32.const ~D~%i32.const ~D~%i32.atomic.rmw.add align=4" 4 1)))
  (it "renders the fixed fence instruction, ignoring its unused keyword arguments"
    (expect (cl-cc/emit:wasm-atomic-wat :fence) :to-equal "atomic.fence")))

(describe-sequential "wasm-threads.lisp: wasm-cl-thread-semantic-mapping"
  (it "returns the fixed CL-primitive to Wasm-instruction alist"
    (expect (cl-cc/emit:wasm-cl-thread-semantic-mapping)
            :to-equal '((:shared-heap . "(memory 1 1 shared) exported/imported with SharedArrayBuffer")
                        (:atomic-incf . "i32.atomic.rmw.add")
                        (:compare-and-swap . "i64.atomic.rmw.cmpxchg")
                        (:memory-barrier . "atomic.fence")
                        (:condition-wait . "memory.atomic.wait32")
                        (:condition-notify . "memory.atomic.notify")
                        (:worker-bootstrap . "host Worker instances share the same WebAssembly.Memory")))))

(describe-sequential "wasm-threads.lisp: emit-wasm-fence"
  (it "emits the atomic prefix, the fence opcode as LEB128, then a zero memory-arg byte"
    (expect (%collect-emitted-octets (lambda (sink) (cl-cc/emit:emit-wasm-fence sink)))
            :to-equalp #(#xfe 3 0))))

(describe-sequential "wasm-threads.lisp: emit-wasm-thread-spawn"
  (it "emits the atomic prefix, the thread-spawn opcode, then FUNCIDX as LEB128"
    (expect (%collect-emitted-octets
             (lambda (sink) (cl-cc/emit::emit-wasm-thread-spawn sink 5)))
            :to-equalp #(#xfe 4 5))))

(describe-sequential "wasm-threads.lisp: emit-wasm-shared-memory"
  (it "emits a memory section with one shared, page-limited memory entry"
    (expect (%collect-emitted-octets
             (lambda (sink) (cl-cc/emit:emit-wasm-shared-memory sink 1)))
            :to-equalp #(5 4 1 3 1 1)))
  (it "signals an error when :max-pages is smaller than the initial page count"
    (signals error
      (%collect-emitted-octets
       (lambda (sink) (cl-cc/emit:emit-wasm-shared-memory sink 2 :max-pages 1))))))

(describe-sequential "regalloc-advanced.lisp: %burs-pattern-frontier"
  (it "matches a symbol-leaf pattern against any atomic tree leaf"
    (expect (cl-cc/emit::%burs-pattern-frontier 'reg 'r1) :to-equal '(r1)))
  (it "refuses a symbol-leaf pattern against a non-atomic tree"
    (expect (cl-cc/emit::%burs-pattern-frontier 'reg '(add a b)) :to-be nil))
  (it "matches a cons pattern by operator and arity, collecting each child's frontier"
    (expect (cl-cc/emit::%burs-pattern-frontier '(add reg1 reg2) '(add r1 r2))
            :to-equal '(r1 r2)))
  (it "refuses a cons pattern whose operator does not match the tree's"
    (expect (cl-cc/emit::%burs-pattern-frontier '(add reg1 reg2) '(mul r1 r2)) :to-be nil))
  (it "refuses a cons pattern whose arity does not match the tree's"
    (expect (cl-cc/emit::%burs-pattern-frontier '(add reg1 reg2) '(add r1 r2 r3)) :to-be nil))
  (it "recurses through nested cons patterns, collecting all leaf frontiers in order"
    (expect (cl-cc/emit::%burs-pattern-frontier '(add (load addr) reg) '(add (load a1) r2))
            :to-equal '(a1 r2))))

(describe-sequential "regalloc-advanced.lisp: register-burs-rule"
  (it "pushes a BURS-RULE struct with the given pattern, replacement, and cost"
    (let ((cl-cc/emit:*burs-rules* nil))
      (cl-cc/emit:register-burs-rule '(add reg1 reg2) '(iadd reg1 reg2) 5)
      (expect (length cl-cc/emit:*burs-rules*) :to-be 1)
      (let ((rule (first cl-cc/emit:*burs-rules*)))
        (expect (cl-cc/emit::burs-rule-pattern rule) :to-equal '(add reg1 reg2))
        (expect (cl-cc/emit::burs-rule-replacement rule) :to-equal '(iadd reg1 reg2))
        (expect (cl-cc/emit::burs-rule-cost rule) :to-be 5))))
  (it "defaults cost to 1 when omitted"
    (let ((cl-cc/emit:*burs-rules* nil))
      (cl-cc/emit:register-burs-rule '(sub reg1 reg2) '(isub reg1 reg2))
      (expect (cl-cc/emit::burs-rule-cost (first cl-cc/emit:*burs-rules*)) :to-be 1))))

(describe-sequential "regalloc-advanced.lisp: burs-select-instructions"
  ;; *BURS-RULES* is let-rebound in every case here so these tests never read
  ;; or mutate the real global rule table the production x86-64 rules (and
  ;; cl-cc's own upstream test suite) also use.
  (it "covers a matched cons tree with its rule plus a synthetic terminal rule per leaf"
    (let ((cl-cc/emit:*burs-rules* nil))
      (cl-cc/emit:register-burs-rule '(add reg1 reg2) '(iadd reg1 reg2) 1)
      (multiple-value-bind (rules cost)
          (cl-cc/emit:burs-select-instructions '(add r1 r2))
        (expect (length rules) :to-be 3)
        (expect (eq (third rules) (first cl-cc/emit:*burs-rules*)) :to-be t)
        ;; 2 unmatched leaves at +BURS-TERMINAL-COST+ (1000) each, plus the rule's own cost of 1.
        (expect cost :to-be 2001))))
  (it "signals an error when no registered rule structurally covers the tree"
    (let ((cl-cc/emit:*burs-rules* nil))
      (cl-cc/emit:register-burs-rule '(sub reg1 reg2) '(isub reg1 reg2) 1)
      (signals error (cl-cc/emit:burs-select-instructions '(add r1 r2))))))

(describe-sequential "llvm-ir.lisp: llvm-ir-bridge-capabilities"
  (it "returns the fixed FR-690 capability descriptor plist"
    (expect (cl-cc/emit:llvm-ir-bridge-capabilities)
            :to-equal '(:fr-id :fr-690
                        :format :textual-llvm-ir
                        :input :mir
                        :lowering (:module :function :basic-block :ssa :phi
                                   :const :move :arithmetic :bitwise :compare
                                   :alloca :load :store :call :tail-call :branch :jump :ret)
                        :types (:fixnum :integer :character :boolean :pointer :void)))))

(describe-sequential "llvm-ir.lisp: %llvm-zero-value"
  (it "returns \"null\" for pointer types and \"0\" for every other LLVM type"
    (expect (cl-cc/emit::%llvm-zero-value "ptr") :to-equal "null")
    (expect (cl-cc/emit::%llvm-zero-value "i64") :to-equal "0")
    (expect (cl-cc/emit::%llvm-zero-value "i1") :to-equal "0")))

(describe-sequential "llvm-ir.lisp: %llvm-global-name"
  (it "prefixes the sanitized name with @"
    (expect (cl-cc/emit::%llvm-global-name "my-func") :to-equal "@my-func")
    (expect (cl-cc/emit::%llvm-global-name 'my-func) :to-equal "@my-func")
    (expect (cl-cc/emit::%llvm-global-name "3abc") :to-equal "@fn_3abc")))

(describe-sequential "llvm-ir.lisp: %llvm-next-temp"
  (it "returns a %prefixN name and increments the context's counter each call"
    (let ((ctx (cl-cc/emit::make-llvm-lower-context)))
      (expect (cl-cc/emit::%llvm-next-temp ctx) :to-equal "%tmp0")
      (expect (cl-cc/emit::%llvm-next-temp ctx) :to-equal "%tmp1")
      (expect (cl-cc/emit::%llvm-next-temp ctx "gep") :to-equal "%gep2")
      (expect (cl-cc/emit::llvmctx-temp-counter ctx) :to-be 3))))

(describe-sequential "llvm-ir.lisp: %llvm-call-target-name"
  (it "resolves a symbol operand to its global name"
    (expect (cl-cc/emit::%llvm-call-target-name 'my-func) :to-equal "@my-func"))
  (it "resolves a string operand to its global name"
    (expect (cl-cc/emit::%llvm-call-target-name "some-func") :to-equal "@some-func"))
  (it "falls back to the indirect-call global name for anything else"
    (expect (cl-cc/emit::%llvm-call-target-name 42) :to-equal "@clcc_indirect_call")))

(describe-sequential "llvm-ir.lisp: %llvm-register-declaration"
  (it "records the target's return type and argument types in the context's declaration table"
    (let ((ctx (cl-cc/emit::make-llvm-lower-context)))
      (cl-cc/emit::%llvm-register-declaration ctx "foo" "i64" '("i64" "i64"))
      (expect (gethash "foo" (cl-cc/emit::llvmctx-declarations ctx))
              :to-equal (list "i64" '("i64" "i64"))))))

(describe-sequential "wasm-types.lisp: wasm-encode-u32-leb128"
  (it-each ((5 #(5)) (300 #(172 2)))
      "wasm-encode-u32-leb128(~A) => ~S"
      (value expected)
    (expect (cl-cc/codegen::wasm-encode-u32-leb128 value) :to-equalp expected)))

(describe-sequential "wasm-types.lisp: wasm-encode-simd-op / wasm-encode-op-u32"
  (it "prefixes the SIMD byte before the opcode's LEB128 encoding"
    (expect (cl-cc/codegen::wasm-encode-simd-op 5) :to-equalp #(#xfd 5)))
  (it "prefixes OPCODE before INDEX's LEB128 encoding"
    (expect (cl-cc/codegen::wasm-encode-op-u32 #x99 3) :to-equalp #(#x99 3))))

(describe-sequential "wasm-types.lisp: global/call opcode encoders"
  (it "wasm-encode-global-get is 0x23 + LEB128(globalidx)"
    (expect (cl-cc/codegen::wasm-encode-global-get 7) :to-equalp #(#x23 7)))
  (it "wasm-encode-global-set is 0x24 + LEB128(globalidx)"
    (expect (cl-cc/codegen::wasm-encode-global-set 7) :to-equalp #(#x24 7)))
  (it "wasm-encode-call is 0x10 + LEB128(funcidx), including the multi-byte case"
    (expect (cl-cc/codegen::wasm-encode-call 12) :to-equalp #(#x10 12))
    (expect (cl-cc/codegen::wasm-encode-call 300) :to-equalp #(#x10 172 2)))
  (it "wasm-encode-call-indirect is 0x11 + LEB128(typeidx) + LEB128(tableidx)"
    (expect (cl-cc/codegen::wasm-encode-call-indirect 2 0) :to-equalp #(#x11 2 0))))

(describe-sequential "wasm-types.lisp: GC opcode encoders"
  (it "wasm-encode-gc-op-u32 is the GC prefix + GC-OPCODE + LEB128(typeidx)"
    (expect (cl-cc/codegen::wasm-encode-gc-op-u32 0 5) :to-equalp #(#xfb 0 5)))
  (it "wasm-encode-struct-new uses GC opcode 0"
    (expect (cl-cc/codegen::wasm-encode-struct-new 3) :to-equalp #(#xfb 0 3)))
  (it "wasm-encode-array-new uses GC opcode 6"
    (expect (cl-cc/codegen::wasm-encode-array-new 3) :to-equalp #(#xfb 6 3))))

(describe-sequential "wasm-types.lisp: exception-handling opcode encoders"
  (it "wasm-encode-try is 0x06 + the raw block/tag type byte"
    (expect (cl-cc/codegen::wasm-encode-try #x40) :to-equalp #(6 #x40)))
  (it "wasm-encode-catch is 0x07 + LEB128(tagidx)"
    (expect (cl-cc/codegen::wasm-encode-catch 1) :to-equalp #(7 1)))
  (it "wasm-encode-throw is 0x08 + LEB128(tagidx)"
    (expect (cl-cc/codegen::wasm-encode-throw 2) :to-equalp #(8 2))))

(describe-sequential "wasm-binary-debug.lisp: %wasm-wat-string / %wasm-json-string"
  ;; DEFINE-ESCAPED-STRING-WRITER generates both from one macro, differing only
  ;; in escape tables: WAT uses hex escapes (\0a \0d \09), JSON uses the
  ;; standard symbolic ones (\n \r \t) -- an intentional divergence, not
  ;; copy-paste drift, matching the earlier LLVM/MLIR sanitizer sibling note.
  (it "quotes plain text and treats NIL as empty"
    (expect (cl-cc/codegen::%wasm-wat-string "hello") :to-equal "\"hello\"")
    (expect (cl-cc/codegen::%wasm-wat-string nil) :to-equal "\"\""))
  (it "escapes embedded quotes and backslashes identically in both writers"
    (expect (cl-cc/codegen::%wasm-wat-string "a\"b") :to-equal "\"a\\\"b\"")
    (expect (cl-cc/codegen::%wasm-json-string "a\\b") :to-equal "\"a\\\\b\""))
  (it "escapes newline/return/tab as WAT hex codes"
    (expect (cl-cc/codegen::%wasm-wat-string (format nil "a~%b")) :to-equal "\"a\\0ab\"")
    (expect (cl-cc/codegen::%wasm-wat-string (string #\Tab)) :to-equal "\"\\09\""))
  (it "escapes newline/return/tab as JSON symbolic codes"
    (expect (cl-cc/codegen::%wasm-json-string (format nil "a~%b")) :to-equal "\"a\\nb\"")
    (expect (cl-cc/codegen::%wasm-json-string (string #\Tab)) :to-equal "\"\\t\"")))

(describe-sequential "wasm-binary-debug.lisp: %wasm-byte-vector-wat-string"
  (it "renders each byte as a backslash-prefixed 2-digit uppercase hex escape"
    (expect (cl-cc/codegen::%wasm-byte-vector-wat-string #(0 255 16))
            :to-equal "\"\\00\\FF\\10\"")))

(describe-sequential "wasm-binary-debug.lisp: %emit-wasm-custom-string / %emit-wasm-custom-bytes"
  (it "emits a (@custom NAME TEXT) WAT form with both fields quoted"
    (expect (with-output-to-string (s) (cl-cc/codegen::%emit-wasm-custom-string s "myname" "mytext"))
            :to-equal (format nil "~%  (@custom \"myname\" \"mytext\")")))
  (it "emits a (@custom NAME BYTES) WAT form with bytes as hex escapes"
    (expect (with-output-to-string (s) (cl-cc/codegen::%emit-wasm-custom-bytes s "myname" #(1 2)))
            :to-equal (format nil "~%  (@custom \"myname\" \"\\01\\02\")"))))

(describe-sequential "wasm-emit-instrs.lisp: %wasm-empty-symbol-eqref"
  (it "returns the fixed staged empty-symbol WAT literal"
    (expect (cl-cc/codegen::%wasm-empty-symbol-eqref)
            :to-equal "(struct.new $symbol_t (struct.new $string_t (array.new $bytes_array_t (i32.const 0) (i32.const 0))) (ref.null eq))")))

(describe-sequential "wasm-emit-instrs.lisp: %wasm-float-literal-eqref"
  (it "wraps f64.const in a plain struct.new when frozen-values is disabled"
    (let ((cl-cc/codegen::*wasm-gc-frozen-values-enabled* nil))
      (expect (cl-cc/codegen::%wasm-float-literal-eqref 3.5d0)
              :to-equal "(struct.new $float_t (f64.const 3.5))")))
  (it "wraps f64.const in struct.new_immutable when frozen-values is enabled"
    (let ((cl-cc/codegen::*wasm-gc-frozen-values-enabled* t))
      (expect (cl-cc/codegen::%wasm-float-literal-eqref 3.5d0)
              :to-equal "(struct.new_immutable $float_t (f64.const 3.5))"))))

(describe-sequential "wasm-emit-instrs.lisp: %wasm-symbol-name-string-t-eqref"
  (it "packs each character's code as an i32.const array.new_fixed payload"
    (let ((cl-cc/codegen::*wasm-gc-frozen-values-enabled* nil))
      (expect (cl-cc/codegen::%wasm-symbol-name-string-t-eqref "AB")
              :to-equal "(struct.new $string_t (array.new_fixed $bytes_array_t 2 (i32.const 65) (i32.const 66)))")))
  (it "uses struct.new_immutable when frozen-values is enabled"
    (let ((cl-cc/codegen::*wasm-gc-frozen-values-enabled* t))
      (expect (cl-cc/codegen::%wasm-symbol-name-string-t-eqref "AB")
              :to-equal "(struct.new_immutable $string_t (array.new_fixed $bytes_array_t 2 (i32.const 65) (i32.const 66)))"))))

(describe-sequential "wasm-emit-instrs.lisp: %wasm-symbol-literal-eqref"
  (it "wraps the symbol's name-string payload with a null value cell"
    (let ((cl-cc/codegen::*wasm-gc-frozen-values-enabled* nil))
      (expect (cl-cc/codegen::%wasm-symbol-literal-eqref 'ab)
              :to-equal (format nil "(struct.new $symbol_t ~A (ref.null eq))"
                                (cl-cc/codegen::%wasm-symbol-name-string-t-eqref "AB"))))))

(describe-sequential "wasm-emit-instrs.lisp: %wasm-reg-or-null-eqref"
  ;; NIL is itself a symbol in Common Lisp ((symbolp nil) => T), so it falls
  ;; into the SYMBOLP clause below, not the final T/"(ref.null eq)" fallback --
  ;; despite the function's own docstring grouping "NIL/other literal" together
  ;; as if they shared a branch. Pinning this by an explicit NIL case rather
  ;; than trusting the docstring's phrasing.
  (it "returns the staged empty-symbol eqref for any non-keyword symbol, including NIL"
    (expect (cl-cc/codegen::%wasm-reg-or-null-eqref nil 'ab)
            :to-equal (cl-cc/codegen::%wasm-empty-symbol-eqref))
    (expect (cl-cc/codegen::%wasm-reg-or-null-eqref nil nil)
            :to-equal (cl-cc/codegen::%wasm-empty-symbol-eqref)))
  (it "returns (ref.null eq) for a non-symbol literal, e.g. an integer"
    (expect (cl-cc/codegen::%wasm-reg-or-null-eqref nil 42) :to-equal "(ref.null eq)")))

(describe-sequential "aarch64-codegen-labels.lisp: a64-instruction-size"
  ;; *CURRENT-A64-REGALLOC* and *CURRENT-A64-EPILOGUE-SAVE-PAIRS* both default
  ;; to NIL, so A64-REG falls back to parsing the :Rn keyword's digits directly
  ;; (e.g. :R1 => 1) without needing a real regalloc-result fixture.
  (it "a64-shrink-save/restore pseudo-instructions are always 4 bytes"
    (expect (cl-cc/codegen::a64-instruction-size (cl-cc/codegen::make-a64-shrink-save)) :to-be 4)
    (expect (cl-cc/codegen::a64-instruction-size (cl-cc/codegen::make-a64-shrink-restore)) :to-be 4))
  (it "vm-move is 0 bytes when dst = src, 4 bytes otherwise"
    (expect (cl-cc/codegen::a64-instruction-size
             (cl-cc/vm:make-vm-move :dst :r0 :src :r0))
            :to-be 0)
    (expect (cl-cc/codegen::a64-instruction-size
             (cl-cc/vm:make-vm-move :dst :r0 :src :r1))
            :to-be 4))
  (it "vm-const uses a fixed 8-byte literal-pool load once IMM64-SIZE exceeds 1 chunk"
    (expect (cl-cc/codegen::a64-instruction-size (cl-cc/vm:make-vm-const :dst :r0 :value 0))
            :to-be 4)
    (expect (cl-cc/codegen::a64-instruction-size
             (cl-cc/vm:make-vm-const :dst :r0 :value (ash 1 48)))
            :to-be 8))
  (it "vm-ret is 4 bytes plus 4 per saved callee-saved pair (0 pairs by default)"
    (expect (cl-cc/codegen::a64-instruction-size (cl-cc/vm:make-vm-ret :reg :r0)) :to-be 4))
  (it "vm-prefetch is 8 bytes with an index register, 4 bytes without"
    (expect (cl-cc/codegen::a64-instruction-size
             (cl-cc/vm:make-vm-prefetch :base-reg :r0 :index-reg :r1))
            :to-be 8)
    (expect (cl-cc/codegen::a64-instruction-size
             (cl-cc/vm:make-vm-prefetch :base-reg :r0 :index-reg nil))
            :to-be 4))
  (it "vm-print falls through to the fixed instruction-size table (0 -- print is a no-op here)"
    (expect (cl-cc/codegen::a64-instruction-size (cl-cc/vm:make-vm-print :reg :r0)) :to-be 0)))

(describe-sequential "aarch64-codegen-labels.lisp: build-a64-label-offsets"
  (it "records each label's byte offset from PROLOGUE-SIZE, advancing by each instruction's real size"
    (let ((offsets (cl-cc/codegen::build-a64-label-offsets
                     (list (cl-cc/vm:make-vm-label :name 'start)
                           (cl-cc/vm:make-vm-print :reg :r0)
                           (cl-cc/vm:make-vm-label :name 'mid)
                           (cl-cc/vm:make-vm-move :dst :r0 :src :r1)
                           (cl-cc/vm:make-vm-label :name 'endlbl))
                     8)))
      (expect (gethash 'start offsets) :to-be 8)
      (expect (gethash 'mid offsets) :to-be 8)
      (expect (gethash 'endlbl offsets) :to-be 12))))

(describe-sequential "wasm-ir.lisp: make-empty-wasm-module"
  (it "initializes all 4 lookup tables as fresh, empty hash tables"
    (let ((module (cl-cc/codegen::make-empty-wasm-module)))
      (dolist (accessor (list #'cl-cc/codegen::wasm-module-global-name-table
                               #'cl-cc/codegen::wasm-module-function-label-table
                               #'cl-cc/codegen::wasm-module-type-signature-table
                               #'cl-cc/codegen::wasm-module-tag-name-table))
        (let ((table (funcall accessor module)))
          (expect (hash-table-p table) :to-be t)
          (expect (hash-table-count table) :to-be 0)))
      (expect (cl-cc/codegen::wasm-module-functions module) :to-be nil)
      (expect (cl-cc/codegen::wasm-module-table-size module) :to-be 0))))

(describe-sequential "wasm-ir.lisp: %wasm-normalize-wat-name"
  (it "strips a leading $ when present"
    (expect (cl-cc/codegen::%wasm-normalize-wat-name "$foo") :to-equal "foo"))
  (it "leaves a name with no leading $ unchanged"
    (expect (cl-cc/codegen::%wasm-normalize-wat-name "foo") :to-equal "foo"))
  (it "accepts a symbol, using its symbol-name"
    (expect (cl-cc/codegen::%wasm-normalize-wat-name '|$bar|) :to-equal "bar"))
  (it "leaves an empty string unchanged rather than erroring on CHAR"
    (expect (cl-cc/codegen::%wasm-normalize-wat-name "") :to-equal "")))

(describe-sequential "wasm-ir.lisp: wasm-module-add-function / wasm-module-function-index-for-label"
  (it "assigns the next function index and indexes the function by both WAT and normalized names"
    (let* ((module (cl-cc/codegen::make-empty-wasm-module))
           (func (cl-cc/codegen::make-wasm-function-def :wat-name "$foo")))
      (cl-cc/codegen::wasm-module-add-function module func)
      (expect (cl-cc/codegen::wasm-func-index func) :to-be 0)
      (expect (cl-cc/codegen::wasm-module-functions module) :to-equal (list func))
      (expect (cl-cc/codegen::wasm-module-function-index-for-label module "$foo") :to-be 0)
      (expect (cl-cc/codegen::wasm-module-function-index-for-label module "foo") :to-be 0)
      (expect (cl-cc/codegen::wasm-module-function-index-for-label module "$missing") :to-be nil)))
  (it "assigns sequential indices across multiple functions"
    (let* ((module (cl-cc/codegen::make-empty-wasm-module))
           (f1 (cl-cc/codegen::make-wasm-function-def :wat-name "$a"))
           (f2 (cl-cc/codegen::make-wasm-function-def :wat-name "$b")))
      (cl-cc/codegen::wasm-module-add-function module f1)
      (cl-cc/codegen::wasm-module-add-function module f2)
      (expect (cl-cc/codegen::wasm-func-index f1) :to-be 0)
      (expect (cl-cc/codegen::wasm-func-index f2) :to-be 1))))

(describe-sequential "wasm-ir.lisp: wasm-module-add-global / wasm-module-global-index-for-name"
  (it "assigns the next global index and indexes it by Lisp name via VM-GLOBAL-WAT-NAME"
    (let* ((module (cl-cc/codegen::make-empty-wasm-module))
           (global (cl-cc/codegen::make-wasm-global-def :wat-name "$g_x")))
      (cl-cc/codegen::wasm-module-add-global module global)
      (expect (cl-cc/codegen::wasm-global-def-index global) :to-be 0)
      (expect (cl-cc/codegen::wasm-module-global-index-for-name module 'x) :to-be 0)
      (expect (cl-cc/codegen::wasm-module-global-index-for-name module 'unknown) :to-be nil))))

(describe-sequential "wasm-ir.lisp: wasm-module-add-tag"
  (it "assigns the next tag index and indexes it by WAT name"
    (let* ((module (cl-cc/codegen::make-empty-wasm-module))
           (tag (cl-cc/codegen::make-wasm-tag-def :wat-name "$tag1")))
      (cl-cc/codegen::wasm-module-add-tag module tag)
      (expect (cl-cc/codegen::wasm-tag-def-index tag) :to-be 0)
      (expect (cl-cc/codegen::wasm-module-tags module) :to-equal (list tag))
      (expect (gethash "$tag1" (cl-cc/codegen::wasm-module-tag-name-table module)) :to-be tag))))

(describe-sequential "wasm-ir.lisp: wasm-lisp-name-to-wat-id / vm-global-wat-name"
  (it "downcases and replaces non-alphanumeric, non-underscore characters with underscores"
    (expect (cl-cc/codegen::wasm-lisp-name-to-wat-id 'my-var) :to-equal "my_var")
    (expect (cl-cc/codegen::wasm-lisp-name-to-wat-id "a.b!c") :to-equal "a_b_c"))
  (it "wraps the sanitized id with the $g_ WAT global prefix"
    (expect (cl-cc/codegen::vm-global-wat-name 'my-var) :to-equal "$g_my_var")))

(describe-sequential "wasm-ir.lisp: make-wasm-reg-map-for-function"
  (it "reserves $pc and $tmp locals immediately after PARAM-COUNT params"
    (let ((reg-map (cl-cc/codegen::make-wasm-reg-map-for-function 3)))
      (expect (cl-cc/codegen::wasm-reg-map-pc-index reg-map) :to-be 3)
      (expect (cl-cc/codegen::wasm-reg-map-tmp-index reg-map) :to-be 4)
      (expect (cl-cc/codegen::wasm-reg-map-next-index reg-map) :to-be 5))))

(describe-sequential "wasm-ir.lisp: initialize-wasm-param-locals / wasm-reg-to-local"
  (it "reserves sequential local indices 0..N-1 for the given param registers"
    (let ((reg-map (cl-cc/codegen::make-wasm-reg-map :table (make-hash-table))))
      (cl-cc/codegen::initialize-wasm-param-locals reg-map '(:r0 :r1))
      (expect (cl-cc/codegen::wasm-reg-to-local reg-map :r0) :to-be 0)
      (expect (cl-cc/codegen::wasm-reg-to-local reg-map :r1) :to-be 1)))
  (it "lazily allocates a new local index on first use, then reuses it on later lookups"
    (let ((reg-map (cl-cc/codegen::make-wasm-reg-map :table (make-hash-table) :next-index 0)))
      (expect (cl-cc/codegen::wasm-reg-to-local reg-map :r5) :to-be 0)
      (expect (cl-cc/codegen::wasm-reg-to-local reg-map :r5) :to-be 0)
      (expect (cl-cc/codegen::wasm-reg-to-local reg-map :r6) :to-be 1))))

(describe-sequential "wasm-ir.lisp: wasm-reg-map-eh-tag-index / wasm-reg-map-exnref-index"
  (it "allocate distinct, stable locals for the EH tag payload and exnref capture"
    (let ((reg-map (cl-cc/codegen::make-wasm-reg-map :table (make-hash-table) :next-index 0)))
      (expect (cl-cc/codegen::wasm-reg-map-eh-tag-index reg-map) :to-be 0)
      (expect (cl-cc/codegen::wasm-reg-map-exnref-index reg-map) :to-be 1)
      ;; Calling again must return the SAME index, not allocate a new one.
      (expect (cl-cc/codegen::wasm-reg-map-eh-tag-index reg-map) :to-be 0))))

(describe-sequential "wasm-sections.lisp: emit-wat-globals"
  ;; No feature flags gate this one -- purely a MODULE-GLOBALS walk, unlike
  ;; most of this file's other emit-wat-* functions.
  (it "emits one (global ...) declaration per module global, in WASM-MODULE-GLOBALS order"
    (let* ((module (cl-cc/codegen::make-empty-wasm-module))
           (g1 (cl-cc/codegen::make-wasm-global-def :wat-name "$g_a"))
           (g2 (cl-cc/codegen::make-wasm-global-def :wat-name "$g_b")))
      (cl-cc/codegen::wasm-module-add-global module g1)
      (cl-cc/codegen::wasm-module-add-global module g2)
      ;; WASM-MODULE-ADD-GLOBAL pushes, so WASM-MODULE-GLOBALS lists the most
      ;; recently added global (g2, index 1) first.
      (expect (with-output-to-string (s) (cl-cc/codegen::emit-wat-globals module s))
              :to-equal (format nil "~%  (global $g_b (mut eqref) (ref.null eq)) ;; globalidx 1~%  (global $g_a (mut eqref) (ref.null eq)) ;; globalidx 0")))))

(describe-sequential "wasm-sections.lisp: ensure-wasm-condition-tag! / emit-wat-tags"
  (it "lazily creates $cl_condition_tag once and reuses it on a second call"
    (let ((module (cl-cc/codegen::make-empty-wasm-module)))
      (let ((tag (cl-cc/codegen::ensure-wasm-condition-tag! module)))
        (expect (cl-cc/codegen::wasm-tag-def-wat-name tag) :to-equal "$cl_condition_tag")
        (expect (cl-cc/codegen::wasm-tag-def-params tag) :to-equal '(:eqref :eqref))
        (expect (cl-cc/codegen::wasm-tag-def-index tag) :to-be 0)
        (expect (cl-cc/codegen::ensure-wasm-condition-tag! module) :to-be tag)
        (expect (length (cl-cc/codegen::wasm-module-tags module)) :to-be 1))))
  (it "emits a (tag $cl_condition_tag ...) declaration, plus its export since exception-tag-linking defaults to enabled"
    (let ((module (cl-cc/codegen::make-empty-wasm-module)))
      (expect (with-output-to-string (s) (cl-cc/codegen::emit-wat-tags module s))
              :to-equal (format nil "~%  (tag $cl_condition_tag (param eqref eqref)) ;; tagidx 0~%  (export \"cl_condition_tag\" (tag $cl_condition_tag))")))))

(describe-sequential "wasm-functions.lisp: emit-wat-call-globals"
  (it "emits the header comment plus exactly +WASM-MAX-CALL-ARGS+ (16) argument-passing globals"
    (expect (with-output-to-string (s) (cl-cc/codegen::emit-wat-call-globals s))
            :to-equal
            (with-output-to-string (s)
              (format s "~%  ;; Argument-passing globals (calling convention)")
              (dotimes (i cl-cc/codegen::+wasm-max-call-args+)
                (format s "~%  (global $cl_arg~D (mut eqref) (ref.null eq))" i))))))

(describe-sequential "wasm-functions.lisp: emit-wat-function-locals"
  (it "emits closure-parameter, $pc, and $tmp locals for a reg-map with no VM registers yet"
    (let ((reg-map (cl-cc/codegen::make-wasm-reg-map-for-function 2)))
      (expect (with-output-to-string (s) (cl-cc/codegen::emit-wat-function-locals reg-map s))
              :to-equal
              (format nil "~%    (local eqref) ;; closure parameter local 0~%    (local eqref) ;; closure parameter local 1~%    (local i32) ;; $pc at index 2~%    (local eqref) ;; $tmp at index 3"))))
  (it "emits one additional eqref local per VM register allocated into the reg-map"
    (let ((reg-map (cl-cc/codegen::make-wasm-reg-map-for-function 0)))
      (cl-cc/codegen::wasm-reg-to-local reg-map :r0)
      (cl-cc/codegen::wasm-reg-to-local reg-map :r1)
      (expect (with-output-to-string (s) (cl-cc/codegen::emit-wat-function-locals reg-map s))
              :to-equal
              (format nil "~%    (local i32) ;; $pc at index 0~%    (local eqref) ;; $tmp at index 1~%    (local eqref) ;; VM register local 2~%    (local eqref) ;; VM register local 3")))))

(describe-sequential "wasm-functions.lisp: wasm-bigint-wrapper-name"
  (it "appends _bigint_i64 to the function's WAT name"
    (expect (cl-cc/codegen::wasm-bigint-wrapper-name
             (cl-cc/codegen::make-wasm-function-def :wat-name "$foo"))
            :to-equal "$foo_bigint_i64")))

(describe-sequential "wasm-functions.lisp: emit-wat-bigint-wrappers / emit-wat-bigint-js-wrapper-code"
  ;; *WASM-JS-BIGINT-I64-ENABLED* defaults to NIL (verified via its own
  ;; DEFPARAMETER, not inferred from a sibling flag or docstring -- see
  ;; the wasm-sections.lisp emit-wat-tags lesson above), so both of these
  ;; are no-ops by default.
  (it "emit nothing when the BigInt feature is disabled (the default)"
    (let* ((module (cl-cc/codegen::make-empty-wasm-module))
           (func (cl-cc/codegen::make-wasm-function-def :wat-name "$foo" :exported-p t)))
      (cl-cc/codegen::wasm-module-add-function module func)
      (expect (with-output-to-string (s) (cl-cc/codegen::emit-wat-bigint-wrappers module s))
              :to-equal "")
      (expect (with-output-to-string (s) (cl-cc/codegen::emit-wat-bigint-js-wrapper-code s))
              :to-equal ""))))

(describe-sequential "x86-64-eh.lisp: normalize-x86-64-eh-model"
  (it-each ((nil :sjlj) (:sjlj :sjlj) (:table :table)
            ("sjlj" :sjlj) ("SETJMP" :sjlj) ("setjmp-longjmp" :sjlj)
            ("table" :table) ("zero-cost" :table) ("DWARF" :table) ("itanium" :table))
      "normalize-x86-64-eh-model(~S) => ~S"
      (model expected)
    (expect (cl-cc/codegen:normalize-x86-64-eh-model model) :to-be expected))
  (it "signals an error for an unrecognized string"
    (signals error (cl-cc/codegen:normalize-x86-64-eh-model "bogus")))
  (it "signals an error for a value that is neither NIL, a known keyword, nor a string"
    (signals error (cl-cc/codegen:normalize-x86-64-eh-model 42))))

(describe-sequential "x86-64-eh.lisp: x86-64-table-eh-enabled-p"
  ;; Both defaults verified directly against their own DEFPARAMETER forms:
  ;; *ZERO-COST-EH-ENABLED* = NIL, *EH-MODEL* = :SJLJ.
  (it "is NIL when zero-cost-eh is disabled and the model is :sjlj (the defaults)"
    (let ((cl-cc/codegen:*zero-cost-eh-enabled* nil)
          (cl-cc/codegen:*eh-model* :sjlj))
      (expect (cl-cc/codegen:x86-64-table-eh-enabled-p) :to-be nil)))
  (it "is T when *zero-cost-eh-enabled* is T, regardless of *eh-model*"
    (let ((cl-cc/codegen:*zero-cost-eh-enabled* t)
          (cl-cc/codegen:*eh-model* :sjlj))
      (expect (cl-cc/codegen:x86-64-table-eh-enabled-p) :to-be t)))
  (it "is T when *eh-model* normalizes to :table, even with zero-cost-eh disabled"
    (let ((cl-cc/codegen:*zero-cost-eh-enabled* nil)
          (cl-cc/codegen:*eh-model* "zero-cost"))
      (expect (cl-cc/codegen:x86-64-table-eh-enabled-p) :to-be t))))

(describe-sequential "wasm-imports.lisp: %wasm-aot-mode-active-p"
  ;; *WASM-AOT-MODE-ENABLED* defaults to NIL (verified via its own DEFPARAMETER).
  (it "is NIL by default"
    (let ((cl-cc/codegen::*wasm-aot-mode-enabled* nil))
      (expect (cl-cc/codegen::%wasm-aot-mode-active-p) :to-be nil)))
  (it "is T when *wasm-aot-mode-enabled* is T"
    (let ((cl-cc/codegen::*wasm-aot-mode-enabled* t))
      (expect (cl-cc/codegen::%wasm-aot-mode-active-p) :to-be t))))

(describe-sequential "wasm-imports.lisp: wasm-module-used-host-imports"
  ;; *WASM-EXCEPTION-HANDLING-V2-ENABLED* defaults to T (verified directly,
  ;; not inferred), so condition_to_exnref/exnref_payload/exnref_tag are
  ;; ALWAYS marked used regardless of module content -- an unconditional
  ;; tail effect in the source, not something this test invented.
  (it "marks imports mentioned in function bodies and in scanned VM instructions"
    (let* ((module (cl-cc/codegen::make-empty-wasm-module))
           (func (cl-cc/codegen::make-wasm-function-def
                  :wat-name "$foo"
                  :body (list "(call $host_write_char (i32.const 65))")
                  :source-instructions (list (cl-cc/vm:make-vm-print :reg :r0)))))
      (cl-cc/codegen::wasm-module-add-function module func)
      (let ((used (cl-cc/codegen::wasm-module-used-host-imports module)))
        (expect (gethash "write_char" used) :to-be t)
        (expect (gethash "print_val" used) :to-be t)
        (expect (gethash "condition_to_exnref" used) :to-be t)
        (expect (gethash "exnref_payload" used) :to-be t)
        (expect (gethash "exnref_tag" used) :to-be t)
        (expect (gethash "read_char" used) :to-be nil)
        (expect (gethash "register_method" used) :to-be nil)))))

(describe-sequential "wasm-imports.lisp: emit-wat-aot-host-stubs"
  ;; *WASM-DEAD-IMPORT-ELIMINATION-ENABLED* defaults T but
  ;; *WASM-AOT-CURRENT-USED-IMPORTS* defaults NIL, so %WASM-IMPORT-NEEDED-P's
  ;; conservative "no tracking set yet" fallback keeps every stub -- see the
  ;; earlier wasm-imports.lisp coverage-baseline entry for this same fallback.
  (it "emits all 7 no-op host stubs when no import-usage tracking is active"
    (expect (with-output-to-string (s) (cl-cc/codegen::emit-wat-aot-host-stubs s))
            :to-equal
            (format nil "~%  ;; FR-219: AOT host bridge stubs (no mandatory JS imports)~%  (func $host_write_char (param i32))~%  (func $host_read_char (result i32) (i32.const -1))~%  (func $host_write_string (param (ref $string_t)))~%  (func $host_error (param (ref $string_t)))~%  (func $host_print_val (param eqref))~%  (func $host_rt_register_method (param eqref) (param eqref) (param eqref) (param eqref))~%  (func $host_rt_call_generic (param eqref) (param i32) (result eqref) (ref.null eq))"))))

(describe-sequential "stack-maps.lisp: %cg-mir-stack-root-p"
  (it "recognizes a plist entry explicitly kinded :stack, with a root-shaped :type"
    (expect (and (cl-cc/codegen::%cg-mir-stack-root-p '(:kind :stack :type :pointer)) t)
            :to-be t))
  (it "recognizes a plist entry that carries a :slot, even without :kind :stack"
    (expect (and (cl-cc/codegen::%cg-mir-stack-root-p '(:slot 2 :type :object)) t)
            :to-be t))
  (it "rejects a non-cons entry"
    (expect (cl-cc/codegen::%cg-mir-stack-root-p 42) :to-be nil))
  (it "rejects a :stack-kinded entry whose type/kind is not root-shaped"
    (expect (cl-cc/codegen::%cg-mir-stack-root-p '(:kind :stack :type :fixnum)) :to-be nil)))

(describe-sequential "stack-maps.lisp: %cg-register-index"
  (it "returns REG directly when it is already an integer"
    (expect (cl-cc/codegen::%cg-register-index 5 99) :to-be 5))
  (it "returns FALLBACK for anything else"
    (expect (cl-cc/codegen::%cg-register-index :rax 99) :to-be 99)
    (expect (cl-cc/codegen::%cg-register-index nil 99) :to-be 99)))

(describe-sequential "stack-maps.lisp: cg-generate-safepoint-stack-map"
  ;; Passing :LIVE-REGISTERS/:LIVE-STACK-SLOTS explicitly bypasses the MIR
  ;; safepoint-metadata scanning path entirely, so this needs no CL-CC/MIR
  ;; fixture -- SAFEPOINT itself can be a plain NIL placeholder.
  (it "builds register/stack-slot entries and bitmasks from explicit live sets"
    (let ((sm (cl-cc/codegen:cg-generate-safepoint-stack-map
               nil :safepoint-id 5 :pc-offset 10 :frame-size 32
               :live-registers '(3 7)
               :live-stack-slots '((:slot 2) (:slot 5)))))
      (expect (cl-cc/codegen:cg-sm-safepoint-id sm) :to-be 5)
      (expect (cl-cc/codegen:cg-sm-pc-offset sm) :to-be 10)
      (expect (cl-cc/codegen:cg-sm-frame-size sm) :to-be 32)
      (expect (mapcar #'cl-cc/codegen:cg-sme-index (cl-cc/codegen:cg-sm-register-roots sm))
              :to-equal '(3 7))
      (expect (mapcar #'cl-cc/codegen:cg-sme-index (cl-cc/codegen:cg-sm-stack-slot-roots sm))
              :to-equal '(2 5))
      ;; bit 3 (8) | bit 7 (128) = 136
      (expect (cl-cc/codegen:cg-sm-register-bitmask sm) :to-be 136)
      ;; bit 2 (4) | bit 5 (32) = 36
      (expect (cl-cc/codegen:cg-sm-stack-bitmask sm) :to-be 36))))

(describe-sequential "stack-maps.lisp: cg-stack-map->section-record"
  (it "flattens a cg-stack-map into a plain plist payload"
    (let ((sm (cl-cc/codegen:make-cg-stack-map
               :safepoint-id 1 :pc-offset 2 :register-bitmask 5 :stack-bitmask 6 :frame-size 7
               :register-roots (list (cl-cc/codegen:make-cg-stack-map-entry :location :rax))
               :stack-slot-roots (list (cl-cc/codegen:make-cg-stack-map-entry :location 3)))))
      (expect (cl-cc/codegen:cg-stack-map->section-record sm)
              :to-equal '(:gc-stack-map :safepoint-id 1 :pc-offset 2
                          :register-bitmask 5 :stack-bitmask 6 :frame-size 7
                          :registers (:rax) :stack-slots (3))))))

(describe-sequential "stack-maps.lisp: cg-safepoint-instruction-p"
  (it "recognizes a plain (:safepoint ...) list form"
    (expect (cl-cc/codegen:cg-safepoint-instruction-p '(:safepoint foo)) :to-be t))
  (it "rejects a list whose head is not :safepoint"
    (expect (cl-cc/codegen:cg-safepoint-instruction-p '(:other foo)) :to-be nil))
  (it "rejects a non-cons, non-MIR-instruction value"
    (expect (cl-cc/codegen:cg-safepoint-instruction-p 42) :to-be nil)))

(describe-sequential "stack-maps.lisp: cg-embed-stack-maps-after-safepoints"
  ;; *PRECISE-GC-STACK-MAPS-ENABLED* defaults to NIL (per its own DEFPARAMETER
  ;; docstring, confirmed), making this the identity function by default.
  (it "returns CODE-SECTION unchanged when precise GC stack maps are disabled"
    (let ((cl-cc/codegen:*precise-gc-stack-maps-enabled* nil)
          (code (list '(:mov :rax :rbx) '(:safepoint) '(:ret))))
      (expect (cl-cc/codegen:cg-embed-stack-maps-after-safepoints code) :to-equal code))))

(describe-sequential "wasm-extract.lisp: %wasm-label-at-pc"
  (it "returns the label name when PC denotes a vm-label instruction"
    (let ((instructions (list (cl-cc/vm:make-vm-move :dst :r0 :src :r1)
                              (cl-cc/vm:make-vm-label :name 'foo)
                              (cl-cc/vm:make-vm-move :dst :r2 :src :r3))))
      (expect (cl-cc/codegen::%wasm-label-at-pc instructions 1) :to-be 'foo)
      (expect (cl-cc/codegen::%wasm-label-at-pc instructions 0) :to-be nil)
      (expect (cl-cc/codegen::%wasm-label-at-pc instructions 99) :to-be nil)
      (expect (cl-cc/codegen::%wasm-label-at-pc instructions nil) :to-be nil))))

(describe-sequential "wasm-extract.lisp: collect-function-params"
  (it "maps each vm-closure's entry label to its VM parameter register list"
    (let* ((c1 (cl-cc/vm:make-vm-closure :dst :r0 :label "func1" :params '(:r1 :r2)))
           (c2 (cl-cc/vm:make-vm-closure :dst :r3 :label "func2" :params nil))
           (params-map (cl-cc/codegen::collect-function-params (list c1 c2))))
      (expect (gethash "func1" params-map) :to-equal '(:r1 :r2))
      (expect (gethash "func2" params-map) :to-be nil)
      (expect (gethash "unknown" params-map) :to-be nil))))

(describe-sequential "wasm-extract.lisp: collect-entry-labels"
  (it "records the entry label of every vm-closure and vm-func-ref, skipping vm-register-function"
    (let* ((c1 (cl-cc/vm:make-vm-closure :dst :r0 :label "func1" :params nil))
           (fr (cl-cc/vm:make-vm-func-ref :dst :r1 :label "func2" :params nil))
           (labels (cl-cc/codegen::collect-entry-labels (list c1 fr))))
      (expect (gethash "func1" labels) :to-be t)
      (expect (gethash "func2" labels) :to-be t)
      (expect (hash-table-count labels) :to-be 2))))

(describe-sequential "wasm-extract.lisp: segment-instructions"
  (it "splits a flat instruction list into alternating :toplevel/:function segments at entry labels and vm-ret"
    (let* ((move1 (cl-cc/vm:make-vm-move :dst :r0 :src :r1))
           (label (cl-cc/vm:make-vm-label :name 'foo))
           (move2 (cl-cc/vm:make-vm-move :dst :r2 :src :r3))
           (ret (cl-cc/vm:make-vm-ret :reg :r2))
           (move3 (cl-cc/vm:make-vm-move :dst :r4 :src :r5))
           (entry-labels (make-hash-table :test 'equal)))
      (setf (gethash 'foo entry-labels) t)
      (expect (cl-cc/codegen::segment-instructions
               (list move1 label move2 ret move3) entry-labels)
              :to-equal (list (list :toplevel move1)
                              (list :function 'foo (list label move2 ret))
                              (list :toplevel move3))))))

(describe-sequential "x86-64-regs.lisp: vm-const-to-integer"
  (it-each ((nil 0) (t 1) (5 5) (-3 -3) ("str" 0) (:foo 0))
      "vm-const-to-integer(~S) => ~A"
      (value expected)
    (expect (cl-cc/codegen::vm-const-to-integer value) :to-be expected)))

(describe-sequential "x86-64-regs.lisp: x86-64-float-vreg-p"
  (it "is NIL when no float-vreg tracking table is bound"
    (let ((cl-cc/codegen::*current-float-vregs* nil))
      (expect (cl-cc/codegen::x86-64-float-vreg-p :r0) :to-be nil)))
  (it "reflects the bound tracking table's membership"
    (let ((cl-cc/codegen::*current-float-vregs* (make-hash-table :test 'eq)))
      (setf (gethash :r0 cl-cc/codegen::*current-float-vregs*) t)
      (expect (cl-cc/codegen::x86-64-float-vreg-p :r0) :to-be t)
      (expect (cl-cc/codegen::x86-64-float-vreg-p :r1) :to-be nil))))

(describe-sequential "x86-64-regs.lisp: vm-reg-to-x86"
  ;; Passing an already-physical register keyword (:rax, :rcx, ...) hits the
  ;; *PHYS-REG-TO-X86-CODE* fast path directly, bypassing *CURRENT-REGALLOC*
  ;; and *VM-REG-MAP* entirely -- no allocator fixture needed for this case.
  (it "maps a physical register keyword directly to its x86-64 code"
    (expect (cl-cc/codegen::vm-reg-to-x86 :rax) :to-be 0)
    (expect (cl-cc/codegen::vm-reg-to-x86 :rcx) :to-be 1)))

(describe-sequential "x86-64-regs.lisp: vm-reg-to-x86-with-alloc"
  (it "looks up the virtual register's assigned physical register, then its x86-64 code"
    (let* ((ht (make-hash-table :test 'eq)))
      (setf (gethash :r0 ht) :rax)
      (let ((ra (cl-cc/regalloc::make-regalloc-result :assignment ht)))
        (expect (cl-cc/codegen:vm-reg-to-x86-with-alloc ra :r0) :to-be 0))))
  (it "signals an error for a virtual register with no allocation entry"
    (let ((ra (cl-cc/regalloc::make-regalloc-result :assignment (make-hash-table :test 'eq))))
      (signals error (cl-cc/codegen:vm-reg-to-x86-with-alloc ra :r99)))))

(describe-sequential "x86-64-regs.lisp: x86-64-compute-float-vregs"
  (it "marks a vm-const's dst when its value is a float, and propagates through vm-move"
    (let* ((c1 (cl-cc/vm:make-vm-const :dst :r0 :value 3.5))
           (m1 (cl-cc/vm:make-vm-move :dst :r1 :src :r0))
           (fv (cl-cc/codegen::x86-64-compute-float-vregs (list c1 m1))))
      (expect (gethash :r0 fv) :to-be t)
      (expect (gethash :r1 fv) :to-be t)
      (expect (gethash :r2 fv) :to-be nil)))
  (it "does not mark a vm-const's dst when its value is an integer"
    (let* ((c1 (cl-cc/vm:make-vm-const :dst :r0 :value 42))
           (fv (cl-cc/codegen::x86-64-compute-float-vregs (list c1))))
      (expect (gethash :r0 fv) :to-be nil))))

(describe-sequential "x86-64-codegen-dispatch.lisp: x86-64-used-callee-saved-regs"
  (it "returns the x86-64 codes of used callee-saved registers, in fixed ABI order, deduped"
    (let ((ht (make-hash-table :test 'eq)))
      (setf (gethash :v1 ht) :rax    ; caller-saved, excluded
            (gethash :v2 ht) :rbx    ; callee-saved, used
            (gethash :v3 ht) :r14    ; callee-saved, used
            (gethash :v4 ht) :rbx)   ; duplicate of :v2 -- must not appear twice
      (let ((ra (cl-cc/regalloc::make-regalloc-result :assignment ht)))
        ;; ABI order is (:rbx :r12 :r13 :r14 :r15); only rbx (code 3) and r14
        ;; (code 14) are used, so they must appear in that relative order.
        (expect (cl-cc/codegen::x86-64-used-callee-saved-regs
                 ra (cl-cc/target:find-target :x86-64))
                :to-equal '(3 14)))))
  (it "returns NIL when no callee-saved register is used"
    (let* ((ht (make-hash-table :test 'eq)))
      (setf (gethash :v1 ht) :rax)
      (let ((ra (cl-cc/regalloc::make-regalloc-result :assignment ht)))
        (expect (cl-cc/codegen::x86-64-used-callee-saved-regs
                 ra (cl-cc/target:find-target :x86-64))
                :to-be nil)))))

(describe-sequential "ppc64-codegen.lisp: encode-ppc64-nop / emit-ppc64-instr"
  (it "encode-ppc64-nop returns the fixed ORI R0,R0,0 word"
    (expect (cl-cc/codegen:encode-ppc64-nop) :to-be #x60000000))
  (it "emit-ppc64-instr writes the 32-bit word as 4 big-endian bytes"
    (expect (%collect-emitted-octets
             (lambda (sink) (cl-cc/codegen:emit-ppc64-instr #x60000000 sink)))
            :to-equalp #(#x60 #x00 #x00 #x00))))

(describe-sequential "ppc64-codegen.lisp: encode-power10-addi / encode-power10-add"
  (it "encode-power10-addi packs opcode 14, RT, RA, and the signed 16-bit immediate"
    (expect (cl-cc/codegen:encode-power10-addi 3 1 -32) :to-be #x3861FFE0))
  (it "encode-power10-add packs the XO-form base opcode with RT, RA, RB"
    (expect (cl-cc/codegen:encode-power10-add 3 1 2) :to-be #x7C611214)))

(describe-sequential "ppc64-codegen.lisp: encode-power10-ld / encode-power10-std"
  (it "encode-power10-ld packs RT, RA, and the 4-byte-aligned DS displacement"
    (expect (cl-cc/codegen:encode-power10-ld 3 1 16) :to-be #xE8610010))
  (it "encode-power10-ld signals an error for a misaligned displacement"
    (signals error (cl-cc/codegen:encode-power10-ld 3 1 15)))
  (it "encode-power10-std packs RS, RA, and DS the same way as LD"
    (expect (cl-cc/codegen:encode-power10-std 0 1 16) :to-be #xF8010010))
  (it "encode-power10-std signals an error for a misaligned displacement"
    (signals error (cl-cc/codegen:encode-power10-std 0 1 15))))

(describe-sequential "ppc64-codegen.lisp: encode-power10-cmp"
  (it "sets the L bit for a 64-bit (doubleword) compare by default"
    (expect (cl-cc/codegen:encode-power10-cmp 0 3 4) :to-be #x7C232000))
  (it "clears the L bit for a 32-bit compare when :doubleword is NIL"
    (expect (cl-cc/codegen:encode-power10-cmp 0 3 4 :doubleword nil) :to-be #x7C032000)))

(describe-sequential "ppc64-codegen.lisp: encode-power10-mflr / encode-power10-mtlr"
  (it "encode-power10-mflr encodes MFSPR RT,LR via the split SPR field"
    (expect (cl-cc/codegen:encode-power10-mflr 0) :to-be #x7C0802A6))
  (it "encode-power10-mtlr encodes MTSPR LR,RS via the split SPR field"
    (expect (cl-cc/codegen:encode-power10-mtlr 0) :to-be #x7C0803A6)))

(describe-sequential "ppc64-codegen.lisp: encode-power10-bc / encode-power10-b / encode-power10-bl"
  (it "encode-power10-bc packs the conditional-branch opcode, BO, BI, and BD"
    (expect (cl-cc/codegen:encode-power10-bc 12 2 8) :to-be #x41820008))
  (it "encode-power10-b packs the branch opcode and displacement, AA/LK clear"
    (expect (cl-cc/codegen:encode-power10-b 4) :to-be #x48000004))
  (it "encode-power10-bl is encode-power10-b with LK set"
    (expect (cl-cc/codegen:encode-power10-bl 4) :to-be #x48000005)))

(describe-sequential "ppc64-codegen.lisp: ppc64-elfv2-prologue / ppc64-elfv2-epilogue"
  (it "prologue emits MFLR R0, STD R0->linkage-slot(R1), then ADDI R1,R1,-frame-size"
    (expect (cl-cc/codegen:ppc64-elfv2-prologue :frame-size 32 :linkage-slot 16)
            :to-equal (list #x7C0802A6 #xF8010010 #x3821FFE0)))
  (it "epilogue emits ADDI R1,R1,+frame-size, LD R0<-linkage-slot(R1), then MTLR R0"
    (expect (cl-cc/codegen:ppc64-elfv2-epilogue :frame-size 32 :linkage-slot 16)
            :to-equal (list #x38210020 #xE8010010 #x7C0803A6)))
  (it "both signal an error when frame-size is not a positive multiple of 16"
    (signals error (cl-cc/codegen:ppc64-elfv2-prologue :frame-size 17))
    (signals error (cl-cc/codegen:ppc64-elfv2-epilogue :frame-size 0))))

(describe-sequential "ppc64-codegen.lisp: ppc64-backend-available-p"
  (it "is NIL by default (*ppc64-enabled* defaults to NIL)"
    (let ((cl-cc/codegen:*ppc64-enabled* nil))
      (expect (cl-cc/codegen:ppc64-backend-available-p) :to-be nil)))
  (it "is T when *ppc64-enabled* is T"
    (let ((cl-cc/codegen:*ppc64-enabled* t))
      (expect (cl-cc/codegen:ppc64-backend-available-p) :to-be t))))

(describe-sequential "x86-64-codegen-core.lisp: stack-probe-count"
  (it-each ((4096 1) (8192 2) (4095 0) (5000 1) (0 0))
      "stack-probe-count(~A) => ~A"
      (frame-size expected)
    (expect (cl-cc/codegen::stack-probe-count frame-size) :to-be expected)))

(describe-sequential "x86-64-codegen-core.lisp: x86-64-stack-frame-size"
  (it "sums 8 bytes per saved register plus the spill frame size"
    (expect (cl-cc/codegen::x86-64-stack-frame-size '(:rbx :r12) 16) :to-be 32)
    (expect (cl-cc/codegen::x86-64-stack-frame-size nil 0) :to-be 0)))

(describe-sequential "x86-64-codegen-core.lisp: x86-64-safe-stack-*-size"
  (it "are all 0 when *x86-64-safe-stack-enabled* is NIL (the default)"
    (let ((cl-cc/codegen:*x86-64-safe-stack-enabled* nil))
      (expect (cl-cc/codegen::x86-64-safe-stack-pointer-size) :to-be 0)
      (expect (cl-cc/codegen::x86-64-safe-stack-prologue-size) :to-be 0)
      (expect (cl-cc/codegen::x86-64-safe-stack-epilogue-size) :to-be 0)))
  (it "are 18/9/9 when *x86-64-safe-stack-enabled* is T"
    (let ((cl-cc/codegen:*x86-64-safe-stack-enabled* t))
      (expect (cl-cc/codegen::x86-64-safe-stack-pointer-size) :to-be 18)
      (expect (cl-cc/codegen::x86-64-safe-stack-prologue-size) :to-be 9)
      (expect (cl-cc/codegen::x86-64-safe-stack-epilogue-size) :to-be 9))))

(describe-sequential "x86-64-codegen-core.lisp: x86-64-align-up"
  (it-each ((13 8 16) (16 8 16) (0 8 0) (5 1 5) (5 0 5))
      "x86-64-align-up(~A, ~A) => ~A"
      (offset alignment expected)
    (expect (cl-cc/codegen::x86-64-align-up offset alignment) :to-be expected)))

(describe-sequential "x86-64-codegen-core.lisp: x86-64-stack-slot-name/size/alignment"
  (it "reads the plist shape, defaulting size to 8 and alignment to (min 8 size)"
    (expect (cl-cc/codegen::x86-64-stack-slot-name '(:name foo :size 4 :alignment 4)) :to-be 'foo)
    (expect (cl-cc/codegen::x86-64-stack-slot-size '(:name foo :size 4 :alignment 4)) :to-be 4)
    (expect (cl-cc/codegen::x86-64-stack-slot-alignment '(:name foo :size 4 :alignment 4)) :to-be 4)
    (expect (cl-cc/codegen::x86-64-stack-slot-size '(:name bar)) :to-be 8)
    (expect (cl-cc/codegen::x86-64-stack-slot-alignment '(:name bar)) :to-be 8))
  (it "reads the positional (name size &optional alignment) shape"
    (expect (cl-cc/codegen::x86-64-stack-slot-name '(baz 4 2)) :to-be 'baz)
    (expect (cl-cc/codegen::x86-64-stack-slot-size '(baz 4 2)) :to-be 4)
    (expect (cl-cc/codegen::x86-64-stack-slot-alignment '(baz 4 2)) :to-be 2)
    (expect (cl-cc/codegen::x86-64-stack-slot-alignment '(qux 4)) :to-be 4))
  (it "treats a bare atom as its own name, with size/alignment 8"
    (expect (cl-cc/codegen::x86-64-stack-slot-name 'atom-slot) :to-be 'atom-slot)
    (expect (cl-cc/codegen::x86-64-stack-slot-size 'atom-slot) :to-be 8)
    (expect (cl-cc/codegen::x86-64-stack-slot-alignment 'atom-slot) :to-be 8)))

(describe-sequential "x86-64-codegen-core.lisp: x86-64-pack-stack-slots"
  (it "packs slots by descending size, aligns each offset, and rounds the final frame size"
    (multiple-value-bind (layout remap frame-size)
        (cl-cc/codegen::x86-64-pack-stack-slots (list '(a 4) '(b 8) '(c 2)))
      (expect layout :to-equal '((:name b :size 8 :alignment 8 :offset 0)
                                 (:name a :size 4 :alignment 4 :offset 8)
                                 (:name c :size 2 :alignment 2 :offset 12)))
      (expect (gethash 'b remap) :to-be 0)
      (expect (gethash 'a remap) :to-be 8)
      (expect (gethash 'c remap) :to-be 12)
      (expect frame-size :to-be 16))))

(describe-sequential "x86-64-codegen-core.lisp: x86-64-env-true-p"
  (it-each ((nil nil) ("1" t) ("TRUE" t) ("on" t) ("0" nil) ("bogus" nil))
      "x86-64-env-true-p(~S) => ~A"
      (value expected)
    (expect (and (cl-cc/codegen::x86-64-env-true-p value) t) :to-be expected)))

(describe-sequential "x86-64-codegen-core.lisp: push-r64-byte-size / pop-r64-byte-size"
  (it-each ((0 1) (7 1) (8 2) (15 2))
      "push/pop-r64-byte-size(~A) => ~A"
      (reg expected)
    (expect (cl-cc/codegen::push-r64-byte-size reg) :to-be expected)
    (expect (cl-cc/codegen::pop-r64-byte-size reg) :to-be expected)))

(describe-sequential "x86-64-codegen-core.lisp: x86-64-program-has-nonlocal-control-p"
  ;; SOME propagates whatever truthy value the element-predicate returns (here,
  ;; ultimately MEMBER's matching tail), not necessarily exactly T -- normalize.
  (it "is T when any instruction is a non-local control-flow op, e.g. vm-throw"
    (expect (and (cl-cc/codegen::x86-64-program-has-nonlocal-control-p
                  (list (cl-cc/vm:make-vm-move :dst :r0 :src :r1)
                        (cl-cc/vm:make-vm-throw :tag-reg :r0 :value-reg :r1)))
                 t)
            :to-be t))
  (it "is NIL when no instruction is a non-local control-flow op"
    (expect (cl-cc/codegen::x86-64-program-has-nonlocal-control-p
             (list (cl-cc/vm:make-vm-move :dst :r0 :src :r1)))
            :to-be nil)))

(describe-sequential "x86-64-codegen-core.lisp: x86-64-stack-buffer-inst-p / x86-64-program-has-stack-buffer-p"
  (it "recognizes buffer-like array/vector instructions, e.g. vm-svref"
    (expect (and (cl-cc/codegen::x86-64-stack-buffer-inst-p
                  (cl-cc/vm:make-vm-svref :dst :r0 :lhs :r1 :rhs :r2))
                 t)
            :to-be t)
    (expect (cl-cc/codegen::x86-64-stack-buffer-inst-p
             (cl-cc/vm:make-vm-move :dst :r0 :src :r1))
            :to-be nil))
  (it "x86-64-program-has-stack-buffer-p is T when any instruction qualifies"
    (expect (and (cl-cc/codegen::x86-64-program-has-stack-buffer-p
                  (list (cl-cc/vm:make-vm-move :dst :r0 :src :r1)
                        (cl-cc/vm:make-vm-svref :dst :r0 :lhs :r1 :rhs :r2)))
                 t)
            :to-be t)
    (expect (cl-cc/codegen::x86-64-program-has-stack-buffer-p
             (list (cl-cc/vm:make-vm-move :dst :r0 :src :r1)))
            :to-be nil)))

(describe-sequential "atomics.lisp: codegen-memory-order"
  (it-each ((nil :seq-cst) (:seq-cst :seq-cst) (:acquire :acquire)
            (:release :release) (:relaxed :relaxed) (:acq-rel :seq-cst))
      "codegen-memory-order(~S) => ~S"
      (order expected)
    (expect (cl-cc/codegen::codegen-memory-order order) :to-be expected))
  (it "signals an error for an unrecognized order"
    (signals error (cl-cc/codegen::codegen-memory-order :bogus))))

(describe-sequential "atomics.lisp: vm-atomic-memory-order*"
  (it "always returns :seq-cst, ignoring INST"
    (expect (cl-cc/codegen::vm-atomic-memory-order* nil) :to-be :seq-cst)))

(describe-sequential "atomics.lisp: x86-64-atomic-fence-byte-size"
  (it-each ((:seq-cst 6) (nil 6) (:acquire 0) (:acq-rel 6))
      "x86-64-atomic-fence-byte-size(~S) => ~A"
      (order expected)
    (expect (cl-cc/codegen::x86-64-atomic-fence-byte-size order) :to-be expected)))

(describe-sequential "atomics.lisp: x86-64-atomic-op-byte-size"
  ;; VM-ATOMIC-MEMORY-ORDER* always returns :SEQ-CST, so INST's actual value is
  ;; irrelevant here and NIL is a safe placeholder.
  (it "sums the seq-cst fence size, op size, and optional move sizes"
    (expect (cl-cc/codegen::x86-64-atomic-op-byte-size nil 10) :to-be 16)
    (expect (cl-cc/codegen::x86-64-atomic-op-byte-size
             nil 10 :result-move-p t :expected-move-p t)
            :to-be 22)))

(describe-sequential "atomics.lisp: emit-x86-64-mfence / emit-x86-64-sfence"
  (it "emit-x86-64-mfence writes its fixed 3-byte encoding"
    (expect (%collect-emitted-octets
             (lambda (sink) (cl-cc/codegen::emit-x86-64-mfence sink)))
            :to-equalp #(#x0F #xAE #xF0)))
  (it "emit-x86-64-sfence writes its fixed 3-byte encoding"
    (expect (%collect-emitted-octets
             (lambda (sink) (cl-cc/codegen::emit-x86-64-sfence sink)))
            :to-equalp #(#x0F #xAE #xF8))))

(describe-sequential "atomics.lisp: emit-x86-64-fence-for-order"
  (it "emits MFENCE for :seq-cst"
    (expect (%collect-emitted-octets
             (lambda (sink) (cl-cc/codegen::emit-x86-64-fence-for-order :seq-cst sink)))
            :to-equalp #(#x0F #xAE #xF0)))
  (it "emits nothing for :acquire (a no-op under x86-64 TSO)"
    (expect (%collect-emitted-octets
             (lambda (sink) (cl-cc/codegen::emit-x86-64-fence-for-order :acquire sink)))
            :to-equalp #())))

(describe-sequential "post-ra-scheduler.lisp: x86-64-macro-fusion-compare-p / x86-64-macro-fusion-branch-p"
  (it "recognizes each of the 8 eligible compare-shaped instruction types"
    (expect (and (cl-cc/codegen:x86-64-macro-fusion-compare-p
                  (cl-cc/vm:make-vm-lt :dst :r0 :lhs :r1 :rhs :r2))
                 t)
            :to-be t)
    (expect (and (cl-cc/codegen:x86-64-macro-fusion-compare-p
                  (cl-cc/vm:make-vm-null-p :dst :r0 :src :r1))
                 t)
            :to-be t))
  (it "rejects an instruction that is not compare-shaped"
    (expect (cl-cc/codegen:x86-64-macro-fusion-compare-p
             (cl-cc/vm:make-vm-move :dst :r0 :src :r1))
            :to-be nil))
  (it "recognizes vm-jump-zero as the branch side of a fusion pair"
    (expect (cl-cc/codegen:x86-64-macro-fusion-branch-p
             (cl-cc/vm:make-vm-jump-zero :reg :r0 :label "L1"))
            :to-be t))
  (it "rejects a plain vm-jump (unconditional, no compare to fuse with)"
    (expect (cl-cc/codegen:x86-64-macro-fusion-branch-p
             (cl-cc/vm:make-vm-move :dst :r0 :src :r1))
            :to-be nil)))

(describe-sequential "post-ra-scheduler.lisp: %post-ra-physical-reg-p"
  (it "recognizes an implicit frame/stack register, e.g. :rsp, unconditionally"
    (expect (and (cl-cc/codegen::%post-ra-physical-reg-p
                  :rsp (cl-cc/regalloc::make-regalloc-result :assignment (make-hash-table :test 'eq)))
                 t)
            :to-be t))
  (it "recognizes a register already present among RA's assigned physical registers"
    (let ((ht (make-hash-table :test 'eq)))
      (setf (gethash :v0 ht) :rbx)
      (expect (and (cl-cc/codegen::%post-ra-physical-reg-p
                    :rbx (cl-cc/regalloc::make-regalloc-result :assignment ht))
                   t)
              :to-be t)))
  (it "recognizes a sub-register alias, e.g. :eax, via *POST-RA-X86-64-ALIASES*"
    (expect (and (cl-cc/codegen::%post-ra-physical-reg-p
                  :eax (cl-cc/regalloc::make-regalloc-result :assignment (make-hash-table :test 'eq)))
                 t)
            :to-be t))
  (it "rejects a plain unmapped virtual register"
    (expect (cl-cc/codegen::%post-ra-physical-reg-p
             :v99 (cl-cc/regalloc::make-regalloc-result :assignment (make-hash-table :test 'eq)))
            :to-be nil)))

(describe-sequential "post-ra-scheduler.lisp: %post-ra-stack-memory-inst-p"
  (it "recognizes vm-spill-store and vm-spill-load"
    (expect (and (cl-cc/codegen::%post-ra-stack-memory-inst-p
                  (cl-cc/regalloc::make-vm-spill-store :src-reg :rax :slot 1))
                 t)
            :to-be t)
    (expect (and (cl-cc/codegen::%post-ra-stack-memory-inst-p
                  (cl-cc/regalloc::make-vm-spill-load :dst-reg :rax :slot 1))
                 t)
            :to-be t))
  (it "rejects a non-spill instruction"
    (expect (cl-cc/codegen::%post-ra-stack-memory-inst-p
             (cl-cc/vm:make-vm-move :dst :r0 :src :r1))
            :to-be nil)))

(describe-sequential "post-ra-scheduler.lisp: %post-ra-fixed-type-p"
  (it "recognizes fixed-barrier instruction types, e.g. vm-jump-zero and vm-ret"
    (expect (and (cl-cc/codegen::%post-ra-fixed-type-p
                  (cl-cc/vm:make-vm-jump-zero :reg :r0 :label "L1"))
                 t)
            :to-be t)
    (expect (and (cl-cc/codegen::%post-ra-fixed-type-p
                  (cl-cc/vm:make-vm-ret :reg :r0))
                 t)
            :to-be t))
  (it "rejects an ordinary data-movement instruction"
    (expect (cl-cc/codegen::%post-ra-fixed-type-p
             (cl-cc/vm:make-vm-move :dst :r0 :src :r1))
            :to-be nil)))

(describe-sequential "x86-64-sequences.lisp: emit-cdq / emit-cqo"
  ;; Zero-operand fixed instruction encodings -- no REX/ModRM register-operand
  ;; derivation needed, unlike most of this file's other emitters (deliberately
  ;; left untested this round rather than guessed at).
  (it "emit-cdq is the fixed 1-byte CDQ encoding"
    (expect (%collect-emitted-octets
             (lambda (sink) (cl-cc/codegen::emit-cdq sink)))
            :to-equalp #(#x99)))
  (it "emit-cqo is the fixed 2-byte REX.W + CDQ encoding"
    (expect (%collect-emitted-octets
             (lambda (sink) (cl-cc/codegen::emit-cqo sink)))
            :to-equalp #(#x48 #x99))))

(describe-sequential "x86-64-sequences.lisp: emit-jge-short"
  (it "emits opcode 0x7D followed by the signed 8-bit displacement"
    (expect (%collect-emitted-octets
             (lambda (sink) (cl-cc/codegen::emit-jge-short 3 sink)))
            :to-equalp #(#x7D 3)))
  (it "masks a negative offset to its 2's-complement byte"
    (expect (%collect-emitted-octets
             (lambda (sink) (cl-cc/codegen::emit-jge-short -1 sink)))
            :to-equalp #(#x7D #xFF))))

(describe-sequential "win-cfg.lisp: win-cfg-guard-fids-table-metadata"
  (it "builds the GuardCF section descriptor from ENTRIES, one row per (target . name)"
    (expect (cl-cc/codegen:win-cfg-guard-fids-table-metadata
             '(("target1" . "name1") ("target2" . "name2")))
            :to-equal '(:section "__guard_fids_table"
                        :comdat ".gfids$y"
                        :entry-size 8
                        :flags (:image-scn-cnt-initialized-data :image-scn-mem-read)
                        :entries ((:target "target1" :name "name1" :guard-flags 1)
                                  (:target "target2" :name "name2" :guard-flags 1)))))
  (it "returns an empty :entries list for an empty table"
    (expect (getf (cl-cc/codegen:win-cfg-guard-fids-table-metadata nil) :entries)
            :to-be nil)))

(describe-sequential "win-cfg.lisp: win-cfg-guard-check-icall-symbol / win-cfg-guard-dispatch-icall-symbol"
  (it "returns the fixed Windows CFG external symbol names"
    (expect (cl-cc/codegen:win-cfg-guard-check-icall-symbol) :to-equal "_guard_check_icall")
    (expect (cl-cc/codegen:win-cfg-guard-dispatch-icall-symbol) :to-equal "_guard_dispatch_icall")))

(describe-sequential "win-cfg.lisp: win-cfg-enabled-p"
  (it "is NIL by default (*win-cfg-enabled* defaults to NIL)"
    (let ((cl-cc/codegen:*win-cfg-enabled* nil))
      (expect (cl-cc/codegen:win-cfg-enabled-p) :to-be nil)))
  (it "is T when *win-cfg-enabled* is T"
    (let ((cl-cc/codegen:*win-cfg-enabled* t))
      (expect (cl-cc/codegen:win-cfg-enabled-p) :to-be t))))

(describe-sequential "sanitizer.lisp: %sanitizer-memory-access-p / %sanitizer-overflow-op-p"
  (it "recognizes vm-aref and vm-aset as memory-access instructions"
    (expect (cl-cc/codegen::%sanitizer-memory-access-p
             (cl-cc/vm:make-vm-aref :dst :r0 :array-reg :r1 :index-reg :r2))
            :to-be t)
    (expect (cl-cc/codegen::%sanitizer-memory-access-p
             (cl-cc/vm:make-vm-aset :array-reg :r1 :index-reg :r2 :val-reg :r3))
            :to-be t)
    (expect (cl-cc/codegen::%sanitizer-memory-access-p
             (cl-cc/vm:make-vm-move :dst :r0 :src :r1))
            :to-be nil))
  (it "recognizes the 3 checked-overflow integer ops"
    (expect (and (cl-cc/codegen::%sanitizer-overflow-op-p
                  (cl-cc/vm:make-vm-integer-add :dst :r0 :lhs :r1 :rhs :r2))
                 t)
            :to-be t)
    (expect (cl-cc/codegen::%sanitizer-overflow-op-p
             (cl-cc/vm:make-vm-move :dst :r0 :src :r1))
            :to-be nil)))

(describe-sequential "sanitizer.lisp: sanitizer-instrumentation-size"
  ;; ASAN's branch needs X86-64-LEA-ADDRESS-BYTE-SIZE / MAKE-X86-64-LEA-ADDRESS
  ;; internals not otherwise exercised this session -- every case here keeps
  ;; *ASAN-INSTRUMENTATION-ENABLED* at its NIL default to avoid guessing at
  ;; that path, testing only the UBSAN-gated additions.
  (it "adds nothing when both sanitizers are disabled (the default)"
    (let ((cl-cc/codegen:*ubsan-instrumentation-enabled* nil)
          (cl-cc/codegen:*asan-instrumentation-enabled* nil))
      (expect (cl-cc/codegen::sanitizer-instrumentation-size
               (cl-cc/vm:make-vm-integer-add :dst :r0 :lhs :r1 :rhs :r2))
              :to-be 0)))
  (it "adds 3 bytes for a checked-overflow op when UBSAN is enabled"
    (let ((cl-cc/codegen:*ubsan-instrumentation-enabled* t)
          (cl-cc/codegen:*asan-instrumentation-enabled* nil))
      (expect (cl-cc/codegen::sanitizer-instrumentation-size
               (cl-cc/vm:make-vm-integer-add :dst :r0 :lhs :r1 :rhs :r2))
              :to-be 3)))
  (it "adds 6 bytes for a memory-access op when UBSAN is enabled"
    (let ((cl-cc/codegen:*ubsan-instrumentation-enabled* t)
          (cl-cc/codegen:*asan-instrumentation-enabled* nil))
      (expect (cl-cc/codegen::sanitizer-instrumentation-size
               (cl-cc/vm:make-vm-aref :dst :r0 :array-reg :r1 :index-reg :r2))
              :to-be 6))))

(describe-sequential "x86-64-encoding.lisp: emit-byte / emit-dword / emit-qword"
  (it "emit-byte masks its argument to 8 bits"
    (expect (%collect-emitted-octets (lambda (sink) (cl-cc/codegen::emit-byte 300 sink)))
            :to-equalp #(44)))
  (it "emit-dword writes 4 little-endian bytes"
    (expect (%collect-emitted-octets (lambda (sink) (cl-cc/codegen::emit-dword #x12345678 sink)))
            :to-equalp #(#x78 #x56 #x34 #x12)))
  (it "emit-qword writes 8 little-endian bytes (low dword, then high dword)"
    (expect (%collect-emitted-octets
             (lambda (sink) (cl-cc/codegen::emit-qword #x0102030405060708 sink)))
            :to-equalp #(#x08 #x07 #x06 #x05 #x04 #x03 #x02 #x01))))

(describe-sequential "x86-64-encoding.lisp: encode-sib"
  (it "packs SCALE's SIB bits, INDEX-REG, and BASE-REG's low 3 bits"
    (expect (cl-cc/codegen::encode-sib 4 3 5) :to-be #x9D))
  (it "signals an error when INDEX-REG's low 3 bits are 4 (RSP/R12, unencodable as SIB index)"
    (signals error (cl-cc/codegen::encode-sib 1 4 0))
    (signals error (cl-cc/codegen::encode-sib 1 12 0))))

(describe-sequential "x86-64-encoding.lisp: %emit-modrm-address"
  (it "emits a bare ModR/M byte for MOD=0 with a non-RSP/R12 base"
    (expect (%collect-emitted-octets
             (lambda (sink) (cl-cc/codegen::%emit-modrm-address 0 1 0 0 sink)))
            :to-equalp #(8)))
  (it "emits ModR/M then a disp8 byte for MOD=1"
    (expect (%collect-emitted-octets
             (lambda (sink) (cl-cc/codegen::%emit-modrm-address 1 2 3 -5 sink)))
            :to-equalp #(#x53 #xFB)))
  (it "emits an extra SIB byte (scale=1, no index) when BASE is RSP/R12 (rm=4)"
    (expect (%collect-emitted-octets
             (lambda (sink) (cl-cc/codegen::%emit-modrm-address 0 0 4 0 sink)))
            :to-equalp #(4 #x24))))

(describe-sequential "x86-64-encoding.lisp: %emit-modrm-rip-relative"
  (it "emits ModR/M (MOD=0, RM=5) followed by the disp32"
    (expect (%collect-emitted-octets
             (lambda (sink) (cl-cc/codegen::%emit-modrm-rip-relative 1 #x100 sink)))
            :to-equalp #(#x0D #x00 #x01 #x00 #x00))))

(describe-sequential "x86-64-encoding.lisp: %emit-modrm-indexed-address"
  (it "emits ModR/M (RM=4) followed by the SIB byte, for MOD=0"
    (expect (%collect-emitted-octets
             (lambda (sink) (cl-cc/codegen::%emit-modrm-indexed-address 0 0 0 1 1 0 sink)))
            :to-equalp #(4 8))))

(describe-sequential "x86-64-encoding.lisp: x86-64-memory-address-byte-size"
  (it "is 1 byte for MOD=0, no SIB (plain register base, zero offset)"
    (expect (cl-cc/codegen::x86-64-memory-address-byte-size 0 0) :to-be 1))
  (it "is 2 bytes for MOD=1 forced by an RBP/R13 base at zero offset"
    (expect (cl-cc/codegen::x86-64-memory-address-byte-size 5 0) :to-be 2))
  (it "is 2 bytes for MOD=0 plus a forced SIB byte when base is RSP/R12"
    (expect (cl-cc/codegen::x86-64-memory-address-byte-size 4 0) :to-be 2))
  (it "is 5 bytes for MOD=2 (disp32, offset too large for a signed byte)"
    (expect (cl-cc/codegen::x86-64-memory-address-byte-size 0 1000) :to-be 5))
  (it "adds a SIB byte whenever :index is supplied, regardless of base"
    (expect (cl-cc/codegen::x86-64-memory-address-byte-size 0 0 :index :rcx) :to-be 2)))

(describe-sequential "x86-64-encoding.lisp: x86-64-rip-relative-address-byte-size"
  (it "is the fixed 5-byte ModR/M + disp32 size"
    (expect (cl-cc/codegen::x86-64-rip-relative-address-byte-size) :to-be 5)))

(describe-sequential "x86-64-encoding-instrs.lisp: emit-mov-rr64"
  ;; Composes the already-tested REX-PREFIX/MODRM/EMIT-BYTE primitives.
  (it "emits REX.W + 0x89 + ModR/M for a low-register move"
    (expect (%collect-emitted-octets
             (lambda (sink) (cl-cc/codegen::emit-mov-rr64 1 2 sink)))
            :to-equalp #(#x48 #x89 #xD1)))
  (it "sets REX.R/REX.B for extended (r8-r15) registers"
    (expect (%collect-emitted-octets
             (lambda (sink) (cl-cc/codegen::emit-mov-rr64 9 3 sink)))
            :to-equalp #(#x49 #x89 #xD9))))

(describe-sequential "x86-64-encoding-instrs.lisp: emit-mov-ri64"
  (it "emits REX.W + B8+rd + the 8-byte little-endian immediate"
    (expect (%collect-emitted-octets
             (lambda (sink) (cl-cc/codegen::emit-mov-ri64 1 1 sink)))
            :to-equalp #(#x48 #xB9 1 0 0 0 0 0 0 0))))

(describe-sequential "x86-64-encoding-instrs.lisp: emit-mov-rm64-fs-disp32"
  (it "emits the fixed FS-segment-prefixed absolute-disp32 load sequence"
    (expect (%collect-emitted-octets
             (lambda (sink) (cl-cc/codegen::emit-mov-rm64-fs-disp32 1 #x100 sink)))
            :to-equalp #(#x64 #x48 #x8B #x0C #x25 0 1 0 0))))

(describe-sequential "x86-64-encoding-instrs.lisp: emit-push-r64 / emit-pop-r64"
  (it "emits the fixed 50+rd/58+rd opcode for a low register, no REX byte"
    (expect (%collect-emitted-octets (lambda (sink) (cl-cc/codegen::emit-push-r64 3 sink)))
            :to-equalp #(#x53))
    (expect (%collect-emitted-octets (lambda (sink) (cl-cc/codegen::emit-pop-r64 3 sink)))
            :to-equalp #(#x5B)))
  (it "prefixes REX.B (0x41) for an extended register (r8-r15)"
    (expect (%collect-emitted-octets (lambda (sink) (cl-cc/codegen::emit-push-r64 9 sink)))
            :to-equalp #(#x41 #x51))
    (expect (%collect-emitted-octets (lambda (sink) (cl-cc/codegen::emit-pop-r64 9 sink)))
            :to-equalp #(#x41 #x59))))

(describe-sequential "x86-64-encoding-instrs.lisp: emit-leave / emit-ret"
  (it "each emit their single fixed opcode byte"
    (expect (%collect-emitted-octets (lambda (sink) (cl-cc/codegen::emit-leave sink)))
            :to-equalp #(#xC9))
    (expect (%collect-emitted-octets (lambda (sink) (cl-cc/codegen::emit-ret sink)))
            :to-equalp #(#xC3))))

(describe-sequential "x86-64-encoding-instrs.lisp: emit-or-mem-rsp-disp32-imm8"
  (it "emits the fixed RSP-relative OR-immediate stack-probe sequence"
    (expect (%collect-emitted-octets
             (lambda (sink) (cl-cc/codegen::emit-or-mem-rsp-disp32-imm8 100 5 sink)))
            :to-equalp #(#x48 #x83 #x8C #x24 100 0 0 0 5))))

(describe-sequential "x86-64-encoding-instrs.lisp: emit-x86-64-lfence"
  (it "emits the fixed 3-byte LFENCE encoding"
    (expect (%collect-emitted-octets (lambda (sink) (cl-cc/codegen::emit-x86-64-lfence sink)))
            :to-equalp #(#x0F #xAE #xE8))))

(describe-sequential "x86-64-encoding-instrs.lisp: emit-call-r64 / emit-jmp-r64"
  (it "emit-call-r64 emits REX.W + 0xFF + ModR/M with the /2 opcode extension"
    (expect (%collect-emitted-octets (lambda (sink) (cl-cc/codegen::emit-call-r64 3 sink)))
            :to-equalp #(#x48 #xFF #xD3))
    (expect (%collect-emitted-octets (lambda (sink) (cl-cc/codegen::emit-call-r64 9 sink)))
            :to-equalp #(#x49 #xFF #xD1)))
  (it "emit-jmp-r64 emits REX.W + 0xFF + ModR/M with the /4 opcode extension"
    (expect (%collect-emitted-octets (lambda (sink) (cl-cc/codegen::emit-jmp-r64 3 sink)))
            :to-equalp #(#x48 #xFF #xE3))))

(describe-sequential "x86-64-encoding-instrs.lisp: emit-jmp-rel32 / emit-je-rel32"
  (it "emit-jmp-rel32 emits 0xE9 + the 4-byte little-endian displacement"
    (expect (%collect-emitted-octets (lambda (sink) (cl-cc/codegen::emit-jmp-rel32 #x100 sink)))
            :to-equalp #(#xE9 0 1 0 0)))
  (it "emit-je-rel32 emits 0x0F 0x84 + the 4-byte little-endian displacement"
    (expect (%collect-emitted-octets (lambda (sink) (cl-cc/codegen::emit-je-rel32 #x100 sink)))
            :to-equalp #(#x0F #x84 0 1 0 0))))

(describe-sequential "x86-64-encoding-instrs.lisp: emit-x86-64-safe-stack-load-pointer / -store-pointer"
  ;; *X86-64-SAFE-STACK-ENABLED* defaults to NIL (verified via its own
  ;; DEFPARAMETER earlier this session), so both are no-ops by default.
  (it "emit nothing when SafeStack is disabled (the default)"
    (let ((cl-cc/codegen:*x86-64-safe-stack-enabled* nil))
      (expect (%collect-emitted-octets
               (lambda (sink) (cl-cc/codegen::emit-x86-64-safe-stack-load-pointer 1 sink)))
              :to-equalp #())
      (expect (%collect-emitted-octets
               (lambda (sink) (cl-cc/codegen::emit-x86-64-safe-stack-store-pointer 1 sink)))
              :to-equalp #()))))

(describe-sequential "x86-64-encoding-instrs.lisp: emit-jo-rel32 / emit-jno-rel32"
  (it "each emit their 2-byte 0F opcode plus the 4-byte little-endian displacement"
    (expect (%collect-emitted-octets (lambda (sink) (cl-cc/codegen::emit-jo-rel32 #x100 sink)))
            :to-equalp #(#x0F #x80 0 1 0 0))
    (expect (%collect-emitted-octets (lambda (sink) (cl-cc/codegen::emit-jno-rel32 #x100 sink)))
            :to-equalp #(#x0F #x81 0 1 0 0))))

(describe-sequential "x86-64-encoding-instrs.lisp: emit-cmp-ri64 / emit-cmp-ri32"
  (it "emit-cmp-ri64 always emits REX.W + 81 /7 id, regardless of register range"
    (expect (%collect-emitted-octets (lambda (sink) (cl-cc/codegen::emit-cmp-ri64 1 100 sink)))
            :to-equalp #(#x48 #x81 #xF9 100 0 0 0)))
  (it "emit-cmp-ri32 omits REX for a low register, adds REX.B only for r8-r15"
    (expect (%collect-emitted-octets (lambda (sink) (cl-cc/codegen::emit-cmp-ri32 1 100 sink)))
            :to-equalp #(#x81 #xF9 100 0 0 0))
    (expect (%collect-emitted-octets (lambda (sink) (cl-cc/codegen::emit-cmp-ri32 9 100 sink)))
            :to-equalp #(#x41 #x81 #xF9 100 0 0 0))))

(describe-sequential "x86-64-encoding-instrs.lisp: emit-test-rr64"
  (it "emits REX.W + 0x85 + ModR/M with REG2 in the reg field, REG1 in r/m"
    (expect (%collect-emitted-octets (lambda (sink) (cl-cc/codegen::emit-test-rr64 1 2 sink)))
            :to-equalp #(#x48 #x85 #xD1))))

(describe-sequential "x86-64-encoding-instrs.lisp: short (rel8) jump encoders"
  (it "each emits its fixed opcode byte followed by the raw offset byte"
    (expect (%collect-emitted-octets (lambda (sink) (cl-cc/codegen::emit-je-short 5 sink)))
            :to-equalp #(#x74 5))
    (expect (%collect-emitted-octets (lambda (sink) (cl-cc/codegen::emit-jmp-rel8 5 sink)))
            :to-equalp #(#xEB 5))
    (expect (%collect-emitted-octets (lambda (sink) (cl-cc/codegen::emit-jne-rel8 5 sink)))
            :to-equalp #(#x75 5))
    (expect (%collect-emitted-octets (lambda (sink) (cl-cc/codegen::emit-jns-rel8 5 sink)))
            :to-equalp #(#x79 5))
    (expect (%collect-emitted-octets (lambda (sink) (cl-cc/codegen::emit-jge-rel8 5 sink)))
            :to-equalp #(#x7D 5))))

(describe-sequential "x86-64-encoding-instrs.lisp: emit-popcnt-rr64 / emit-lzcnt-rr64 / emit-bsr-rr64"
  (it "emit-popcnt-rr64 emits F3 + REX.W + 0F B8 + ModR/M"
    (expect (%collect-emitted-octets (lambda (sink) (cl-cc/codegen::emit-popcnt-rr64 1 2 sink)))
            :to-equalp #(#xF3 #x48 #x0F #xB8 #xCA)))
  (it "emit-lzcnt-rr64 emits F3 + REX.W + 0F BD + ModR/M"
    (expect (%collect-emitted-octets (lambda (sink) (cl-cc/codegen::emit-lzcnt-rr64 1 2 sink)))
            :to-equalp #(#xF3 #x48 #x0F #xBD #xCA)))
  (it "emit-bsr-rr64 emits REX.W + 0F BD + ModR/M (same opcode as LZCNT, no F3 prefix)"
    (expect (%collect-emitted-octets (lambda (sink) (cl-cc/codegen::emit-bsr-rr64 1 2 sink)))
            :to-equalp #(#x48 #x0F #xBD #xCA))))

(describe-sequential "x86-64-encoding-instrs.lisp: DEFINE-ALU-RR64-generated emitters (add/sub/cmp)"
  ;; All 3 share one macro-generated skeleton (REX.W <opcode> /r); only the
  ;; opcode byte differs.
  (it "emit-add-rr64 uses opcode 0x01"
    (expect (%collect-emitted-octets (lambda (sink) (cl-cc/codegen::emit-add-rr64 1 2 sink)))
            :to-equalp #(#x48 #x01 #xD1)))
  (it "emit-sub-rr64 uses opcode 0x29"
    (expect (%collect-emitted-octets (lambda (sink) (cl-cc/codegen::emit-sub-rr64 1 2 sink)))
            :to-equalp #(#x48 #x29 #xD1)))
  (it "emit-cmp-rr64 uses opcode 0x39"
    (expect (%collect-emitted-octets (lambda (sink) (cl-cc/codegen::emit-cmp-rr64 1 2 sink)))
            :to-equalp #(#x48 #x39 #xD1))))

(describe-sequential "x86-64-encoding-instrs.lisp: DEFINE-ALU-RI32-generated emitters (add/sub)"
  ;; Both share the REX.W 81 /ext id skeleton; only the ModR/M opcode
  ;; extension (/0 vs /5) differs.
  (it "emit-add-ri32 uses ModR/M extension /0"
    (expect (%collect-emitted-octets (lambda (sink) (cl-cc/codegen::emit-add-ri32 1 100 sink)))
            :to-equalp #(#x48 #x81 #xC1 100 0 0 0)))
  (it "emit-sub-ri32 uses ModR/M extension /5"
    (expect (%collect-emitted-octets (lambda (sink) (cl-cc/codegen::emit-sub-ri32 1 100 sink)))
            :to-equalp #(#x48 #x81 #xE9 100 0 0 0))))

(describe-sequential "x86-64-encoding-instrs.lisp: DEFINE-F7-UNARY-RM64-generated emitters (mul/imul/div/idiv)"
  ;; All 4 share the REX.W F7 /ext skeleton; only the extension (/4 /5 /6 /7) differs.
  (it "emit-mul-rm64 uses ModR/M extension /4"
    (expect (%collect-emitted-octets (lambda (sink) (cl-cc/codegen::emit-mul-rm64 1 sink)))
            :to-equalp #(#x48 #xF7 #xE1)))
  (it "emit-imul-rm64 uses ModR/M extension /5"
    (expect (%collect-emitted-octets (lambda (sink) (cl-cc/codegen::emit-imul-rm64 1 sink)))
            :to-equalp #(#x48 #xF7 #xE9)))
  (it "emit-div-rm64 uses ModR/M extension /6"
    (expect (%collect-emitted-octets (lambda (sink) (cl-cc/codegen::emit-div-rm64 1 sink)))
            :to-equalp #(#x48 #xF7 #xF1)))
  (it "emit-idiv-rm64 uses ModR/M extension /7"
    (expect (%collect-emitted-octets (lambda (sink) (cl-cc/codegen::emit-idiv-rm64 1 sink)))
            :to-equalp #(#x48 #xF7 #xF9))))

(describe-sequential "x86-64-encoding-instrs.lisp: emit-imul-rr64"
  (it "emits REX.W + 0F AF + ModR/M (two-operand signed multiply)"
    (expect (%collect-emitted-octets (lambda (sink) (cl-cc/codegen::emit-imul-rr64 1 2 sink)))
            :to-equalp #(#x48 #x0F #xAF #xCA))))

(describe-sequential "x86-64-encoding-instrs.lisp: LEA emitters"
  (it "emit-lea-rr64 emits REX.W + 8D + a fixed SIB-form ModR/M byte + SIB"
    (expect (%collect-emitted-octets
             (lambda (sink) (cl-cc/codegen::emit-lea-rr64 1 2 3 sink 4)))
            :to-equalp #(#x48 #x8D #x0C #x9A)))
  (it "emit-lea-rr64-offset emits REX.W + 8D + ModR/M for [base+offset], no SIB when base isn't RSP/R12"
    (expect (%collect-emitted-octets
             (lambda (sink) (cl-cc/codegen::emit-lea-rr64-offset 1 2 0 sink)))
            :to-equalp #(#x48 #x8D #x0A)))
  (it "emit-lea-rip-relative emits REX.W + 8D + ModR/M(mod=0,rm=5) + disp32"
    (expect (%collect-emitted-octets
             (lambda (sink) (cl-cc/codegen::emit-lea-rip-relative 1 #x100 sink)))
            :to-equalp #(#x48 #x8D #x0D 0 1 0 0))))

(describe-sequential "x86-64-encoding-instrs-xmm.lisp: emit-sse-prefix-rex-if-needed"
  (it "emits nothing when REG, RM, and INDEX are all low registers"
    (expect (%collect-emitted-octets
             (lambda (sink) (cl-cc/codegen::emit-sse-prefix-rex-if-needed 1 2 sink)))
            :to-equalp #()))
  (it "emits REX.R when REG is an extended register (>= 8)"
    (expect (%collect-emitted-octets
             (lambda (sink) (cl-cc/codegen::emit-sse-prefix-rex-if-needed 9 2 sink)))
            :to-equalp #(#x44)))
  (it "emits REX.B when RM is an extended register"
    (expect (%collect-emitted-octets
             (lambda (sink) (cl-cc/codegen::emit-sse-prefix-rex-if-needed 1 9 sink)))
            :to-equalp #(#x41)))
  (it "emits REX.X when INDEX is supplied and extended"
    (expect (%collect-emitted-octets
             (lambda (sink) (cl-cc/codegen::emit-sse-prefix-rex-if-needed 1 2 sink 8)))
            :to-equalp #(#x42))))

(describe-sequential "x86-64-encoding-instrs-xmm.lisp: emit-sse66-0f-xx"
  (it "emits 0x66 prefix, optional REX, 0x0F, the opcode, then ModR/M"
    (expect (%collect-emitted-octets
             (lambda (sink) (cl-cc/codegen::emit-sse66-0f-xx #x58 1 2 sink)))
            :to-equalp #(#x66 #x0F #x58 #xCA))))

(describe-sequential "x86-64-encoding-instrs-xmm.lisp: emit-movdqa-xx / emit-movdqa-xm / emit-movdqa-mx"
  (it "emit-movdqa-xx uses opcode 0x6F between two XMM registers"
    (expect (%collect-emitted-octets
             (lambda (sink) (cl-cc/codegen::emit-movdqa-xx 1 2 sink)))
            :to-equalp #(#x66 #x0F #x6F #xCA)))
  (it "emit-movdqa-xm (load) uses opcode 0x6F with a memory operand"
    (expect (%collect-emitted-octets
             (lambda (sink) (cl-cc/codegen::emit-movdqa-xm 1 2 0 sink)))
            :to-equalp #(#x66 #x0F #x6F #x0A)))
  (it "emit-movdqa-mx (store) uses opcode 0x7F with a memory destination"
    (expect (%collect-emitted-octets
             (lambda (sink) (cl-cc/codegen::emit-movdqa-mx 2 0 1 sink)))
            :to-equalp #(#x66 #x0F #x7F #x0A))))

(describe-sequential "x86-64-encoding-instrs-xmm.lisp: emit-movdqu-xm / emit-movdqu-mx"
  ;; F3 0F /r skeleton -- the unaligned-load/store sibling of MOVDQA's 66 0F /r.
  (it "emit-movdqu-xm (load) emits F3 0F 6F + ModR/M for a memory source"
    (expect (%collect-emitted-octets
             (lambda (sink) (cl-cc/codegen::emit-movdqu-xm 1 2 0 sink)))
            :to-equalp #(#xF3 #x0F #x6F #x0A)))
  (it "emit-movdqu-mx (store) emits F3 0F 7F + ModR/M for a memory destination"
    (expect (%collect-emitted-octets
             (lambda (sink) (cl-cc/codegen::emit-movdqu-mx 2 0 1 sink)))
            :to-equalp #(#xF3 #x0F #x7F #x0A))))

(describe-sequential "x86-64-encoding-instrs-xmm.lisp: DEFINE-SSE66-0F-XMM-OP-generated emitters"
  ;; PADDD/PXOR share the EMIT-SSE66-0F-XX skeleton already verified above;
  ;; only the opcode byte differs.
  (it "emit-paddd-xx uses opcode 0xFE"
    (expect (%collect-emitted-octets (lambda (sink) (cl-cc/codegen::emit-paddd-xx 1 2 sink)))
            :to-equalp #(#x66 #x0F #xFE #xCA)))
  (it "emit-pxor-xx uses opcode 0xEF"
    (expect (%collect-emitted-octets (lambda (sink) (cl-cc/codegen::emit-pxor-xx 1 2 sink)))
            :to-equalp #(#x66 #x0F #xEF #xCA))))

(describe-sequential "x86-64-encoding-instrs-xmm.lisp: DEFINE-SSE66-0F38-XMM-OP-generated emitters"
  ;; The 66 0F 38 skeleton -- one extra fixed 0x38 byte versus the 66 0F family above.
  (it "emit-pmulld-xx (register form) emits 66 0F 38 40 + ModR/M"
    (expect (%collect-emitted-octets (lambda (sink) (cl-cc/codegen::emit-pmulld-xx 1 2 sink)))
            :to-equalp #(#x66 #x0F #x38 #x40 #xCA)))
  (it "emit-pmulld-xm (memory form) emits 66 0F 38 40 + ModR/M for a memory source"
    (expect (%collect-emitted-octets (lambda (sink) (cl-cc/codegen::emit-pmulld-xm 1 2 0 sink)))
            :to-equalp #(#x66 #x0F #x38 #x40 #x0A))))

(describe-sequential "x86-64-lea-peephole.lisp: x86-64-lea-valid-index-p"
  (it "rejects RSP/R12 (low 3 bits = 4), the only unencodable SIB index values"
    (expect (cl-cc/codegen::x86-64-lea-valid-index-p 4) :to-be nil)
    (expect (cl-cc/codegen::x86-64-lea-valid-index-p 12) :to-be nil))
  (it "accepts any other register, and rejects NIL"
    (expect (and (cl-cc/codegen::x86-64-lea-valid-index-p 1) t) :to-be t)
    (expect (cl-cc/codegen::x86-64-lea-valid-index-p nil) :to-be nil)))

(describe-sequential "x86-64-lea-peephole.lisp: x86-64-lea-scale-p"
  (it-each ((1 t) (2 t) (4 t) (8 t) (3 nil) (0 nil))
      "x86-64-lea-scale-p(~A) => ~A"
      (scale expected)
    (expect (and (cl-cc/codegen::x86-64-lea-scale-p scale) t) :to-be expected)))

(describe-sequential "x86-64-lea-peephole.lisp: x86-64-power-of-two-scale-from-shift"
  (it-each ((0 1) (1 2) (2 4) (3 8) (4 nil) (-1 nil))
      "x86-64-power-of-two-scale-from-shift(~A) => ~A"
      (shift expected)
    (expect (cl-cc/codegen::x86-64-power-of-two-scale-from-shift shift) :to-be expected)))

(describe-sequential "x86-64-lea-peephole.lisp: x86-64-vm-int-const-p / x86-64-vm-const-reg-value"
  (it "recognizes an integer, NIL, or T vm-const value as an integer constant"
    (expect (cl-cc/codegen::x86-64-vm-int-const-p (cl-cc/vm:make-vm-const :dst :r0 :value 42))
            :to-be t)
    (expect (cl-cc/codegen::x86-64-vm-int-const-p (cl-cc/vm:make-vm-const :dst :r0 :value nil))
            :to-be t)
    (expect (cl-cc/codegen::x86-64-vm-int-const-p (cl-cc/vm:make-vm-const :dst :r0 :value t))
            :to-be t))
  (it "rejects a non-integer-coercible vm-const value and any non-vm-const instruction"
    (expect (cl-cc/codegen::x86-64-vm-int-const-p (cl-cc/vm:make-vm-const :dst :r0 :value "s"))
            :to-be nil)
    (expect (cl-cc/codegen::x86-64-vm-int-const-p (cl-cc/vm:make-vm-move :dst :r0 :src :r1))
            :to-be nil))
  (it "returns the dst register and the coerced integer value"
    (expect (multiple-value-list
             (cl-cc/codegen::x86-64-vm-const-reg-value
              (cl-cc/vm:make-vm-const :dst :r0 :value 42)))
            :to-equal '(:r0 42))
    (expect (multiple-value-list
             (cl-cc/codegen::x86-64-vm-const-reg-value
              (cl-cc/vm:make-vm-const :dst :r0 :value nil)))
            :to-equal '(:r0 0))))

(describe-sequential "x86-64-lea-peephole.lisp: x86-64-count-register-uses / x86-64-single-use-const-p"
  (it "counts each register's occurrences across INSTRUCTION-USES of all instructions"
    (let ((uses (cl-cc/codegen::x86-64-count-register-uses
                 (list (cl-cc/vm:make-vm-move :dst :r0 :src :r1)
                       (cl-cc/vm:make-vm-move :dst :r2 :src :r1)))))
      (expect (gethash :r1 uses) :to-be 2)
      ;; :r0 only ever appears as a DST (never a USE) in this fixture, so it
      ;; has no entry at all -- not a zero-valued one.
      (expect (nth-value 1 (gethash :r0 uses)) :to-be nil)))
  (it "x86-64-single-use-const-p is T only for an integer constant used exactly once"
    (let ((uses (make-hash-table :test 'eq)))
      (setf (gethash :r0 uses) 1)
      (expect (cl-cc/codegen::x86-64-single-use-const-p
               (cl-cc/vm:make-vm-const :dst :r0 :value 42) uses)
              :to-be t)
      (setf (gethash :r0 uses) 2)
      (expect (cl-cc/codegen::x86-64-single-use-const-p
               (cl-cc/vm:make-vm-const :dst :r0 :value 42) uses)
              :to-be nil))))

(describe-sequential "x86-64-lea-peephole.lisp: x86-64-commutative-add-with-reg-p"
  (it "returns the other addend when INST computes DST = REG + other"
    (expect (cl-cc/codegen::x86-64-commutative-add-with-reg-p
             (cl-cc/vm:make-vm-add :dst :r0 :lhs :r1 :rhs :r2) :r0 :r1)
            :to-be :r2)
    (expect (cl-cc/codegen::x86-64-commutative-add-with-reg-p
             (cl-cc/vm:make-vm-add :dst :r0 :lhs :r1 :rhs :r2) :r0 :r2)
            :to-be :r1))
  (it "returns NIL when INST doesn't define DST or doesn't use REG as an addend"
    (expect (cl-cc/codegen::x86-64-commutative-add-with-reg-p
             (cl-cc/vm:make-vm-add :dst :r0 :lhs :r1 :rhs :r2) :r0 :r3)
            :to-be nil)
    (expect (cl-cc/codegen::x86-64-commutative-add-with-reg-p
             (cl-cc/vm:make-vm-move :dst :r0 :src :r1) :r0 :r1)
            :to-be nil)))

(describe-sequential "x86-64-lea-peephole.lisp: x86-64-contiguous-low-mask-width"
  (it-each ((0 0) (7 3) (15 4) (5 nil) (-1 nil))
      "x86-64-contiguous-low-mask-width(~A) => ~A"
      (mask expected)
    (expect (cl-cc/codegen::x86-64-contiguous-low-mask-width mask) :to-be expected)))

(describe-sequential "x86-64-peephole.lisp: peephole-copy-byte-vector / peephole-byte-list-vector"
  (it "peephole-copy-byte-vector copies the full vector by default"
    (expect (cl-cc/codegen::peephole-copy-byte-vector #(1 2 3 4 5)) :to-equalp #(1 2 3 4 5)))
  (it "peephole-copy-byte-vector copies a [start,end) slice"
    (expect (cl-cc/codegen::peephole-copy-byte-vector #(1 2 3 4 5) :start 1 :end 4)
            :to-equalp #(2 3 4)))
  (it "peephole-byte-list-vector coerces a plain list into a byte vector"
    (expect (cl-cc/codegen::peephole-byte-list-vector '(1 2 3)) :to-equalp #(1 2 3))))

(describe-sequential "x86-64-peephole.lisp: x86-rex-byte-p / x86-legacy-prefix-byte-p"
  (it-each ((#x40 t) (#x4F t) (#x3F nil) (#x50 nil))
      "x86-rex-byte-p(~2,'0X) => ~A"
      (byte expected)
    (expect (and (cl-cc/codegen::x86-rex-byte-p byte) t) :to-be expected))
  (it "recognizes a legacy prefix byte, e.g. the 0x66 operand-size override"
    (expect (and (cl-cc/codegen::x86-legacy-prefix-byte-p #x66) t) :to-be t))
  (it "rejects a non-prefix byte"
    (expect (cl-cc/codegen::x86-legacy-prefix-byte-p #x50) :to-be nil)))

(describe-sequential "x86-64-peephole.lisp: x86-modrm-mod / x86-modrm-reg / x86-modrm-rm"
  ;; #xD1 = mod=3, reg=2, rm=1 -- the exact byte hand-derived and verified in
  ;; an earlier round's ADD-RR64 encoder test.
  (it "extracts the MOD/REG/RM fields from a ModR/M byte"
    (expect (cl-cc/codegen::x86-modrm-mod #xD1) :to-be 3)
    (expect (cl-cc/codegen::x86-modrm-reg #xD1) :to-be 2)
    (expect (cl-cc/codegen::x86-modrm-rm #xD1) :to-be 1)))

(describe-sequential "x86-64-peephole.lisp: x86-rex-bit / x86-modrm-reg-full / x86-modrm-rm-full"
  ;; #x49 = REX.W + REX.B (as hand-derived for CALL R9 in an earlier round).
  (it "extracts an individual REX bit, and 0 for a NIL (absent) REX byte"
    (expect (cl-cc/codegen::x86-rex-bit #x49 0) :to-be 1)  ; REX.B
    (expect (cl-cc/codegen::x86-rex-bit #x49 2) :to-be 0)  ; REX.R
    (expect (cl-cc/codegen::x86-rex-bit #x49 3) :to-be 1)  ; REX.W
    (expect (cl-cc/codegen::x86-rex-bit nil 0) :to-be 0))
  (it "combines ModR/M.reg with REX.R to recover an extended register number"
    (expect (cl-cc/codegen::x86-modrm-reg-full #xCA #x44) :to-be 9))  ; reg=1, REX.R set -> 9
  (it "combines ModR/M.rm with REX.B to recover an extended register number"
    (expect (cl-cc/codegen::x86-modrm-rm-full #xCA #x41) :to-be 10)))  ; rm=2, REX.B set -> 10

(describe-sequential "x86-64-peephole.lisp: x86-read-s32 / x86-read-s8"
  (it "reads a positive little-endian s32 unchanged"
    (expect (cl-cc/codegen::x86-read-s32 #(0 1 0 0) 0) :to-be 256))
  (it "reads a negative s32 via two's-complement sign extension"
    (expect (cl-cc/codegen::x86-read-s32 #(#xFF #xFF #xFF #xFF) 0) :to-be -1))
  (it "reads a positive s8 unchanged, and a negative s8 via sign extension"
    (expect (cl-cc/codegen::x86-read-s8 #(5) 0) :to-be 5)
    (expect (cl-cc/codegen::x86-read-s8 #(#xFF) 0) :to-be -1)))

(describe-sequential "x86-64-peephole.lisp: x86-write-s32 / x86-write-s8"
  (it "writes a positive s32 as 4 little-endian bytes"
    (let ((bytes (make-array 4 :element-type '(unsigned-byte 8) :initial-element 0)))
      (cl-cc/codegen::x86-write-s32 bytes 0 256)
      (expect bytes :to-equalp #(0 1 0 0))))
  (it "writes a negative s32 via its two's-complement byte pattern"
    (let ((bytes (make-array 4 :element-type '(unsigned-byte 8) :initial-element 0)))
      (cl-cc/codegen::x86-write-s32 bytes 0 -1)
      (expect bytes :to-equalp #(#xFF #xFF #xFF #xFF))))
  (it "writes a negative s8 via its two's-complement byte pattern"
    (let ((bytes (make-array 1 :element-type '(unsigned-byte 8) :initial-element 0)))
      (cl-cc/codegen::x86-write-s8 bytes 0 -1)
      (expect bytes :to-equalp #(#xFF)))))

(describe-sequential "x86-64-peephole.lisp: x86-encode-xor-rr64 / x86-encode-test-rr64"
  (it "emit-x86-encode-xor-rr64 composes REX.W + 0x31 + ModR/M(reg=rm=REG)"
    (expect (cl-cc/codegen::x86-encode-xor-rr64 1) :to-equalp #(#x48 #x31 #xC9)))
  (it "emit-x86-encode-test-rr64 composes REX.W + 0x85 + ModR/M(reg=rm=REG)"
    (expect (cl-cc/codegen::x86-encode-test-rr64 1) :to-equalp #(#x48 #x85 #xC9))))

(describe-sequential "x86-64-peephole.lisp: native-rewrite-inst"
  (it "returns a fresh copy with only the supplied slots replaced"
    (let* ((original (cl-cc/codegen::make-native-peephole-inst
                      :kind :mov-rr :dst 1 :src 2 :bytes #(1 2 3)))
           (copy (cl-cc/codegen::native-rewrite-inst original :kind :nop)))
      (expect (cl-cc/codegen::native-peephole-inst-kind copy) :to-be :nop)
      (expect (cl-cc/codegen::native-peephole-inst-dst copy) :to-be 1)
      (expect (cl-cc/codegen::native-peephole-inst-src copy) :to-be 2)
      ;; The original must be untouched -- NATIVE-REWRITE-INST copies, not mutates.
      (expect (cl-cc/codegen::native-peephole-inst-kind original) :to-be :mov-rr))))

(describe-sequential "x86-64-peephole.lisp: native-safe-identical-dedup-p"
  (it "is T for the 4 idempotent-when-duplicated instruction kinds"
    (dolist (kind '(:mov-rr :cmp-rr :test-rr :nop))
      (expect (and (cl-cc/codegen::native-safe-identical-dedup-p
                    (cl-cc/codegen::make-native-peephole-inst :kind kind))
                   t)
              :to-be t)))
  (it "is NIL for a kind not in that safe set"
    (expect (cl-cc/codegen::native-safe-identical-dedup-p
             (cl-cc/codegen::make-native-peephole-inst :kind :add-rr))
            :to-be nil)))

(describe-sequential "aarch64-emitters.lisp: emit-a64-vm-add / emit-a64-vm-sub / emit-a64-vm-mul"
  ;; *CURRENT-A64-REGALLOC* defaults to NIL, so A64-REG falls back to parsing
  ;; the :Rn keyword directly (:r1 => 1, :r2 => 2, :r3 => 3), matching the
  ;; same fallback already confirmed for aarch64-codegen-labels.lisp earlier
  ;; this session -- no regalloc-result fixture needed.
  (it "emit-a64-vm-add encodes ADD Xd,Xn,Xm (0x8B000000 base) as 4 little-endian bytes"
    (expect (%collect-emitted-octets
             (lambda (sink)
               (cl-cc/codegen::emit-a64-vm-add
                (cl-cc/vm:make-vm-add :dst :r1 :lhs :r2 :rhs :r3) sink)))
            :to-equalp #(#x41 #x00 #x03 #x8B)))
  (it "emit-a64-vm-sub encodes SUB Xd,Xn,Xm (0xCB000000 base), same field layout as ADD"
    (expect (%collect-emitted-octets
             (lambda (sink)
               (cl-cc/codegen::emit-a64-vm-sub
                (cl-cc/vm:make-vm-sub :dst :r1 :lhs :r2 :rhs :r3) sink)))
            :to-equalp #(#x41 #x00 #x03 #xCB)))
  (it "emit-a64-vm-mul encodes MUL Xd,Xn,Xm (0x9B007C00 base, via MADD with XZR)"
    (expect (%collect-emitted-octets
             (lambda (sink)
               (cl-cc/codegen::emit-a64-vm-mul
                (cl-cc/vm:make-vm-mul :dst :r1 :lhs :r2 :rhs :r3) sink)))
            :to-equalp #(#x41 #x7C #x03 #x9B)))
  (it "emit-a64-vm-truncate encodes SDIV Xd,Xn,Xm (0x9AC00C00 base, signed division)"
    (expect (%collect-emitted-octets
             (lambda (sink)
               (cl-cc/codegen::emit-a64-vm-truncate
                (cl-cc/vm:make-vm-truncate :dst :r1 :lhs :r2 :rhs :r3) sink)))
            :to-equalp #(#x41 #x0C #xC3 #x9A)))
  (it "emit-a64-vm-integer-mul-high-u encodes UMULH Xd,Xn,Xm (0x9BC07C00 base, unsigned high half)"
    (expect (%collect-emitted-octets
             (lambda (sink)
               (cl-cc/codegen::emit-a64-vm-integer-mul-high-u
                (cl-cc/vm:make-vm-integer-mul-high-u :dst :r1 :lhs :r2 :rhs :r3) sink)))
            :to-equalp #(#x41 #x7C #xC3 #x9B)))
  (it "emit-a64-vm-integer-mul-high-s encodes SMULH Xd,Xn,Xm (0x9B407C00 base, signed high half)"
    (expect (%collect-emitted-octets
             (lambda (sink)
               (cl-cc/codegen::emit-a64-vm-integer-mul-high-s
                (cl-cc/vm:make-vm-integer-mul-high-s :dst :r1 :lhs :r2 :rhs :r3) sink)))
            :to-equalp #(#x41 #x7C #x43 #x9B))))

(describe-sequential "aarch64-emitters.lisp: emit-a64-vm-float-sub / -mul / -div (precision-dispatched)"
  ;; VM-FLOAT-PRECISION defaults to :F64, driving the ECASE in
  ;; DEFINE-A64-FLOAT-BINARY-EMITTER toward the D-ENCODE-FN branch; passing
  ;; :precision :f32 explicitly exercises the S-ENCODE-FN branch instead --
  ;; both are asserted below to cover the ECASE's two clauses.
  (it "emit-a64-vm-float-sub encodes FSUB Dd,Dn,Dm at the default :f64 precision"
    (expect (%collect-emitted-octets
             (lambda (sink)
               (cl-cc/codegen::emit-a64-vm-float-sub
                (cl-cc/vm:make-vm-float-sub :dst :r1 :lhs :r2 :rhs :r3) sink)))
            :to-equalp #(#x41 #x38 #x63 #x1E)))
  (it "emit-a64-vm-float-sub encodes FSUB Sd,Sn,Sm at explicit :f32 precision"
    (expect (%collect-emitted-octets
             (lambda (sink)
               (cl-cc/codegen::emit-a64-vm-float-sub
                (cl-cc/vm:make-vm-float-sub :dst :r1 :lhs :r2 :rhs :r3 :precision :f32) sink)))
            :to-equalp #(#x41 #x38 #x23 #x1E)))
  (it "emit-a64-vm-float-mul encodes FMUL Dd,Dn,Dm at the default :f64 precision"
    (expect (%collect-emitted-octets
             (lambda (sink)
               (cl-cc/codegen::emit-a64-vm-float-mul
                (cl-cc/vm:make-vm-float-mul :dst :r1 :lhs :r2 :rhs :r3) sink)))
            :to-equalp #(#x41 #x08 #x63 #x1E)))
  (it "emit-a64-vm-float-mul encodes FMUL Sd,Sn,Sm at explicit :f32 precision"
    (expect (%collect-emitted-octets
             (lambda (sink)
               (cl-cc/codegen::emit-a64-vm-float-mul
                (cl-cc/vm:make-vm-float-mul :dst :r1 :lhs :r2 :rhs :r3 :precision :f32) sink)))
            :to-equalp #(#x41 #x08 #x23 #x1E)))
  (it "emit-a64-vm-float-div encodes FDIV Dd,Dn,Dm at the default :f64 precision"
    (expect (%collect-emitted-octets
             (lambda (sink)
               (cl-cc/codegen::emit-a64-vm-float-div
                (cl-cc/vm:make-vm-float-div :dst :r1 :lhs :r2 :rhs :r3) sink)))
            :to-equalp #(#x41 #x18 #x63 #x1E)))
  (it "emit-a64-vm-float-div encodes FDIV Sd,Sn,Sm at explicit :f32 precision"
    (expect (%collect-emitted-octets
             (lambda (sink)
               (cl-cc/codegen::emit-a64-vm-float-div
                (cl-cc/vm:make-vm-float-div :dst :r1 :lhs :r2 :rhs :r3 :precision :f32) sink)))
            :to-equalp #(#x41 #x18 #x23 #x1E))))

(describe-sequential "aarch64-emitters.lisp: emit-a64-vm-min / emit-a64-vm-max (branchless CSEL)"
  ;; DEFINE-A64-CSEL-EMITTER emits TWO instructions per call: CMP Xn,Xm then
  ;; CSEL Xd,Xn,Xm,cond -- 8 bytes total, cond=LT(11) for MIN, cond=GT(12)
  ;; for MAX, distinguishing the two emitters via the shared CMP prefix.
  (it "emit-a64-vm-min encodes CMP Xn,Xm + CSEL Xd,Xn,Xm,LT (cond=11)"
    (expect (%collect-emitted-octets
             (lambda (sink)
               (cl-cc/codegen::emit-a64-vm-min
                (cl-cc/vm:make-vm-min :dst :r1 :lhs :r2 :rhs :r3) sink)))
            :to-equalp #(#x5F #x00 #x03 #xEB #x41 #xB0 #x83 #x9A)))
  (it "emit-a64-vm-max encodes CMP Xn,Xm + CSEL Xd,Xn,Xm,GT (cond=12)"
    (expect (%collect-emitted-octets
             (lambda (sink)
               (cl-cc/codegen::emit-a64-vm-max
                (cl-cc/vm:make-vm-max :dst :r1 :lhs :r2 :rhs :r3) sink)))
            :to-equalp #(#x5F #x00 #x03 #xEB #x41 #xC0 #x83 #x9A))))

(describe-sequential "aarch64-emitters.lisp: %a64-libm-resolve / a64-libm-address"
  ;; The full libm-call emitters (EMIT-A64-VM-SIN etc.) embed a
  ;; process-address immediate resolved at load time via SB-ALIEN --
  ;; that address is not portable/hand-traceable across machines or SBCL
  ;; builds, so the byte-level emitter itself is not a good target here.
  ;; The deterministic surface underneath is: resolution returns a real
  ;; unsigned 64-bit address, the table lookup matches direct resolution,
  ;; and an unsupported name signals an error -- all hand-traceable without
  ;; depending on any specific address value.
  (it "%a64-libm-resolve resolves \"sin\" to a positive value within unsigned 64-bit range"
    (let ((addr (cl-cc/codegen::%a64-libm-resolve "sin")))
      (expect (and (integerp addr) (< 0 addr #.(expt 2 64)) t) :to-be t)))
  (it "a64-libm-address returns the same value as *a64-libm-address-table*'s own entry for \"cos\""
    (expect (cl-cc/codegen::a64-libm-address "cos")
            :to-equal (cdr (assoc "cos" cl-cc/codegen::*a64-libm-address-table*
                                   :test #'string=))))
  (it "a64-libm-address signals an error for a name outside the supported libm set"
    (signals error (cl-cc/codegen::a64-libm-address "bogus-fn"))))

(describe-sequential "aarch64-emitters.lisp: emit-a64-vm-sqrt (define-a64-unary-emitter)"
  (it "emit-a64-vm-sqrt encodes FSQRT Dd,Dn (0x1E61C000 base) as 4 little-endian bytes"
    (expect (%collect-emitted-octets
             (lambda (sink)
               (cl-cc/codegen::emit-a64-vm-sqrt
                (cl-cc/vm:make-vm-sqrt :dst :r1 :src :r2) sink)))
            :to-equalp #(#x41 #xC0 #x61 #x1E))))

(describe-sequential "aarch64-emitters.lisp: emit-a64-vm-const (value coercion + MOVZ/MOVK chunking)"
  ;; VM-VALUE coerces through a 4-armed COND (integerp / null / eq T / else)
  ;; before being loaded via EMIT-A64-MOV-IMM64's MOVZ+MOVK chunk sequence.
  ;; Covering all 4 COND arms plus a value needing every MOVK chunk.
  (it "coerces a NIL value to 0, emitting only MOVZ Xd,#0"
    (expect (%collect-emitted-octets
             (lambda (sink)
               (cl-cc/codegen::emit-a64-vm-const
                (cl-cc/vm:make-vm-const :dst :r1 :value nil) sink)))
            :to-equalp #(#x01 #x00 #x80 #xD2)))
  (it "coerces a T value to 1, emitting only MOVZ Xd,#1"
    (expect (%collect-emitted-octets
             (lambda (sink)
               (cl-cc/codegen::emit-a64-vm-const
                (cl-cc/vm:make-vm-const :dst :r1 :value t) sink)))
            :to-equalp #(#x21 #x00 #x80 #xD2)))
  (it "coerces a non-integer, non-NIL, non-T value (a keyword) to 0 via the fallback COND arm"
    (expect (%collect-emitted-octets
             (lambda (sink)
               (cl-cc/codegen::emit-a64-vm-const
                (cl-cc/vm:make-vm-const :dst :r1 :value :unrepresentable) sink)))
            :to-equalp #(#x01 #x00 #x80 #xD2)))
  (it "loads an integer needing all 4 chunks via MOVZ + 3x MOVK"
    (expect (%collect-emitted-octets
             (lambda (sink)
               (cl-cc/codegen::emit-a64-vm-const
                (cl-cc/vm:make-vm-const :dst :r1 :value #x0001000200030004) sink)))
            :to-equalp #(#x81 #x00 #x80 #xD2   ; MOVZ X1, #4
                         #x61 #x00 #xA0 #xF2   ; MOVK X1, #3, LSL #16
                         #x41 #x00 #xC0 #xF2   ; MOVK X1, #2, LSL #32
                         #x21 #x00 #xE0 #xF2)))) ; MOVK X1, #1, LSL #48

(describe-sequential "aarch64-emitters.lisp: emit-a64-vm-move (skips MOV when dst == src)"
  (it "emits MOV Xd,Xn (via ORR Xd,XZR,Xn, 0xAA0003E0 base) when dst and src differ"
    (expect (%collect-emitted-octets
             (lambda (sink)
               (cl-cc/codegen::emit-a64-vm-move
                (cl-cc/vm:make-vm-move :dst :r1 :src :r2) sink)))
            :to-equalp #(#xE1 #x03 #x02 #xAA)))
  (it "emits nothing when dst and src are the same register"
    (expect (%collect-emitted-octets
             (lambda (sink)
               (cl-cc/codegen::emit-a64-vm-move
                (cl-cc/vm:make-vm-move :dst :r1 :src :r1) sink)))
            :to-equalp #())))

(describe-sequential "aarch64-emitters.lisp: emit-a64-vm-select / -bswap / -rotate / -halt"
  (it "emit-a64-vm-select encodes MOV Xd,Xelse + CMP Xcond,XZR + CSEL Xd,Xthen,Xd,NE (branchless ?:)"
    (expect (%collect-emitted-octets
             (lambda (sink)
               (cl-cc/codegen::emit-a64-vm-select
                (cl-cc/vm:make-vm-select :dst :r1 :cond-reg :r2
                                          :then-reg :r3 :else-reg :r4)
                sink)))
            :to-equalp #(#xE1 #x03 #x04 #xAA   ; MOV X1, X4 (else)
                         #x5F #x00 #x1F #xEB   ; CMP X2, XZR
                         #x61 #x10 #x81 #x9A))) ; CSEL X1, X3, X1, NE
  (it "emit-a64-vm-bswap encodes REV Wd,Wn (0x5AC00800 base, byte-swap low 32 bits)"
    (expect (%collect-emitted-octets
             (lambda (sink)
               (cl-cc/codegen::emit-a64-vm-bswap
                (cl-cc/vm:make-vm-bswap :dst :r1 :src :r2) sink)))
            :to-equalp #(#x41 #x08 #xC0 #x5A)))
  (it "emit-a64-vm-rotate encodes MOV Xd,Xlhs + RORV Xd,Xd,Xrhs (rotate right by variable amount)"
    (expect (%collect-emitted-octets
             (lambda (sink)
               (cl-cc/codegen::emit-a64-vm-rotate
                (cl-cc/vm:make-vm-rotate :dst :r1 :lhs :r2 :rhs :r3) sink)))
            :to-equalp #(#xE1 #x03 #x02 #xAA   ; MOV X1, X2 (lhs)
                         #x21 #x2C #xC3 #x9A))) ; RORV X1, X1, X3
  (it "emit-a64-vm-halt encodes exactly one MOV X0,Xreg to load the return register"
    (expect (%collect-emitted-octets
             (lambda (sink)
               (cl-cc/codegen::emit-a64-vm-halt
                (cl-cc/vm:make-vm-halt :reg :r2) sink)))
            :to-equalp #(#xE0 #x03 #x02 #xAA))))

(describe-sequential "aarch64-emitters.lisp: emit-a64-vm-jump / emit-a64-vm-jump-zero (PC-relative offsets)"
  ;; Both compute BYTE-OFFSET = target-pos - current-pos, then divide by 4
  ;; (instruction units) via ASH ... -2. A forward jump gives a positive
  ;; imm; a backward jump gives a negative imm, which must round-trip
  ;; through DEFENC's LOGAND masking as the correct two's-complement bit
  ;; pattern within the field width -- covering both signs.
  (it "emit-a64-vm-jump encodes B #imm26 for a forward jump (target 16 bytes ahead)"
    (expect (%collect-emitted-octets
             (lambda (sink)
               (cl-cc/codegen::emit-a64-vm-jump
                (cl-cc/vm:make-vm-jump :label "L1") sink 0
                (let ((h (make-hash-table :test 'equal)))
                  (setf (gethash "L1" h) 16)
                  h))))
            :to-equalp #(#x04 #x00 #x00 #x14)))
  (it "emit-a64-vm-jump encodes B #imm26 for a backward jump (target 16 bytes behind) via two's-complement imm26"
    (expect (%collect-emitted-octets
             (lambda (sink)
               (cl-cc/codegen::emit-a64-vm-jump
                (cl-cc/vm:make-vm-jump :label "L1") sink 16
                (let ((h (make-hash-table :test 'equal)))
                  (setf (gethash "L1" h) 0)
                  h))))
            :to-equalp #(#xFC #xFF #xFF #x17)))
  (it "emit-a64-vm-jump-zero encodes CBZ Xn,#imm19 for a forward jump"
    (expect (%collect-emitted-octets
             (lambda (sink)
               (cl-cc/codegen::emit-a64-vm-jump-zero
                (cl-cc/vm:make-vm-jump-zero :reg :r2 :label "L2") sink 0
                (let ((h (make-hash-table :test 'equal)))
                  (setf (gethash "L2" h) 16)
                  h))))
            :to-equalp #(#x82 #x00 #x00 #xB4))))

(describe-sequential "aarch64-emitters.lisp: emit-a64-vm-spill-store / emit-a64-vm-spill-load"
  ;; VM-SPILL-STORE/-LOAD look up their register directly in
  ;; *AARCH64-REG-NUMBER* (an :X0..:X30 alist), NOT through A64-REG's
  ;; generic :Rn fallback -- so the fixture must use :X-prefixed keywords.
  ;; A64-SPILL-SLOT-OFFSET(1) = 0 - 1*8 = -8 against the default
  ;; *CURRENT-A64-SPILL-BASE-REG* (X29/FP), a negative SIMM9 field.
  (it "emit-a64-vm-spill-store encodes STUR Xt,[X29,#-8] for slot 1"
    (expect (%collect-emitted-octets
             (lambda (sink)
               (cl-cc/codegen::emit-a64-vm-spill-store
                (cl-cc/regalloc:make-vm-spill-store :src-reg :x1 :slot 1) sink)))
            :to-equalp #(#xA1 #x83 #x1F #xF8)))
  (it "emit-a64-vm-spill-load encodes LDUR Xt,[X29,#-8] for slot 1"
    (expect (%collect-emitted-octets
             (lambda (sink)
               (cl-cc/codegen::emit-a64-vm-spill-load
                (cl-cc/regalloc:make-vm-spill-load :dst-reg :x2 :slot 1) sink)))
            :to-equalp #(#xA2 #x83 #x5F #xF8))))

(describe-sequential "aarch64-emitters.lisp: emit-a64-vm-prefetch (locality ECASE, indexed addressing, error paths)"
  (it "emits PRFM PLDL1KEEP (rt=0) for :t0 locality, no index register"
    (expect (%collect-emitted-octets
             (lambda (sink)
               (cl-cc/codegen::emit-a64-vm-prefetch
                (cl-cc/vm:make-vm-prefetch :base-reg :r1 :offset 16 :locality :t0)
                sink)))
            :to-equalp #(#x20 #x08 #x80 #xF9)))
  (it "emits PRFM PLDL1STRM (rt=1) for :nta locality, no index register"
    (expect (%collect-emitted-octets
             (lambda (sink)
               (cl-cc/codegen::emit-a64-vm-prefetch
                (cl-cc/vm:make-vm-prefetch :base-reg :r1 :offset 16 :locality :nta)
                sink)))
            :to-equalp #(#x21 #x08 #x80 #xF9)))
  (it "with an index register at scale 8, first materializes BASE+INDEX*8 into X16 then PRFMs [X16]"
    (expect (%collect-emitted-octets
             (lambda (sink)
               (cl-cc/codegen::emit-a64-vm-prefetch
                (cl-cc/vm:make-vm-prefetch :base-reg :r1 :index-reg :r2 :scale 8
                                            :offset 0 :locality :t0)
                sink)))
            :to-equalp #(#x30 #x0C #x02 #x8B   ; ADD X16, X1, X2, LSL #3
                         #x00 #x02 #x80 #xF9))) ; PRFM PLDL1KEEP, [X16]
  (it "signals an error for an indexed prefetch at an unsupported scale"
    (signals error
      (%collect-emitted-octets
       (lambda (sink)
         (cl-cc/codegen::emit-a64-vm-prefetch
          (cl-cc/vm:make-vm-prefetch :base-reg :r1 :index-reg :r2 :scale 4
                                      :offset 0 :locality :t0)
          sink)))))
  (it "signals an error for an offset that isn't a multiple of 8"
    (signals error
      (%collect-emitted-octets
       (lambda (sink)
         (cl-cc/codegen::emit-a64-vm-prefetch
          (cl-cc/vm:make-vm-prefetch :base-reg :r1 :offset 3 :locality :t0)
          sink))))))

(describe-sequential "aarch64-emitters.lisp: boolean-pred and comparison emitter families"
  ;; DEFINE-A64-BOOLEAN-PRED-EMIT-METHOD generates unconditional-result
  ;; predicates (fixnum-only mode: numberp/integerp always true,
  ;; consp/symbolp/functionp always false) dispatched via a per-VM-tag
  ;; hash table in aarch64-program.lisp, not tied 1:1 to a single VM
  ;; struct type -- VM-NUMBER-P/VM-CONS-P are two of several dispatched to
  ;; the same emitter.
  (it "emit-a64-vm-true-pred always emits MOVZ Xd,#1 regardless of the VM tag (VM-NUMBER-P here)"
    (expect (%collect-emitted-octets
             (lambda (sink)
               (cl-cc/codegen::emit-a64-vm-true-pred
                (cl-cc/vm:make-vm-number-p :dst :r1 :src :r2) sink)))
            :to-equalp #(#x21 #x00 #x80 #xD2)))
  (it "emit-a64-vm-false-pred always emits MOVZ Xd,#0 regardless of the VM tag (VM-CONS-P here)"
    (expect (%collect-emitted-octets
             (lambda (sink)
               (cl-cc/codegen::emit-a64-vm-false-pred
                (cl-cc/vm:make-vm-cons-p :dst :r1 :src :r2) sink)))
            :to-equalp #(#x01 #x00 #x80 #xD2)))
  (it "emit-a64-vm-null-p encodes CMP Xsrc,XZR + the MOVZ/MOVZ/CSEL boolean-result idiom (cond=EQ=0)"
    (expect (%collect-emitted-octets
             (lambda (sink)
               (cl-cc/codegen::emit-a64-vm-null-p
                (cl-cc/vm:make-vm-null-p :dst :r1 :src :r2) sink)))
            :to-equalp #(#x5F #x00 #x1F #xEB   ; CMP X2, XZR
                         #x01 #x00 #x80 #xD2   ; MOVZ X1, #0
                         #x30 #x00 #x80 #xD2   ; MOVZ X16, #1
                         #x01 #x02 #x81 #x9A))) ; CSEL X1, X16, X1, EQ
  (it "emit-a64-vm-lt encodes CMP Xlhs,Xrhs + boolean-result idiom at cond=LT(11)"
    (expect (%collect-emitted-octets
             (lambda (sink)
               (cl-cc/codegen::emit-a64-vm-lt
                (cl-cc/vm:make-vm-lt :dst :r1 :lhs :r2 :rhs :r3) sink)))
            :to-equalp #(#x5F #x00 #x03 #xEB   ; CMP X2, X3
                         #x01 #x00 #x80 #xD2   ; MOVZ X1, #0
                         #x30 #x00 #x80 #xD2   ; MOVZ X16, #1
                         #x01 #xB2 #x81 #x9A))) ; CSEL X1, X16, X1, LT
  (it "emit-a64-vm-eq encodes CMP Xlhs,Xrhs + boolean-result idiom at cond=EQ(0)"
    (expect (%collect-emitted-octets
             (lambda (sink)
               (cl-cc/codegen::emit-a64-vm-eq
                (cl-cc/vm:make-vm-eq :dst :r1 :lhs :r2 :rhs :r3) sink)))
            :to-equalp #(#x5F #x00 #x03 #xEB   ; CMP X2, X3
                         #x01 #x00 #x80 #xD2   ; MOVZ X1, #0
                         #x30 #x00 #x80 #xD2   ; MOVZ X16, #1
                         #x01 #x02 #x81 #x9A)))) ; CSEL X1, X16, X1, EQ

(describe-sequential "aarch64-emitters.lisp: emit-a64-vm-add-checked / emit-a64-vm-sub-checked"
  ;; ADDS/SUBS + B.VC(cond=7) skip-2 + BRK #1 overflow-trap idiom.
  (it "emit-a64-vm-add-checked encodes ADDS + B.VC #2 + BRK #1"
    (expect (%collect-emitted-octets
             (lambda (sink)
               (cl-cc/codegen::emit-a64-vm-add-checked
                (cl-cc/vm:make-vm-add-checked :dst :r1 :lhs :r2 :rhs :r3) sink)))
            :to-equalp #(#x41 #x00 #x03 #xAB   ; ADDS X1, X2, X3
                         #x47 #x00 #x00 #x54   ; B.VC #2
                         #x20 #x00 #x20 #xD4))) ; BRK #1
  (it "emit-a64-vm-sub-checked encodes SUBS + B.VC #2 + BRK #1"
    (expect (%collect-emitted-octets
             (lambda (sink)
               (cl-cc/codegen::emit-a64-vm-sub-checked
                (cl-cc/vm:make-vm-sub-checked :dst :r1 :lhs :r2 :rhs :r3) sink)))
            :to-equalp #(#x41 #x00 #x03 #xEB   ; SUBS X1, X2, X3
                         #x47 #x00 #x00 #x54   ; B.VC #2
                         #x20 #x00 #x20 #xD4))) ; BRK #1
  (it "emit-a64-vm-mul-checked encodes the 6-instruction SMULH-based overflow check (MUL does not set NZCV)"
    (expect (%collect-emitted-octets
             (lambda (sink)
               (cl-cc/codegen::emit-a64-vm-mul-checked
                (cl-cc/vm:make-vm-mul-checked :dst :r1 :lhs :r2 :rhs :r3) sink)))
            :to-equalp #(#x41 #x7C #x03 #x9B   ; MUL X1, X2, X3 (low 64 bits)
                         #x50 #x7C #x43 #x9B   ; SMULH X16, X2, X3 (high 64 bits)
                         #x31 #xFC #x7F #x93   ; ASR X17, X1, #63 (sign_extend(X1))
                         #x1F #x02 #x11 #xEB   ; CMP X16, X17
                         #x20 #x00 #x00 #x54   ; B.EQ #1
                         #x20 #x00 #x20 #xD4)))) ; BRK #1

(describe-sequential "wasm-trampoline-fixnum.lisp: i31ref range analysis primitives"
  (it "wasm-i31-range-p is T at both signed i31 boundaries"
    (expect (and (cl-cc/codegen::wasm-i31-range-p cl-cc/codegen::+wasm-i31-min+)
                 (cl-cc/codegen::wasm-i31-range-p cl-cc/codegen::+wasm-i31-max+)
                 t)
            :to-be t))
  (it "wasm-i31-range-p is NIL one past either boundary, and for a non-integer"
    (expect (cl-cc/codegen::wasm-i31-range-p (1+ cl-cc/codegen::+wasm-i31-max+)) :to-be nil)
    (expect (cl-cc/codegen::wasm-i31-range-p (1- cl-cc/codegen::+wasm-i31-min+)) :to-be nil)
    (expect (cl-cc/codegen::wasm-i31-range-p "42") :to-be nil))
  (it "wasm-range-binop computes conservative result ranges for i64.add/sub/mul"
    (expect (cl-cc/codegen::wasm-range-binop '(1 . 2) '(3 . 4) "i64.add") :to-equal '(4 . 6))
    (expect (cl-cc/codegen::wasm-range-binop '(1 . 2) '(3 . 4) "i64.sub") :to-equal '(-3 . -1))
    (expect (cl-cc/codegen::wasm-range-binop '(1 . 2) '(3 . 4) "i64.mul") :to-equal '(3 . 8)))
  (it "wasm-range-binop widens bitwise ops to the full i31 range, and returns NIL for an unknown op or non-cons range"
    (expect (cl-cc/codegen::wasm-range-binop '(1 . 2) '(3 . 4) "i64.and")
            :to-equal (cons cl-cc/codegen::+wasm-i31-min+ cl-cc/codegen::+wasm-i31-max+))
    (expect (cl-cc/codegen::wasm-range-binop '(1 . 2) '(3 . 4) "i64.div_s") :to-be nil)
    (expect (cl-cc/codegen::wasm-range-binop nil '(3 . 4) "i64.add") :to-be nil))
  (it "wasm-range-unary handles the increment/decrement/negate format strings and the popcnt/clz/ctz family"
    (expect (cl-cc/codegen::wasm-range-unary '(1 . 2) "(i64.add ~A (i64.const 1))") :to-equal '(2 . 3))
    (expect (cl-cc/codegen::wasm-range-unary '(1 . 2) "(i64.sub ~A (i64.const 1))") :to-equal '(0 . 1))
    (expect (cl-cc/codegen::wasm-range-unary '(1 . 2) "(i64.sub (i64.const 0) ~A)") :to-equal '(-2 . -1))
    (expect (cl-cc/codegen::wasm-range-unary '(1 . 2) "(i64.popcnt ~A)") :to-equal '(0 . 64))
    (expect (cl-cc/codegen::wasm-range-unary '(1 . 2) "(i64.clz ~A)") :to-equal '(0 . 64))
    (expect (cl-cc/codegen::wasm-range-unary '(1 . 2) "unrecognized") :to-be nil))
  (it "wasm-range-i31-or-unknown passes through a range that fits, widens one that doesn't"
    (expect (cl-cc/codegen::wasm-range-i31-or-unknown '(1 . 2)) :to-equal '(1 . 2))
    (expect (cl-cc/codegen::wasm-range-i31-or-unknown
             (cons (1- cl-cc/codegen::+wasm-i31-min+) 0))
            :to-equal (cons cl-cc/codegen::+wasm-i31-min+ cl-cc/codegen::+wasm-i31-max+)))
  (it "wasm-i64-const-wat-value parses (i64.const N), and returns NIL for a non-match, non-string, or malformed literal"
    (expect (cl-cc/codegen::wasm-i64-const-wat-value "(i64.const 42)") :to-equal 42)
    (expect (cl-cc/codegen::wasm-i64-const-wat-value "(i64.const -7)") :to-equal -7)
    (expect (cl-cc/codegen::wasm-i64-const-wat-value "(i64.add 1 2)") :to-be nil)
    (expect (cl-cc/codegen::wasm-i64-const-wat-value 42) :to-be nil)
    (expect (cl-cc/codegen::wasm-i64-const-wat-value "(i64.const abc)") :to-be nil))
  (it "wasm-i64-extended-i31-source extracts the inner register from an i31 sign-extension WAT shape"
    (expect (cl-cc/codegen::wasm-i64-extended-i31-source
             "(i64.extend_i32_s (i31.get_s $x))")
            :to-equal "$x")
    (expect (cl-cc/codegen::wasm-i64-extended-i31-source "(i64.const 1)") :to-be nil)))

(describe-sequential "wasm-trampoline-fixnum.lisp: wasm-eq-wat / wasm-ref-cast-maybe (FR-142 type tracking)"
  ;; Both dispatch on REG-KNOWN-TYPE, recorded via REG-RECORD-TYPE against a
  ;; WASM-REG-MAP built the same way as the existing wasm-ir.lisp round
  ;; (INITIALIZE-WASM-PARAM-LOCALS for stable local indices 0/1).
  (it "wasm-eq-wat compares two known-:i31ref registers numerically via i64.eq + unboxing"
    (let ((reg-map (cl-cc/codegen::make-wasm-reg-map-for-function 2)))
      (cl-cc/codegen::initialize-wasm-param-locals reg-map '(:r0 :r1))
      (cl-cc/codegen::reg-record-type reg-map :r0 :i31ref)
      (cl-cc/codegen::reg-record-type reg-map :r1 :i31ref)
      (expect (cl-cc/codegen::wasm-eq-wat reg-map :r0 :r1)
              :to-equal "(i64.eq (i64.extend_i32_s (i31.get_s (local.get 0))) (i64.extend_i32_s (i31.get_s (local.get 1))))")))
  (it "wasm-eq-wat falls back to ref.eq when either register's type is unknown"
    (let ((reg-map (cl-cc/codegen::make-wasm-reg-map-for-function 2)))
      (cl-cc/codegen::initialize-wasm-param-locals reg-map '(:r0 :r1))
      (expect (cl-cc/codegen::wasm-eq-wat reg-map :r0 :r1)
              :to-equal "(ref.eq (local.get 0) (local.get 1))")))
  (it "wasm-ref-cast-maybe skips the cast when the register's known type already matches TYPE-WAT"
    (let ((reg-map (cl-cc/codegen::make-wasm-reg-map-for-function 1)))
      (cl-cc/codegen::initialize-wasm-param-locals reg-map '(:r0))
      (cl-cc/codegen::reg-record-type reg-map :r0 :cons)
      (expect (cl-cc/codegen::wasm-ref-cast-maybe "(ref $cons_t)" reg-map :r0)
              :to-equal "(local.get 0)")))
  (it "wasm-ref-cast-maybe emits ref.cast (wrapped in ref.as_non_null) when the known type doesn't match"
    (let ((reg-map (cl-cc/codegen::make-wasm-reg-map-for-function 1)))
      (cl-cc/codegen::initialize-wasm-param-locals reg-map '(:r0))
      (cl-cc/codegen::reg-record-type reg-map :r0 :cons)
      (expect (cl-cc/codegen::wasm-ref-cast-maybe "(ref $closure_t)" reg-map :r0)
              :to-equal "(ref.cast (ref $closure_t) (ref.as_non_null (local.get 0)))"))))

(describe-sequential "wasm-trampoline-gc.lisp: array element-kind normalization and WAT primitives"
  (it "wasm-normalize-array-element-kind maps each CL/VM type designator group to its Wasm array kind"
    (expect (cl-cc/codegen::wasm-normalize-array-element-kind 'fixnum) :to-be :fixnum)
    (expect (cl-cc/codegen::wasm-normalize-array-element-kind :integer) :to-be :fixnum)
    (expect (cl-cc/codegen::wasm-normalize-array-element-kind 'double-float) :to-be :float)
    (expect (cl-cc/codegen::wasm-normalize-array-element-kind :float) :to-be :float)
    (expect (cl-cc/codegen::wasm-normalize-array-element-kind 'character) :to-be :char)
    (expect (cl-cc/codegen::wasm-normalize-array-element-kind t) :to-be :eqref)
    (expect (cl-cc/codegen::wasm-normalize-array-element-kind nil) :to-be :eqref)
    (expect (cl-cc/codegen::wasm-normalize-array-element-kind :something-unrecognized) :to-be :eqref))
  (it "wasm-array-type-name/-type-ref look up the WAT type name/ref for a (possibly unnormalized) kind"
    (expect (cl-cc/codegen::wasm-array-type-name :fixnum) :to-equal "$fixnum_array_t")
    (expect (cl-cc/codegen::wasm-array-type-name 'fixnum) :to-equal "$fixnum_array_t")
    (expect (cl-cc/codegen::wasm-array-type-name :char) :to-equal "$char_array_t")
    (expect (cl-cc/codegen::wasm-array-type-ref :fixnum) :to-equal "(ref $fixnum_array_t)"))
  (it "wasm-vector-literal-kind infers the narrowest kind from a CL vector literal's elements"
    (expect (cl-cc/codegen::wasm-vector-literal-kind '(1 2 3)) :to-be :fixnum)
    (expect (cl-cc/codegen::wasm-vector-literal-kind '(1.0 2.0)) :to-be :float)
    (expect (cl-cc/codegen::wasm-vector-literal-kind (list #\a #\b)) :to-be :char)
    (expect (cl-cc/codegen::wasm-vector-literal-kind '()) :to-be :eqref)
    (expect (cl-cc/codegen::wasm-vector-literal-kind '(1 "mixed")) :to-be :eqref))
  (it "wasm-value-to-array-element-wat formats a raw value for its specialized array kind"
    (expect (cl-cc/codegen::wasm-value-to-array-element-wat 42 :fixnum) :to-equal "(i64.const 42)")
    (expect (cl-cc/codegen::wasm-value-to-array-element-wat 3.5 :float) :to-equal "(f64.const 3.5)")
    (expect (cl-cc/codegen::wasm-value-to-array-element-wat #\a :char) :to-equal "(i32.const 97)"))
  (it "wasm-array-default-wat returns each kind's zero/null-equivalent initializer"
    (expect (cl-cc/codegen::wasm-array-default-wat :fixnum) :to-equal "(i64.const 0)")
    (expect (cl-cc/codegen::wasm-array-default-wat :float) :to-equal "(f64.const 0.0)")
    (expect (cl-cc/codegen::wasm-array-default-wat :char) :to-equal "(i32.const 0)")
    (expect (cl-cc/codegen::wasm-array-default-wat :eqref) :to-equal "(ref.null eq)")))

(describe-sequential "x86-64-emit-ops.lisp: emit-vm-add (define-binary-alu-emitter over MOV + ADD)"
  ;; *CURRENT-REGALLOC* defaults to NIL, so VM-REG-TO-X86 falls back to the
  ;; naive *VM-REG-MAP* (:R0->RAX=0, :R1->RCX=1, :R2->RDX=2). The macro
  ;; emits MOV dst,lhs (0x89 /r) then ADD dst,rhs (0x01 /r), each with its
  ;; own REX.W prefix computed from that specific instruction's operands.
  (it "emits MOV RAX,RCX (48 89 C8) then ADD RAX,RDX (48 01 D0) for dst=R0,lhs=R1,rhs=R2"
    (expect (%collect-emitted-octets
             (lambda (sink)
               (cl-cc/codegen::emit-vm-add
                (cl-cc/vm:make-vm-add :dst :r0 :lhs :r1 :rhs :r2) sink)))
            :to-equalp #(#x48 #x89 #xC8   ; MOV RAX, RCX
                         #x48 #x01 #xD0)))) ; ADD RAX, RDX

(describe-sequential "x86-64-emit-ops-logical.lisp: emit-vm-and / emit-vm-or (short-circuit boolean logic)"
  ;; 98%-similar per `paredit inspect similarity` -- both share the exact
  ;; XOR/TEST/TEST/ADD skeleton and differ only in the first short-circuit
  ;; jump's condition byte (JE=0x74 for AND vs JNE=0x75 for OR) and its
  ;; displacement. Locking in the current byte-for-byte output here BEFORE
  ;; consolidating both into a shared defmacro, so the refactor is
  ;; regression-checked against this exact fixture rather than assumed
  ;; equivalent by inspection.
  (it "emit-vm-and encodes XOR dst,dst + TEST lhs,lhs + JE +9 + TEST rhs,rhs + JE +4 + ADD dst,1"
    (expect (%collect-emitted-octets
             (lambda (sink)
               (cl-cc/codegen::emit-vm-and
                (cl-cc/vm:make-vm-and :dst :r0 :lhs :r1 :rhs :r2) sink)))
            :to-equalp #(#x48 #x31 #xC0   ; XOR RAX, RAX
                         #x48 #x85 #xC9   ; TEST RCX, RCX
                         #x74 #x09        ; JE +9
                         #x48 #x85 #xD2   ; TEST RDX, RDX
                         #x74 #x04        ; JE +4
                         #x48 #x83 #xC0 #x01))) ; ADD RAX, 1
  (it "emit-vm-or encodes the same skeleton but JNE +5 for its first short-circuit jump"
    (expect (%collect-emitted-octets
             (lambda (sink)
               (cl-cc/codegen::emit-vm-or
                (cl-cc/vm:make-vm-or :dst :r0 :lhs :r1 :rhs :r2) sink)))
            :to-equalp #(#x48 #x31 #xC0   ; XOR RAX, RAX
                         #x48 #x85 #xC9   ; TEST RCX, RCX
                         #x75 #x05        ; JNE +5
                         #x48 #x85 #xD2   ; TEST RDX, RDX
                         #x74 #x04        ; JE +4
                         #x48 #x83 #xC0 #x01)))) ; ADD RAX, 1

(describe-sequential "x86-64-emit-ops.lisp: emit-vm-integer-mul-high-u / -s (via emit-mul-high-sequence)"
  ;; Locking in current byte-for-byte output BEFORE consolidating these two
  ;; into a shared macro (same pattern as the emit-vm-and/-or round):
  ;; both wrap EMIT-MUL-HIGH-SEQUENCE with a trailing MOV dst,R11, differing
  ;; only in the SIGNEDP flag threaded through to MUL vs IMUL.
  (it "emit-vm-integer-mul-high-u: MOV R11,rhs+PUSH+PUSH+MOV RAX,lhs+MUL R11+MOV R11,RDX+POP+POP+MOV dst,R11"
    (expect (%collect-emitted-octets
             (lambda (sink)
               (cl-cc/codegen::emit-vm-integer-mul-high-u
                (cl-cc/vm:make-vm-integer-mul-high-u :dst :r0 :lhs :r1 :rhs :r2) sink)))
            :to-equalp #(#x49 #x89 #xD3   ; MOV R11, RDX
                         #x50            ; PUSH RAX
                         #x52            ; PUSH RDX
                         #x48 #x89 #xC8   ; MOV RAX, RCX
                         #x49 #xF7 #xE3   ; MUL R11 (unsigned)
                         #x49 #x89 #xD3   ; MOV R11, RDX
                         #x5A            ; POP RDX
                         #x58            ; POP RAX
                         #x4C #x89 #xD8))) ; MOV RAX, R11
  (it "emit-vm-integer-mul-high-s: same skeleton but IMUL R11 (signed)"
    (expect (%collect-emitted-octets
             (lambda (sink)
               (cl-cc/codegen::emit-vm-integer-mul-high-s
                (cl-cc/vm:make-vm-integer-mul-high-s :dst :r0 :lhs :r1 :rhs :r2) sink)))
            :to-equalp #(#x49 #x89 #xD3
                         #x50
                         #x52
                         #x48 #x89 #xC8
                         #x49 #xF7 #xEB   ; IMUL R11 (signed)
                         #x49 #x89 #xD3
                         #x5A
                         #x58
                         #x4C #x89 #xD8))))

(describe-sequential "x86-64-emit-ops.lisp: emit-vm-truncate / emit-vm-rem (via emit-idiv-sequence)"
  ;; Same shared-skeleton relationship as mul-high-u/-s, one level removed:
  ;; both wrap EMIT-IDIV-SEQUENCE (save/setup/CQO/IDIV/restore) with a
  ;; trailing MOV dst,R11, differing only in RESULT-IS-REMAINDER selecting
  ;; RAX (quotient) vs RDX (remainder) into R11 before the restore.
  (it "emit-vm-truncate takes the quotient (RAX) branch of emit-idiv-sequence"
    (expect (%collect-emitted-octets
             (lambda (sink)
               (cl-cc/codegen::emit-vm-truncate
                (cl-cc/vm:make-vm-truncate :dst :r0 :lhs :r1 :rhs :r2) sink)))
            :to-equalp #(#x49 #x89 #xD3   ; MOV R11, RDX
                         #x50            ; PUSH RAX
                         #x52            ; PUSH RDX
                         #x48 #x89 #xC8   ; MOV RAX, RCX
                         #x48 #x99       ; CQO
                         #x49 #xF7 #xFB   ; IDIV R11
                         #x49 #x89 #xC3   ; MOV R11, RAX (quotient)
                         #x5A            ; POP RDX
                         #x58            ; POP RAX
                         #x4C #x89 #xD8))) ; MOV RAX, R11
  (it "emit-vm-rem takes the remainder (RDX) branch of emit-idiv-sequence"
    (expect (%collect-emitted-octets
             (lambda (sink)
               (cl-cc/codegen::emit-vm-rem
                (cl-cc/vm:make-vm-rem :dst :r0 :lhs :r1 :rhs :r2) sink)))
            :to-equalp #(#x49 #x89 #xD3
                         #x50
                         #x52
                         #x48 #x89 #xC8
                         #x48 #x99
                         #x49 #xF7 #xFB
                         #x49 #x89 #xD3   ; MOV R11, RDX (remainder)
                         #x5A
                         #x58
                         #x4C #x89 #xD8))))

(describe-sequential "x86-64-emit-ops.lisp: define-cmp-emitter family (emit-vm-lt / emit-vm-eq)"
  ;; CMP lhs,rhs -> SETcc dst8 -> MOVZX dst64,dst8. EMIT-SETCC only emits a
  ;; REX prefix when its register code is >= 4 (SETcc needs REX to reach
  ;; SPL/BPL/SIL/DIL's low byte without the legacy AH/CH/DH/BH aliasing) --
  ;; covering both a dst < 4 (no REX on SETcc) and dst >= 4 (REX.B=0 on
  ;; SETcc) case.
  (it "emit-vm-lt (dst=RAX, code<4): CMP + SETL AL (no REX) + MOVZX RAX,AL"
    (expect (%collect-emitted-octets
             (lambda (sink)
               (cl-cc/codegen::emit-vm-lt
                (cl-cc/vm:make-vm-lt :dst :r0 :lhs :r1 :rhs :r2) sink)))
            :to-equalp #(#x48 #x39 #xD1   ; CMP RCX, RDX
                         #x0F #x9C #xC0   ; SETL AL
                         #x48 #x0F #xB6 #xC0))) ; MOVZX RAX, AL
  (it "emit-vm-eq (dst=RSI, code>=4): CMP + SETE SIL (REX.B=0 needed) + MOVZX RSI,SIL"
    (expect (%collect-emitted-octets
             (lambda (sink)
               (cl-cc/codegen::emit-vm-eq
                (cl-cc/vm:make-vm-eq :dst :r4 :lhs :r0 :rhs :r1) sink)))
            :to-equalp #(#x48 #x39 #xC8   ; CMP RAX, RCX
                         #x40 #x0F #x94 #xC6 ; SETE SIL (REX needed for SIL)
                         #x48 #x0F #xB6 #xF6)))) ; MOVZX RSI, SIL
