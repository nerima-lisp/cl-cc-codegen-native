;;;; packages/emit/src/wasm-trampoline-fixnum.lisp - i31ref fixnum boxing + closures
;;;
;;; Split out of wasm-trampoline.lisp in 2026-07. FR-209 fixnum range
;;; analysis and i31ref boxing/unboxing, FR-145 unboxed-register tracking,
;;; multi-value block WAT, closure allocation/reference, and the i64
;;; binop/cmp + basic-block jump helpers that build on them.

(in-package :cl-cc/codegen)

;;; ─────────────────────────────────────────────────────────────────────────────
;;; FR-209: i31ref fixnum native boxing/range analysis helpers
;;; ─────────────────────────────────────────────────────────────────────────────

(defconstant +wasm-i31-min+ (- (expt 2 30))
  "Minimum signed integer representable by Wasm GC i31ref.")

(defconstant +wasm-i31-max+ (1- (expt 2 30))
  "Maximum signed integer representable by Wasm GC i31ref.")

(defun wasm-i31-range-p (value)
  "Return true when integer VALUE fits in signed Wasm i31ref payload bits."
  (and (integerp value)
       (<= +wasm-i31-min+ value +wasm-i31-max+)))

(defun reg-record-fixnum-range (reg-map reg range)
  "Record RANGE for REG and mark REG as an i31ref fixnum when FR-209 is enabled."
  (when *wasm-i31ref-optimize-enabled*
    (reg-record-type reg-map reg :i31ref)
    (let ((ranges (wasm-reg-map-fixnum-ranges reg-map)))
      (when ranges (setf (gethash reg ranges) range)))))

(defun reg-known-fixnum-range (reg-map reg)
  "Return the known fixnum range for REG, or NIL when unknown."
  (let ((ranges (wasm-reg-map-fixnum-ranges reg-map)))
    (and ranges (gethash reg ranges))))

(defun wasm-range-binop (lhs-range rhs-range op)
  "Conservatively compute a result range for integer OP over LHS/RHS ranges."
  (when (and (consp lhs-range) (consp rhs-range))
    (let ((a (car lhs-range)) (b (cdr lhs-range))
          (c (car rhs-range)) (d (cdr rhs-range)))
      (cond
        ((string= op "i64.add") (cons (+ a c) (+ b d)))
        ((string= op "i64.sub") (cons (- a d) (- b c)))
        ((string= op "i64.mul")
         (let ((values (list (* a c) (* a d) (* b c) (* b d))))
           (cons (apply #'min values) (apply #'max values))))
        ((member op '("i64.and" "i64.or" "i64.xor") :test #'string=)
         (cons +wasm-i31-min+ +wasm-i31-max+))
        (t nil)))))

(defun wasm-range-unary (src-range format-string)
  "Conservatively compute a result range for a unary fixnum format string."
  (when (consp src-range)
    (cond
      ((string= format-string "(i64.add ~A (i64.const 1))")
       (cons (1+ (car src-range)) (1+ (cdr src-range))))
      ((string= format-string "(i64.sub ~A (i64.const 1))")
       (cons (1- (car src-range)) (1- (cdr src-range))))
      ((string= format-string "(i64.sub (i64.const 0) ~A)")
       (cons (- (cdr src-range)) (- (car src-range))))
      ((or (search "popcnt" format-string)
           (search "clz" format-string)
           (search "ctz" format-string))
       (cons 0 64))
      (t nil))))

(defun wasm-range-i31-or-unknown (range)
  "Return RANGE if it fits i31ref, otherwise the conservative i31 range."
  (if (and (consp range)
           (wasm-i31-range-p (car range))
           (wasm-i31-range-p (cdr range)))
      range
      (cons +wasm-i31-min+ +wasm-i31-max+)))

(defun wasm-i64-const-wat-value (wat)
  "Return integer N for WAT of the form (i64.const N), else NIL."
  (when (stringp wat)
    (let ((prefix "(i64.const "))
      (when (and (>= (length wat) (+ (length prefix) 2))
                 (string= wat prefix :end1 (length prefix))
                 (char= (char wat (1- (length wat))) #\)))
        (ignore-errors
          (parse-integer wat :start (length prefix) :end (1- (length wat))))))))

(defun wasm-i64-extended-i31-source (wat)
  "Return X from WAT shaped as (i64.extend_i32_s (i31.get_s X)), else NIL."
  (when (stringp wat)
    (let ((prefix "(i64.extend_i32_s (i31.get_s "))
      (when (and (>= (length wat) (+ (length prefix) 2))
                 (string= wat prefix :end1 (length prefix)))
        (subseq wat (length prefix) (- (length wat) 2))))))

(defun wasm-ref-cast-maybe (type-wat reg-map reg)
  "Return WAT for a ref.cast to TYPE-WAT for register REG, 
   SKIPPING the cast when FR-142 determines the register's type is already known
   to match TYPE-WAT."
  (if *wasm-ref-cast-elimination-enabled*
      (let ((known (reg-known-type reg-map reg)))
        (if (or (and (eq known :cons) (string= type-wat "(ref $cons_t)"))
                (and (eq known :closure) (string= type-wat "(ref $closure_t)"))
                (and (eq known :string) (string= type-wat "(ref $string_t)"))
                (and (eq known :symbol) (string= type-wat "(ref $symbol_t)")))
            (reg-local-ref reg-map reg)
            (format nil "(ref.cast ~A ~A)" type-wat
                    (wasm-ref-as-non-null-wat (reg-local-ref reg-map reg)))))
      (format nil "(ref.cast ~A ~A)" type-wat
              (wasm-ref-as-non-null-wat (reg-local-ref reg-map reg)))))

(defun wasm-eq-wat (reg-map lhs rhs)
  "Return CL EQ/EQL comparison WAT.  Known fixnums compare numerically; GC refs use ref.eq."
  (let ((lhs-known (reg-known-type reg-map lhs))
        (rhs-known (reg-known-type reg-map rhs)))
    (if (and (eq lhs-known :i31ref) (eq rhs-known :i31ref))
        (format nil "(i64.eq ~A ~A)"
                (wasm-fixnum-unbox reg-map lhs)
                (wasm-fixnum-unbox reg-map rhs))
        (wasm-ref-eq-wat (reg-local-ref reg-map lhs)
                         (reg-local-ref reg-map rhs)))))

(defun wasm-fixnum-unbox (reg-map reg &key (result-type :i64))
  "Unbox a native i31ref fixnum.

RESULT-TYPE selects the consumer width.  :I64 preserves the historical fixnum
arithmetic path with i64.extend_i32_s; :I32 emits direct i31.get_s for Wasm
consumers that already accept i32, skipping the extend/wrap pair."
  (let* ((ref (reg-local-ref reg-map reg))
         (known (and *wasm-i31ref-optimize-enabled* (reg-known-type reg-map reg)))
         (i32-wat (format nil "(i31.get_s ~A)" ref)))
    (case result-type
      (:i32 i32-wat)
      (:i64 (if (and *wasm-i31ref-optimize-enabled* (eq known :i64-unboxed))
                ref
                (format nil "(i64.extend_i32_s ~A)" i32-wat)))
      (otherwise (error "Unsupported wasm-fixnum-unbox result type: ~S" result-type)))))

(defun wasm-fixnum-box (i64-wat)
  "Box an integer expression as an i31ref fixnum.

FR-209 optimizes constant i31 values to direct i32.const and removes dead
box/unbox pairs by returning the original i31ref expression when boxing a value
that was just unboxed from i31ref."
  (if *wasm-i31ref-optimize-enabled*
      (let ((const (wasm-i64-const-wat-value i64-wat))
            (inner-i31 (wasm-i64-extended-i31-source i64-wat)))
        (cond
          ((and const (wasm-i31-range-p const))
           (format nil "(ref.i31 (i32.const ~D))" const))
          (inner-i31 inner-i31)
          (t (format nil "(ref.i31 (i32.wrap_i64 ~A))" i64-wat))))
      (format nil "(ref.i31 (i32.wrap_i64 ~A))" i64-wat)))

;;; ─────────────────────────────────────────────────────────────────────────────
;;; FR-145: Integer Range Annotation — fixnum unboxed register tracking
;;; ─────────────────────────────────────────────────────────────────────────────

(defvar *wasm-fixnum-unboxed-regs* nil
  "Dynamic binding: hash table mapping VM register keyword → integer constant value
   when the register holds a known fixnum constant that can be used as raw i64.
   Set by vm-const emit when the const value is an integer (FR-145).")

(defun wasm-fixnum-unboxed-reg-p (reg-map reg)
  "Return the integer constant REG holds, or NIL if not a known fixnum constant.
FR-145: Checks *wasm-fixnum-unboxed-regs* table for the register."
  (declare (ignore reg-map))
  (and *wasm-fixnum-unboxed-regs*
       (gethash reg *wasm-fixnum-unboxed-regs*)))

(defun wasm-mark-reg-unboxed-fixnum (reg value)
  "Mark REG as holding an unboxed i64 constant VALUE (FR-145)."
  (when *wasm-fixnum-unboxed-regs*
    (setf (gethash reg *wasm-fixnum-unboxed-regs*) value)))

(defun wasm-clear-reg-unboxed-fixnum (reg)
  "Clear the unboxed-fixnum mark for REG (FR-145)."
  (when *wasm-fixnum-unboxed-regs*
    (remhash reg *wasm-fixnum-unboxed-regs*)))

(defun wasm-bool-to-i31 (cond-wat)
  "Convert a WASM i32 boolean (0/1) to i31ref (nil/t).
   0 -> ref.null eq (nil), 1 -> (ref.i31 (i32.const 1)) (truthy)."
  (format nil "(if (result eqref) ~A (then (ref.i31 (i32.const 1))) (else (ref.null eq)))"
          cond-wat))

(defun wasm-block-result-types-wat (types)
  "Return a WAT block result type clause for TYPES, e.g. (result f64 i32)."
  (if types
      (format nil "(result~{ ~A~})" types)
      ""))

(defun wasm-values-multi-value-block-wat (reg-map dst src-regs &key (indent 0))
  "Return FR-235 WAT that materializes values through a multi-value block."
  (let ((prefix (make-string indent :initial-element #\Space))
        (values (or src-regs nil)))
    (if (null values)
        (format nil "~A;; FR-235 multi-value block: zero values~%~A~A"
                prefix prefix (reg-local-set reg-map dst "(ref.null eq)"))
        (with-output-to-string (s)
          (format s "~A;; FR-235 wasm multi-value block path" prefix)
          (format s "~%~A(block ~A" prefix
                  (wasm-block-result-types-wat (make-list (length values) :initial-element "eqref")))
          (dolist (reg values)
            (format s "~%~A  ~A" prefix (reg-local-ref reg-map reg)))
          (format s "~%~A)" prefix)
          (loop repeat (1- (length values))
                do (format s "~%~A(drop)" prefix))
          (format s "~%~A(local.set ~D)" prefix (wasm-reg-to-local reg-map dst))))))

(defun wasm-values-wat (reg-map dst src-regs &key (indent 0))
  "Return WAT for vm-values using the FR-235 multi-value block representation."
  (wasm-values-multi-value-block-wat reg-map dst src-regs :indent indent))

(defun %wasm-captured-value-reg (capture)
  "Return the VM register carrying CAPTURE's value."
  (if (consp capture) (cdr capture) capture))

(defun emit-wasm-typed-closure-alloc (reg-map dst entry-index captured stream prefix)
  "FR-144 typed-env path: build the closure environment with array.new_fixed and
wrap the typed (ref $eqref_array_t) directly in $closure_t, skipping the $env_t
struct.  FR-142: keep the array.new_fixed result typed to avoid a redundant ref.cast."
  (format stream "~%~A;; FR-144: typed closure env using array.new_fixed" prefix)
  (format stream "~%~A(local.set ~D (array.new_fixed $eqref_array_t ~D~{ ~A~}))"
           prefix (wasm-reg-map-tmp-index reg-map)
           (length captured)
           (loop for capture in captured
                 for reg = (%wasm-captured-value-reg capture)
                 collect (reg-local-ref reg-map reg)))
  (format stream "~%~A~A"
          prefix
          (reg-local-set
            reg-map dst
             (format nil "(struct.new $closure_t ~A (ref.cast (ref $eqref_array_t) (local.get ~D)))"
                     (wasm-table-const-wat entry-index)
                     (wasm-reg-map-tmp-index reg-map))))
  (reg-record-type reg-map dst :closure))

(defun emit-wasm-boxed-closure-alloc (reg-map dst entry-index captured stream prefix)
  "Env-struct path: allocate a mutable $eqref_array_t, populate it via array.set,
then wrap it in an $env_t struct inside $closure_t."
  (let ((tmp (wasm-reg-map-tmp-index reg-map)))
    (format stream "~%~A(local.set ~D (array.new $eqref_array_t (ref.null eq) (i32.const ~D)))"
            prefix tmp (length captured))
    (loop for capture in captured
          for idx from 0
          for reg = (%wasm-captured-value-reg capture)
          do (format stream "~%~A(array.set $eqref_array_t (ref.cast (ref $eqref_array_t) (local.get ~D)) (i32.const ~D) ~A)"
                     prefix tmp idx (reg-local-ref reg-map reg)))
    (format stream "~%~A~A"
            prefix
            (reg-local-set
             reg-map dst
              (format nil "(struct.new $closure_t ~A (struct.new $env_t (ref.cast (ref $eqref_array_t) (local.get ~D)) (ref.null $env_t)))"
                      (wasm-table-const-wat entry-index) tmp)))
    (reg-record-type reg-map dst :closure)))

(defun emit-wasm-closure-allocation (reg-map dst entry-index captured stream indent)
  "Emit closure allocation using $closure_t and $env_t GC structs.
   FR-144: When *wasm-typed-closure-env-enabled*, uses array.new_fixed directly
   for the environment instead of wrapping in $env_t struct + array.new/set loop.
   FR-142: Records the closure type on the destination register for ref.cast elimination.
   
Captured values are materialized into a mutable $eqref_array_t with array.new and
array.set before the closure struct is created.

FR-142: Eliminate redundant ref.cast by using local.tee pattern.  When array.new
returns (ref $eqref_array_t), we use local.tee to keep the typed ref available on
the stack for immediate use, avoiding one ref.cast per closure construction.

FR-144: Use typed closure environment array via array.new_fixed eqref for direct
index access instead of the intermediate $env_t struct wrapper."
  (let ((prefix (make-string indent :initial-element #\Space)))
    (cond
      ((and captured *wasm-typed-closure-env-enabled*)
       (emit-wasm-typed-closure-alloc reg-map dst entry-index captured stream prefix))
      (captured
       (emit-wasm-boxed-closure-alloc reg-map dst entry-index captured stream prefix))
      (t
       (format stream "~%~A~A"
                prefix
                (reg-local-set
                 reg-map dst
                  (format nil "(struct.new $closure_t ~A ~A)"
                          (wasm-table-const-wat entry-index)
                          (if *wasm-typed-closure-env-enabled*
                              "(ref.null $eqref_array_t)"
                              "(ref.null $env_t)"))))
       (reg-record-type reg-map dst :closure)))))

(defun wasm-closure-ref-wat (reg-map closure-reg index)
  "Return WAT for reading captured INDEX from CLOSURE-REG.
   FR-144: When typed env enabled, uses array.get directly on env field."
  (if *wasm-typed-closure-env-enabled*
      (format nil "(array.get $eqref_array_t (ref.cast (ref $eqref_array_t) (struct.get $closure_t 1 ~A)) (i32.const ~D))"
              (wasm-ref-cast-maybe "(ref $closure_t)" reg-map closure-reg)
              index)
      (format nil "(array.get $eqref_array_t (struct.get $env_t 0 (ref.cast (ref $env_t) (struct.get $closure_t 1 ~A))) (i32.const ~D))"
              (wasm-ref-cast-maybe "(ref $closure_t)" reg-map closure-reg)
              index)))

;;; ─────────────────────────────────────────────────────────────────────────────
;;; Fixnum operation helpers (used by emit-trampoline-instruction)
;;; ─────────────────────────────────────────────────────────────────────────────

(defun wasm-i64-binop (reg-map dst lhs rhs op)
  "WAT for: dst = box(op(unbox(lhs), unbox(rhs)))."
  (let* ((result-range (wasm-range-i31-or-unknown
                        (wasm-range-binop (reg-known-fixnum-range reg-map lhs)
                                          (reg-known-fixnum-range reg-map rhs)
                                          op)))
         (wat (reg-local-set reg-map dst
                             (wasm-fixnum-box
                              (format nil "(~A ~A ~A)" op
                                      (wasm-fixnum-unbox reg-map lhs)
                                      (wasm-fixnum-unbox reg-map rhs))))))
    (reg-record-fixnum-range reg-map dst result-range)
    wat))

(defun wasm-i64-cmp (reg-map dst lhs rhs cmp-op)
  "WAT for: dst = T if cmp-op(unbox(lhs), unbox(rhs)), else NIL."
  (reg-local-set reg-map dst
                 (wasm-bool-to-i31
                  (format nil "(~A ~A ~A)" cmp-op
                          (wasm-fixnum-unbox reg-map lhs)
                          (wasm-fixnum-unbox reg-map rhs)))))

(defun emit-trampoline-jump-to-label (label-name label-pc-map reg-map stream)
  "Emit WAT to set $pc to the index for LABEL-NAME and branch back to $dispatch.
    FR-143: When tail-calls enabled and label has a known table entry, 
    emit return_call_indirect directly without the br $dispatch."
  (let ((table-idx (and *wasm-tail-call-enabled*
                        *wasm-label-to-table-idx*
                        (gethash label-name *wasm-label-to-table-idx*))))
    (if table-idx
        (format stream "~%      ;; FR-143: direct tail dispatch to function label ~S~%      ~A"
                label-name
                (wasm-call-indirect-wat "$main_func_t" "$funcref_table"
                                        (wasm-table-const-wat table-idx)
                                        :tail-p t))
        (let ((pc-idx (gethash label-name label-pc-map)))
          (if pc-idx
              (format stream "~%      (local.set ~D (i32.const ~D))"
                      (wasm-reg-map-pc-index reg-map) pc-idx)
              (format stream "~%      ;; WARNING: unknown label ~S" label-name))
          (format stream "~%      (br $dispatch)")))))
