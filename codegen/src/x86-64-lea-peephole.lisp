;;;; x86-64-lea-peephole.lisp — VM-instruction-level LEA/BEXTR fusion
;;;;
;;;; A pre-encoding peephole pass: matches short runs of VM instructions
;;;; (const+shift+add, const+scale+add, bit-extract-via-shift-and-mask) and
;;;; fuses them into a single internal LEA or BEXTR instruction. Split out
;;;; of x86-64-codegen-emitters.lisp (2026-07) as its own cohesive concern
;;;; -- distinct from that file's function prologue/epilogue/CFI setup and
;;;; from the byte-level, post-encoding rewriting in x86-64-peephole.lisp,
;;;; which decodes and rewrites already-encoded machine code rather than
;;;; matching VM instructions.

(in-package :cl-cc/codegen)

(defun x86-64-lea-valid-index-p (reg)
  "Return true when physical REG is valid as an x86-64 SIB index."
  (and reg (/= (logand reg #x7) 4)))

(defun x86-64-lea-scale-p (scale)
  "Return true when SCALE is encodable by x86-64 LEA."
  (member scale '(1 2 4 8) :test #'=))

(defun x86-64-power-of-two-scale-from-shift (shift)
  "Return LEA scale for non-negative SHIFT values 0..3, otherwise NIL.
LEA addressing scales are powers of two (1, 2, 4, 8), so this is
2^SHIFT rather than a lookup table."
  (and (integerp shift) (<= 0 shift 3) (ash 1 shift)))

(defun x86-64-vm-int-const-p (inst)
  "Return true when INST is an integer VM constant."
  (and (typep inst 'vm-const)
       (let ((value (vm-value inst)))
         (or (integerp value)
             (null value)
             (eq value t)))))

(defun x86-64-vm-const-reg-value (inst)
  "Return two values: destination register and integer value for VM-CONST INST."
  (values (vm-dst inst) (vm-const-to-integer (vm-value inst))))

(defun x86-64-count-register-uses (instructions)
  "Return a hash table mapping VM registers to use counts in INSTRUCTIONS."
  (let ((uses (make-hash-table :test #'eq)))
    (labels ((use (reg)
               (when reg
                 (incf (gethash reg uses 0)))))
      (dolist (inst instructions uses)
        (dolist (reg (instruction-uses inst))
          (use reg))))))

(defun x86-64-single-use-const-p (inst uses)
  "Return true when INST is an integer constant used exactly once."
  (and (x86-64-vm-int-const-p inst)
       (= (gethash (vm-dst inst) uses 0) 1)))

(defun x86-64-commutative-add-with-reg-p (inst dst reg)
  "Return the other addend when INST computes DST = REG + other, else NIL."
  (when (and (typep inst '(or vm-add vm-integer-add))
             (eq (vm-dst inst) dst))
    (cond
      ((eq (vm-lhs inst) reg) (vm-rhs inst))
      ((eq (vm-rhs inst) reg) (vm-lhs inst))
      (t nil))))

(defun x86-64-lea-internal (dst-reg base-reg index-reg scale displacement)
  "Build an internal LEA instruction from VM registers when encodable."
  (let ((dst (vm-reg-to-x86 dst-reg))
        (base (vm-reg-to-x86 base-reg))
        (index (and index-reg (vm-reg-to-x86 index-reg))))
    (when (and (typep displacement '(signed-byte 32))
               (or (null index)
                   (and (x86-64-lea-valid-index-p index)
                        (x86-64-lea-scale-p scale))))
      (make-x86-64-lea-address :dst dst
                                :base base
                                :index index
                                :scale scale
                                :displacement displacement))))

(defun x86-64-match-lea-pattern (instructions uses)
  "Try to consume a LEA-able prefix of INSTRUCTIONS.

Returns two values: the replacement instruction and the number of source
instructions consumed."
  (flet ((%try-lea-with-optional-disp (accum-reg base-reg index-reg scale i3 i4)
           "Shared tail for the shift/scale LEA patterns: try a 5-instruction
match with a trailing constant-displacement add, else a 3-instruction match
with no displacement. Returns (values lea count), or (values nil 0) when
neither shape matches."
           (cond
             ((and i3 i4
                   (x86-64-single-use-const-p i3 uses)
                   (x86-64-commutative-add-with-reg-p i4 accum-reg accum-reg))
              (multiple-value-bind (disp-reg disp) (x86-64-vm-const-reg-value i3)
                (if (eq (x86-64-commutative-add-with-reg-p i4 accum-reg accum-reg) disp-reg)
                    (let ((lea (x86-64-lea-internal accum-reg base-reg index-reg scale disp)))
                      (if lea (values lea 5) (values nil 0)))
                    (values nil 0))))
             (t
              (let ((lea (x86-64-lea-internal accum-reg base-reg index-reg scale 0)))
                (if lea (values lea 3) (values nil 0)))))))
    (destructuring-bind (i0 &optional i1 i2 i3 i4 &rest rest) instructions
      (declare (ignore rest))
      ;; const shift, ash r,r,shift, add r,base, [const disp, add r,disp]
      (when (and i1 i2
                 (x86-64-single-use-const-p i0 uses)
                 (typep i1 (quote vm-ash)))
        (multiple-value-bind (shift-reg shift) (x86-64-vm-const-reg-value i0)
          (let* ((accum-reg (vm-dst i1))
                 (index-reg (vm-lhs i1))
                 (scale (x86-64-power-of-two-scale-from-shift shift))
                 (base-reg (and scale
                                (eq (vm-rhs i1) shift-reg)
                                (x86-64-commutative-add-with-reg-p i2 accum-reg accum-reg))))
            (when base-reg
              (multiple-value-bind (lea count)
                  (%try-lea-with-optional-disp accum-reg base-reg index-reg scale i3 i4)
                (when lea (return-from x86-64-match-lea-pattern (values lea count))))))))
      ;; const scale, mul r,r,scale, add r,base, [const disp, add r,disp]
      (when (and i1 i2
                 (x86-64-single-use-const-p i0 uses)
                 (typep i1 (quote (or vm-mul vm-integer-mul))))
        (multiple-value-bind (scale-reg scale) (x86-64-vm-const-reg-value i0)
          (let* ((accum-reg (vm-dst i1))
                 (index-reg (vm-lhs i1))
                 (base-reg (and (x86-64-lea-scale-p scale)
                                (eq (vm-rhs i1) scale-reg)
                                (x86-64-commutative-add-with-reg-p i2 accum-reg accum-reg))))
            (when base-reg
              (multiple-value-bind (lea count)
                  (%try-lea-with-optional-disp accum-reg base-reg index-reg scale i3 i4)
                (when lea (return-from x86-64-match-lea-pattern (values lea count))))))))
      ;; add r,base, const disp, add r,disp => lea r,[base + r + disp]
      (when (and i1 i2
                 (typep i0 (quote (or vm-add vm-integer-add)))
                 (x86-64-single-use-const-p i1 uses)
                 (typep i2 (quote (or vm-add vm-integer-add))))
        (let* ((dst-reg (vm-dst i0))
               (index-reg (vm-lhs i0))
               (base-reg (vm-rhs i0)))
          (unless (eq (vm-dst i0) (vm-lhs i0))
            (when (eq (vm-dst i0) (vm-rhs i0))
              (rotatef index-reg base-reg)))
          (when (and base-reg (eq (vm-dst i2) dst-reg))
            (multiple-value-bind (disp-reg disp) (x86-64-vm-const-reg-value i1)
              (when (eq (x86-64-commutative-add-with-reg-p i2 dst-reg dst-reg) disp-reg)
                (let ((lea (x86-64-lea-internal dst-reg base-reg index-reg 1 disp)))
                  (when lea (return-from x86-64-match-lea-pattern (values lea 3)))))))))
      (values nil 0))))

(defun x86-64-contiguous-low-mask-width (mask)
  "Return WIDTH when MASK is 2^WIDTH-1, otherwise NIL."
  (when (and (integerp mask) (>= mask 0))
    (let ((width (integer-length mask)))
      (when (= mask (1- (ash 1 width)))
        width))))

(defun x86-64-match-bextr-pattern (instructions uses)
  "Try to consume (ash SRC -START) followed by a low-bit mask as BEXTR."
  (destructuring-bind (i0 &optional i1 i2 i3 &rest rest) instructions
    (declare (ignore rest))
    (when (and i1 i2 i3
               (x86-64-single-use-const-p i0 uses)
               (typep i1 'vm-ash)
               (x86-64-single-use-const-p i2 uses)
               (typep i3 'vm-logand))
      (multiple-value-bind (shift-reg shift) (x86-64-vm-const-reg-value i0)
        (multiple-value-bind (mask-reg mask) (x86-64-vm-const-reg-value i2)
          (let* ((shifted-reg (vm-dst i1))
                 (src-reg (vm-lhs i1))
                 (start (and (integerp shift) (minusp shift) (- shift)))
                 (width (x86-64-contiguous-low-mask-width mask)))
            (when (and start width
                       (< 0 width 64)
                       (< start 64)
                       (<= (+ start width) 64)
                       (eq (vm-rhs i1) shift-reg)
                       (or (and (eq (vm-lhs i3) shifted-reg)
                                (eq (vm-rhs i3) mask-reg))
                           (and (eq (vm-rhs i3) shifted-reg)
                                (eq (vm-lhs i3) mask-reg))))
              (return-from x86-64-match-bextr-pattern
                (values (make-x86-64-bextr-field
                         :dst (vm-reg-to-x86 (vm-dst i3))
                          :src (vm-reg-to-x86 src-reg)
                          :start start
                          :width width)
                         4)))))))
    (values nil 0)))

(defun emit-x86-64-bextr-field-inst (inst stream)
  "Emit internal BEXTR using R11 as the BMI control register."
  (emit-mov-ri64 +r11+
                 (logior (x86-64-bextr-field-start inst)
                         (ash (x86-64-bextr-field-width inst) 8))
                 stream)
  (emit-bextr-rrr64 (x86-64-bextr-field-dst inst)
                    (x86-64-bextr-field-src inst)
                    +r11+
                    stream))

(defun x86-64-peephole-lea-addresses (instructions)
  "Replace LEA-able arithmetic/address and BMI bit-field runs with internal ops."
  (let ((uses (x86-64-count-register-uses instructions))
        (result '())
        (remaining instructions))
    (loop while remaining
          do (multiple-value-bind (replacement consumed)
                  (multiple-value-bind (bextr bextr-consumed)
                      (x86-64-match-bextr-pattern remaining uses)
                    (if bextr
                        (values bextr bextr-consumed)
                        (x86-64-match-lea-pattern remaining uses)))
                (if replacement
                    (progn
                      (push replacement result)
                     (setf remaining (nthcdr consumed remaining)))
                    (progn
                      (push (first remaining) result)
                      (setf remaining (rest remaining))))))
    (nreverse result)))
