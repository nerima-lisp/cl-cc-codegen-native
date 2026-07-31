;;;; packages/emit/src/wasm-trampoline-proposals.lisp - misc + staged WAT ops
;;;
;;; Split out of wasm-trampoline.lisp in 2026-07. One-instruction WAT
;;; emitters that don't depend on trampoline dispatch state: bulk memory,
;;; copysign, saturating float-to-int conversion, sign extension, MVP bit
;;; ops, bulk table ops, sub-word atomics, and the Waves 11-15 low-priority
;;; WASM proposal helpers (128-bit i64 arithmetic, f16, typed continuations,
;;; stringref).

(in-package :cl-cc/codegen)

;;; ─────────────────────────────────────────────────────────────────────────────
;;; FR-228: Bulk Memory Operations helpers
;;; ─────────────────────────────────────────────────────────────────────────────

(defparameter *wasm-bulk-memory-enabled* t
  "Feature flag for Wasm Bulk Memory Operations proposal (FR-228).")

(defun wasm-memory-copy-wat (dst-offset-wat src-offset-wat size-wat
                             &key (dst-memory +wasm-memory-gc-heap+)
                                  (src-memory +wasm-memory-gc-heap+))
  "Return WAT for memory.copy (dst src size), optionally cross-memory."
  (wasm-memory-copy-wat* dst-offset-wat src-offset-wat size-wat
                         :dst-memory dst-memory
                         :src-memory src-memory))

(defun wasm-memory-fill-wat (dst-offset-wat value-wat size-wat
                             &key (memory-index +wasm-memory-gc-heap+))
  "Return WAT for memory.fill (dst value size), optionally selecting a memory."
  (if (wasm-multiple-memories-feature-enabled-p)
      (format nil "(memory.fill (memory ~D) ~A ~A ~A)"
              memory-index dst-offset-wat value-wat size-wat)
      (format nil "(memory.fill ~A ~A ~A)" dst-offset-wat value-wat size-wat)))

;;; ─────────────────────────────────────────────────────────────────────────────
;;; FR-324: copysign — float-sign implementation via f64.copysign
;;; ─────────────────────────────────────────────────────────────────────────────

(defun wasm-copysign-wat (magnitude-wat sign-wat)
  "Return WAT for f64.copysign (magnitude, sign) — IEEE 754 copySign operation."
  (format nil "(f64.copysign ~A ~A)" magnitude-wat sign-wat))

;;; ─────────────────────────────────────────────────────────────────────────────
;;; FR-326: memory.grow OOM detection — storage-condition on allocation failure
;;; ─────────────────────────────────────────────────────────────────────────────

(defparameter *wasm-memory-grow-oom-check-enabled* t
  "Feature flag for memory.grow OOM detection (FR-326).")

(defun wasm-storage-condition-wat ()
  "Return a staged symbol payload naming CL:STORAGE-CONDITION."
  (let* ((name "STORAGE-CONDITION")
         (bytes (map 'list #'char-code name))
         (byte-elems (format nil "~{~A~^ ~}"
                             (mapcar (lambda (b) (format nil "(i32.const ~D)" b)) bytes))))
    (format nil "(struct.new $symbol_t (struct.new $string_t (array.new_fixed $bytes_array_t ~D ~A)) (ref.null eq))"
            (length bytes)
            byte-elems)))

(defun wasm-memory-grow-checked-wat (pages-wat)
  "Return WAT for safe memory.grow with OOM check.
   Returns the active memory index type on success; signals STORAGE-CONDITION on OOM."
  (let ((result-type (wasm-memory-index-type-wat))
        (failed (if (wasm-memory64-feature-enabled-p) "(i64.const -1)" "(i32.const -1)")))
    (format nil "(if (result ~A) (~A.eq ~A ~A) (then (throw $cl_condition_tag (ref.null eq) ~A) (unreachable)) (else ~A))"
            result-type
            result-type
            (wasm-memory-grow-wat pages-wat)
            failed
            (wasm-storage-condition-wat)
            (wasm-memory-size-wat))))

(defun wasm-table-index-type-wat ()
  "Return the active table index type."
  (if (wasm-table64-feature-enabled-p) "i64" "i32"))

(defun wasm-table-const-wat (value)
  "Return VALUE as a table-index-width WAT constant."
  (format nil "(~A.const ~D)" (wasm-table-index-type-wat) value))

(defun wasm-table-index-from-eqref-wat (eqref-wat)
  "Return WAT that converts a boxed CL fixnum/closure entry to the table index type."
  (let ((i32 (format nil "(i31.get_s ~A)" eqref-wat)))
    (if (wasm-table64-feature-enabled-p)
        (format nil "(i64.extend_i32_u ~A)" i32)
        i32)))

(defun wasm-call-indirect-wat (type-name table-name index-wat &key tail-p)
  "Return call_indirect/return_call_indirect with table64-compatible index WAT."
  (format nil "(~A (type ~A) (table ~A~@[ i64~]) ~A)"
          (if tail-p "return_call_indirect" "call_indirect")
          type-name table-name (wasm-table64-feature-enabled-p) index-wat))

;;; ─────────────────────────────────────────────────────────────────────────────
;;; FR-233: Non-trapping float-to-int — saturating conversion helpers
;;; ─────────────────────────────────────────────────────────────────────────────

(defun wasm-trunc-sat-f64-i64-wat (f64-wat)
  "Return WAT for non-trapping f64→i64 conversion (saturating)."
  (format nil "(i64.trunc_sat_f64_s ~A)" f64-wat))

(defun wasm-trunc-sat-f64-i32-wat (f64-wat)
  "Return WAT for non-trapping f64→i32 conversion (saturating)."
  (format nil "(i32.trunc_sat_f64_s ~A)" f64-wat))

(defun wasm-trunc-sat-f32-i64-wat (f32-wat)
  "Return WAT for non-trapping f32→i64 conversion (saturating)."
  (format nil "(i64.trunc_sat_f32_s ~A)" f32-wat))

(defun wasm-trunc-sat-f32-i32-wat (f32-wat)
  "Return WAT for non-trapping f32→i32 conversion (saturating)."
  (format nil "(i32.trunc_sat_f32_s ~A)" f32-wat))

;;; ─────────────────────────────────────────────────────────────────────────────
;;; FR-234: Sign-extension — 1-instruction replacements for shift pairs
;;; ─────────────────────────────────────────────────────────────────────────────

(defun wasm-sign-extend-32-8-wat (i32-wat)
  "Return WAT for i32.extend8_s."
  (format nil "(i32.extend8_s ~A)" i32-wat))

(defun wasm-sign-extend-32-16-wat (i32-wat)
  "Return WAT for i32.extend16_s."
  (format nil "(i32.extend16_s ~A)" i32-wat))

(defun wasm-sign-extend-64-32-wat (i64-wat)
  "Return WAT for i64.extend32_s."
  (format nil "(i64.extend32_s ~A)" i64-wat))

(defun wasm-sign-extend-64-8-wat (i64-wat)
  "Return WAT for i64.extend8_s."
  (format nil "(i64.extend8_s ~A)" i64-wat))

(defun wasm-sign-extend-64-16-wat (i64-wat)
  "Return WAT for i64.extend16_s."
  (format nil "(i64.extend16_s ~A)" i64-wat))

;;; ─────────────────────────────────────────────────────────────────────────────
;;; FR-323: MVP Bit Operations — clz/ctz/popcnt for integer-length/logcount
;;; ─────────────────────────────────────────────────────────────────────────────

(defun wasm-i64-clz-wat (i64-wat)
  "Return WAT for i64.clz — count leading zeros."
  (format nil "(i64.clz ~A)" i64-wat))

(defun wasm-i64-ctz-wat (i64-wat)
  "Return WAT for i64.ctz — count trailing zeros."
  (format nil "(i64.ctz ~A)" i64-wat))

(defun wasm-i64-popcnt-wat (i64-wat)
  "Return WAT for i64.popcnt — population count."
  (format nil "(i64.popcnt ~A)" i64-wat))

;;; ─────────────────────────────────────────────────────────────────────────────
;;; FR-237: Bulk Table Operations helpers
;;; ─────────────────────────────────────────────────────────────────────────────

(defun emit-wasm-table-init-wat (table-name elem-name dst-offset-wat src-offset-wat size-wat)
  "Return WAT for table.init TABLE-NAME ELEM-NAME."
  (format nil "(table.init ~A ~A ~A ~A ~A)"
          table-name elem-name dst-offset-wat src-offset-wat size-wat))

(defun emit-wasm-table-copy-wat (dst-table-name src-table-name dst-offset-wat src-offset-wat size-wat)
  "Return WAT for table.copy DST-TABLE-NAME SRC-TABLE-NAME."
  (format nil "(table.copy ~A ~A ~A ~A ~A)"
          dst-table-name src-table-name dst-offset-wat src-offset-wat size-wat))

(defun emit-wasm-table-fill-wat (table-name dst-offset-wat value-wat size-wat)
  "Return WAT for table.fill TABLE-NAME."
  (format nil "(table.fill ~A ~A ~A ~A)"
          table-name dst-offset-wat value-wat size-wat))

(defun emit-wasm-elem-drop-wat (elem-name)
  "Return WAT for elem.drop ELEM-NAME."
  (format nil "(elem.drop ~A)" elem-name))

;;; ─────────────────────────────────────────────────────────────────────────────
;;; FR-327: Sub-word atomic WAT helpers
;;; ─────────────────────────────────────────────────────────────────────────────

(defun wasm-i32-atomic-rmw8-cmpxchg-u-wat (addr-wat expected-wat replacement-wat &key (align 1) (offset 0))
  "Return WAT for i32.atomic.rmw8.cmpxchg_u."
  (format nil "(i32.atomic.rmw8.cmpxchg_u align=~D offset=~D ~A ~A ~A)"
          align offset addr-wat expected-wat replacement-wat))

(defun wasm-i32-atomic-rmw16-cmpxchg-u-wat (addr-wat expected-wat replacement-wat &key (align 2) (offset 0))
  "Return WAT for i32.atomic.rmw16.cmpxchg_u."
  (format nil "(i32.atomic.rmw16.cmpxchg_u align=~D offset=~D ~A ~A ~A)"
          align offset addr-wat expected-wat replacement-wat))

(defun wasm-i32-atomic-rmw8-op-u-wat (op addr-wat value-wat &key (align 1) (offset 0))
  "Return WAT for an i32.atomic.rmw8.*_u operation."
  (format nil "(i32.atomic.rmw8.~A_u align=~D offset=~D ~A ~A)"
          op align offset addr-wat value-wat))

(defun wasm-i32-atomic-rmw16-op-u-wat (op addr-wat value-wat &key (align 2) (offset 0))
  "Return WAT for an i32.atomic.rmw16.*_u operation."
  (format nil "(i32.atomic.rmw16.~A_u align=~D offset=~D ~A ~A)"
          op align offset addr-wat value-wat))

;;; ─────────────────────────────────────────────────────────────────────────────
;;; Waves 11-15 low-priority proposal WAT helpers
;;; ─────────────────────────────────────────────────────────────────────────────

(defun wasm-i64-add128-wat (lo-lhs-wat hi-lhs-wat lo-rhs-wat hi-rhs-wat)
  "FR-238: Return WAT for i64.add128."
  (format nil "(i64.add128 ~A ~A ~A ~A)" lo-lhs-wat hi-lhs-wat lo-rhs-wat hi-rhs-wat))

(defun wasm-i64-sub128-wat (lo-lhs-wat hi-lhs-wat lo-rhs-wat hi-rhs-wat)
  "FR-238: Return WAT for i64.sub128."
  (format nil "(i64.sub128 ~A ~A ~A ~A)" lo-lhs-wat hi-lhs-wat lo-rhs-wat hi-rhs-wat))

(defun wasm-i64-mul-wide-s-wat (lhs-wat rhs-wat)
  "FR-238: Return WAT for signed i64.mul_wide_s."
  (format nil "(i64.mul_wide_s ~A ~A)" lhs-wat rhs-wat))

(defun wasm-i64-mul-wide-u-wat (lhs-wat rhs-wat)
  "FR-238: Return WAT for unsigned i64.mul_wide_u."
  (format nil "(i64.mul_wide_u ~A ~A)" lhs-wat rhs-wat))

(defun wasm-memory-discard-wat (offset-wat length-wat &key (memory-index nil))
  "FR-243: Return WAT for memory.discard."
  (format nil "(memory.discard~@[ (memory ~D)~] ~A ~A)"
          (and (wasm-multiple-memories-feature-enabled-p) memory-index)
          offset-wat length-wat))

(defun wasm-f16-binop-wat (op lhs-wat rhs-wat)
  "FR-248: Return WAT for an f16 binary operation OP."
  (format nil "(f16.~A ~A ~A)" op lhs-wat rhs-wat))

(defun wasm-f16-load-wat (addr-wat &key (align 2) (offset 0))
  "FR-248: Return WAT for f16.load."
  (format nil "(f16.load align=~D offset=~D ~A)" align offset addr-wat))

(defun wasm-f16-store-wat (addr-wat value-wat &key (align 2) (offset 0))
  "FR-248: Return WAT for f16.store."
  (format nil "(f16.store align=~D offset=~D ~A ~A)" align offset addr-wat value-wat))

(defun wasm-f16-convert-f32-wat (f32-wat)
  "FR-248: Return WAT for f16.convert_f32."
  (format nil "(f16.convert_f32 ~A)" f32-wat))

(defun wasm-f32-convert-f16-wat (f16-wat)
  "FR-248: Return WAT for f32.convert_f16."
  (format nil "(f32.convert_f16 ~A)" f16-wat))

(defun wasm-stringref-length-wat (string-wat)
  "FR-251: Return WAT for native stringref length."
  (format nil "(string.length ~A)" string-wat))

(defun wasm-stringref-get-codeunit-wat (string-wat index-wat)
  "FR-251: Return WAT for native stringref code-unit access."
  (format nil "(string.get_codeunit ~A ~A)" string-wat index-wat))

(defun wasm-func-bind-wat (type-name func-wat &rest bound-args)
  "FR-290: Return WAT for func.bind partial application."
  (format nil "(func.bind (type ~A) ~A~{ ~A~})" type-name func-wat bound-args))

(defun wasm-cont-new-wat (type-name func-wat)
  "FR-205: Return WAT for cont.new."
  (format nil "(cont.new (type ~A) ~A)" type-name func-wat))

(defun wasm-cont-bind-wat (type-name cont-wat &rest bound-args)
  "FR-205: Return WAT for cont.bind."
  (format nil "(cont.bind (type ~A) ~A~{ ~A~})" type-name cont-wat bound-args))

(defun wasm-suspend-wat (tag-name &rest args)
  "FR-205: Return WAT for suspend."
  (format nil "(suspend ~A~{ ~A~})" tag-name args))

(defun wasm-resume-wat (cont-wat &rest args)
  "FR-205: Return WAT for resume."
  (format nil "(resume ~A~{ ~A~})" cont-wat args))

(defun wasm-cont-throw-wat (cont-wat exnref-wat)
  "FR-301: Return WAT for cont.throw."
  (format nil "(cont.throw ~A ~A)" cont-wat exnref-wat))

(defun wasm-effect-perform-wat (effect-name &rest args)
  "FR-272: Return WAT for an algebraic effect perform placeholder."
  (format nil "(perform ~A~{ ~A~})" effect-name args))

(defun wasm-flexible-vector-op-wat (op lhs-wat rhs-wat &key (width :v128x2))
  "FR-246: Return WAT for flexible-vector OP at WIDTH (:V128X2 or :V512)."
  (let ((prefix (ecase width
                  (:v128x2 "v128x2")
                  (:v512 "v512"))))
    (format nil "(~A.~A ~A ~A)" prefix op lhs-wat rhs-wat)))

(defun wasm-startup-snapshot-comment-wat (&optional (name "module.wasm.snap"))
  "FR-287: Return a WAT comment documenting the snapshot sidecar."
  (format nil ";; FR-287 startup snapshot sidecar: ~A" name))
