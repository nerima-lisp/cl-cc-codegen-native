;;;; tests/unit/emit/x86-64-emit-ops-tests.lisp
;;;; Unit tests for src/emit/x86-64-emit-ops.lisp
;;;;
;;;; Covers: emit-vm-const, emit-vm-move, float-binary emitters,
;;;;   integer alu (add/sub/mul), truncate/rem, div/mod,
;;;;   comparison emitters (lt/gt/le/ge/num-eq/eq),
;;;;   unary emitters (neg/not/lognot/logcount/integer-length/bswap/inc/dec/abs),
;;;;   emit-vm-ash, emit-vm-rotate, emit-vm-min/max, emit-vm-select.
;;;;
;;;; Strategy: emit each instruction into a byte-collecting lambda stream,
;;;;   verify byte count matches the documented layout or is non-empty.

(in-package :cl-cc/codegen-native/targets/x86-64/test)

;;; ─── Helper ──────────────────────────────────────────────────────────────

(defun %collect-emit-ops-bytes (emit-fn inst)
  "Collect bytes emitted by EMIT-FN for INST into a list."
  (let ((bytes nil))
    (funcall emit-fn inst (lambda (b) (push b bytes)))
    (nreverse bytes)))

;;; ─── emit-vm-const ───────────────────────────────────────────────────────

(it-sequential "x86-emit-const-cases integer"
  (destructuring-bind (inst) (list (cl-cc/vm:make-vm-const :dst :r0 :value 42))
    (expect (> (length (%collect-emit-ops-bytes #'cl-cc/codegen-native/targets/x86-64::emit-vm-const inst)) 0) :to-be-truthy)))

(it-sequential "x86-emit-const-cases float"
  (destructuring-bind (inst) (list (cl-cc/vm:make-vm-const :dst :r0 :value 3.14d0))
    (expect (> (length (%collect-emit-ops-bytes #'cl-cc/codegen-native/targets/x86-64::emit-vm-const inst)) 0) :to-be-truthy)))

;;; ─── emit-vm-move ────────────────────────────────────────────────────────

(it-sequential "x86-emit-move-between-gp-regs"
  (let* ((inst (cl-cc/vm:make-vm-move :dst :r0 :src :r1))
         (bytes (%collect-emit-ops-bytes #'cl-cc/codegen-native/targets/x86-64::emit-vm-move inst)))
    ;; Distinct GP registers → MOV emitted
    (expect (> (length bytes) 0) :to-be-truthy)))

(it-sequential "x86-emit-move-same-gp-reg-emits-nothing"
  (let* ((inst (cl-cc/vm:make-vm-move :dst :r0 :src :r0))
         (bytes (%collect-emit-ops-bytes #'cl-cc/codegen-native/targets/x86-64::emit-vm-move inst)))
    (expect (length bytes) :to-equal 0)))

;;; ─── Binary ALU emitters (define-binary-alu-emitter) ────────────────────

(it-sequential "x86-emit-binary-alu-emits-bytes add"
  (destructuring-bind (emit-fn inst) (list #'cl-cc/codegen-native/targets/x86-64::emit-vm-add (cl-cc/vm:make-vm-add :dst :r0 :lhs :r1 :rhs :r2))
    (let ((bytes (%collect-emit-ops-bytes emit-fn inst)))
    (expect (>= (length bytes) 6) :to-be-truthy))))

(it-sequential "x86-emit-binary-alu-emits-bytes sub"
  (destructuring-bind (emit-fn inst) (list #'cl-cc/codegen-native/targets/x86-64::emit-vm-sub (cl-cc/vm:make-vm-sub :dst :r0 :lhs :r1 :rhs :r2))
    (let ((bytes (%collect-emit-ops-bytes emit-fn inst)))
    (expect (>= (length bytes) 6) :to-be-truthy))))

(it-sequential "x86-emit-binary-alu-emits-bytes mul"
  (destructuring-bind (emit-fn inst) (list #'cl-cc/codegen-native/targets/x86-64::emit-vm-mul (cl-cc/vm:make-vm-mul :dst :r0 :lhs :r1 :rhs :r2))
    (let ((bytes (%collect-emit-ops-bytes emit-fn inst)))
    (expect (>= (length bytes) 6) :to-be-truthy))))

;;; ─── Checked arithmetic emitters (FR-303) ─────────────────────────────────

(it-sequential "x86-emit-add-checked-emits-jo-and-bignum-helper"
  (let* ((inst (cl-cc/vm:make-vm-add-checked :dst :r0 :lhs :r1 :rhs :r2))
         (bytes (%collect-emit-ops-bytes #'cl-cc/codegen-native/targets/x86-64::emit-vm-add-checked inst)))
    (expect (= 14 (length bytes)) :to-be-truthy)))

(it-sequential "x86-emit-sub-checked-emits-jo-and-bignum-helper"
  (let* ((inst (cl-cc/vm:make-vm-sub-checked :dst :r0 :lhs :r1 :rhs :r2))
         (bytes (%collect-emit-ops-bytes #'cl-cc/codegen-native/targets/x86-64::emit-vm-sub-checked inst)))
    (expect (= 14 (length bytes)) :to-be-truthy)))

(it-sequential "x86-emit-mul-checked-emits-jo-and-bignum-helper"
  (let* ((inst (cl-cc/vm:make-vm-mul-checked :dst :r0 :lhs :r1 :rhs :r2))
         (bytes (%collect-emit-ops-bytes #'cl-cc/codegen-native/targets/x86-64::emit-vm-mul-checked inst)))
    (expect (= 15 (length bytes)) :to-be-truthy)))

(it-sequential "x86-emit-add-checked-emits-14-bytes"
  (let* ((inst (cl-cc/vm:make-vm-add-checked :dst :r0 :lhs :r1 :rhs :r2))
         (bytes (%collect-emit-ops-bytes #'cl-cc/codegen-native/targets/x86-64::emit-vm-add-checked inst)))
    (expect (= 14 (length bytes)) :to-be-truthy)))

(it-sequential "x86-emit-sub-checked-emits-14-bytes"
  (let* ((inst (cl-cc/vm:make-vm-sub-checked :dst :r0 :lhs :r1 :rhs :r2))
         (bytes (%collect-emit-ops-bytes #'cl-cc/codegen-native/targets/x86-64::emit-vm-sub-checked inst)))
    (expect (= 14 (length bytes)) :to-be-truthy)))

(it-sequential "x86-emit-mul-checked-emits-15-bytes"
  (let* ((inst (cl-cc/vm:make-vm-mul-checked :dst :r0 :lhs :r1 :rhs :r2))
         (bytes (%collect-emit-ops-bytes #'cl-cc/codegen-native/targets/x86-64::emit-vm-mul-checked inst)))
    (expect (= 15 (length bytes)) :to-be-truthy)))

(it-sequential "x86-emit-mul-high-emits-19-bytes"
  (expect (%collect-emit-ops-bytes #'cl-cc/codegen-native/targets/x86-64::emit-vm-integer-mul-high-u
                                         (cl-cc/vm:make-vm-integer-mul-high-u :dst :r0 :lhs :r1 :rhs :r2)) :to-equal '(#x49 #x89 #xD3 #x50 #x52 #x48 #x89 #xC8 #x49 #xF7 #xE3 #x49 #x89 #xD3 #x5A #x58 #x4C #x89 #xD8))
  (expect (%collect-emit-ops-bytes #'cl-cc/codegen-native/targets/x86-64::emit-vm-integer-mul-high-s
                                          (cl-cc/vm:make-vm-integer-mul-high-s :dst :r0 :lhs :r1 :rhs :r2)) :to-equal '(#x49 #x89 #xD3 #x50 #x52 #x48 #x89 #xC8 #x49 #xF7 #xEB #x49 #x89 #xD3 #x5A #x58 #x4C #x89 #xD8)))

(it-sequential "x86-emit-sqrt-emits-sqrtsd-sequence"
  (expect (%collect-emit-ops-bytes #'cl-cc/codegen-native/targets/x86-64::emit-vm-sqrt
                                         (cl-cc/vm:make-vm-sqrt :dst :r0 :src :r1)) :to-equal '(#xF2 #x0F #x10 #xC1 #xF2 #x0F #x51 #xC0)))

;;; ─── Libm call emitters (sin/cos/exp/log/tan/asin/acos/atan) ───────────────

(it-sequential "x86-emit-libm-unary-emits-21-bytes sin"
  (destructuring-bind (emit-fn inst) (list #'cl-cc/codegen-native/targets/x86-64::emit-vm-sin (cl-cc/vm::make-vm-sin-inst :dst :r0 :src :r1))
    (expect (= 21 (length (%collect-emit-ops-bytes emit-fn inst))) :to-be-truthy)))

(it-sequential "x86-emit-libm-unary-emits-21-bytes cos"
  (destructuring-bind (emit-fn inst) (list #'cl-cc/codegen-native/targets/x86-64::emit-vm-cos (cl-cc/vm::make-vm-cos-inst :dst :r0 :src :r1))
    (expect (= 21 (length (%collect-emit-ops-bytes emit-fn inst))) :to-be-truthy)))

(it-sequential "x86-emit-libm-unary-emits-21-bytes exp"
  (destructuring-bind (emit-fn inst) (list #'cl-cc/codegen-native/targets/x86-64::emit-vm-exp (cl-cc/vm::make-vm-exp-inst :dst :r0 :src :r1))
    (expect (= 21 (length (%collect-emit-ops-bytes emit-fn inst))) :to-be-truthy)))

(it-sequential "x86-emit-libm-unary-emits-21-bytes log"
  (destructuring-bind (emit-fn inst) (list #'cl-cc/codegen-native/targets/x86-64::emit-vm-log (cl-cc/vm::make-vm-log-inst :dst :r0 :src :r1))
    (expect (= 21 (length (%collect-emit-ops-bytes emit-fn inst))) :to-be-truthy)))

(it-sequential "x86-emit-libm-unary-emits-21-bytes tan"
  (destructuring-bind (emit-fn inst) (list #'cl-cc/codegen-native/targets/x86-64::emit-vm-tan (cl-cc/vm::make-vm-tan-inst :dst :r0 :src :r1))
    (expect (= 21 (length (%collect-emit-ops-bytes emit-fn inst))) :to-be-truthy)))

(it-sequential "x86-emit-libm-unary-emits-21-bytes asin"
  (destructuring-bind (emit-fn inst) (list #'cl-cc/codegen-native/targets/x86-64::emit-vm-asin (cl-cc/vm::make-vm-asin-inst :dst :r0 :src :r1))
    (expect (= 21 (length (%collect-emit-ops-bytes emit-fn inst))) :to-be-truthy)))

(it-sequential "x86-emit-libm-unary-emits-21-bytes acos"
  (destructuring-bind (emit-fn inst) (list #'cl-cc/codegen-native/targets/x86-64::emit-vm-acos (cl-cc/vm::make-vm-acos-inst :dst :r0 :src :r1))
    (expect (= 21 (length (%collect-emit-ops-bytes emit-fn inst))) :to-be-truthy)))

(it-sequential "x86-emit-libm-unary-emits-21-bytes atan"
  (destructuring-bind (emit-fn inst) (list #'cl-cc/codegen-native/targets/x86-64::emit-vm-atan (cl-cc/vm::make-vm-atan-inst :dst :r0 :src :r1))
    (expect (= 21 (length (%collect-emit-ops-bytes emit-fn inst))) :to-be-truthy)))

(it-sequential "x86-emit-libm-sin-starts-with-movsd"
  (let ((bytes (%collect-emit-ops-bytes
                #'cl-cc/codegen-native/targets/x86-64::emit-vm-sin
                (cl-cc/vm::make-vm-sin-inst :dst :r0 :src :r1))))
    (expect (subseq bytes 0 4) :to-equal '(#xF2 #x0F #x10 #xC1))))

;;; ─── Truncate / Rem ──────────────────────────────────────────────────────

(it-sequential "x86-emit-truncate-rem-cases truncate"
  (destructuring-bind (emit-fn inst) (list #'cl-cc/codegen-native/targets/x86-64::emit-vm-truncate (cl-cc/vm:make-vm-truncate :dst :r0 :lhs :r1 :rhs :r2))
    (expect (> (length (%collect-emit-ops-bytes emit-fn inst)) 0) :to-be-truthy)))

(it-sequential "x86-emit-truncate-rem-cases rem"
  (destructuring-bind (emit-fn inst) (list #'cl-cc/codegen-native/targets/x86-64::emit-vm-rem (cl-cc/vm:make-vm-rem      :dst :r0 :lhs :r1 :rhs :r2))
    (expect (> (length (%collect-emit-ops-bytes emit-fn inst)) 0) :to-be-truthy)))

;;; ─── Floor Division / Mod (documented byte counts) ──────────────────────

(it-sequential "x86-emit-div-emits-34-bytes"
  (let* ((inst (cl-cc/vm:make-vm-div :dst :r0 :lhs :r1 :rhs :r2))
         (bytes (%collect-emit-ops-bytes #'cl-cc/codegen-native/targets/x86-64::emit-vm-div inst)))
    (expect (= 34 (length bytes)) :to-be-truthy)))

(it-sequential "x86-emit-mod-emits-37-bytes"
  (let* ((inst (cl-cc/vm:make-vm-mod :dst :r0 :lhs :r1 :rhs :r2))
         (bytes (%collect-emit-ops-bytes #'cl-cc/codegen-native/targets/x86-64::emit-vm-mod inst)))
    (expect (= 37 (length bytes)) :to-be-truthy)))

;;; ─── Comparison emitters (define-cmp-emitter) ───────────────────────────

(it-sequential "x86-emit-comparison-emits-bytes lt"
  (destructuring-bind (emit-fn inst) (list #'cl-cc/codegen-native/targets/x86-64::emit-vm-lt (cl-cc/vm:make-vm-lt     :dst :r0 :lhs :r1 :rhs :r2))
    (let ((bytes (%collect-emit-ops-bytes emit-fn inst)))
    (expect (> (length bytes) 0) :to-be-truthy))))

(it-sequential "x86-emit-comparison-emits-bytes gt"
  (destructuring-bind (emit-fn inst) (list #'cl-cc/codegen-native/targets/x86-64::emit-vm-gt (cl-cc/vm:make-vm-gt     :dst :r0 :lhs :r1 :rhs :r2))
    (let ((bytes (%collect-emit-ops-bytes emit-fn inst)))
    (expect (> (length bytes) 0) :to-be-truthy))))

(it-sequential "x86-emit-comparison-emits-bytes le"
  (destructuring-bind (emit-fn inst) (list #'cl-cc/codegen-native/targets/x86-64::emit-vm-le (cl-cc/vm:make-vm-le     :dst :r0 :lhs :r1 :rhs :r2))
    (let ((bytes (%collect-emit-ops-bytes emit-fn inst)))
    (expect (> (length bytes) 0) :to-be-truthy))))

(it-sequential "x86-emit-comparison-emits-bytes ge"
  (destructuring-bind (emit-fn inst) (list #'cl-cc/codegen-native/targets/x86-64::emit-vm-ge (cl-cc/vm:make-vm-ge     :dst :r0 :lhs :r1 :rhs :r2))
    (let ((bytes (%collect-emit-ops-bytes emit-fn inst)))
    (expect (> (length bytes) 0) :to-be-truthy))))

(it-sequential "x86-emit-comparison-emits-bytes num-eq"
  (destructuring-bind (emit-fn inst) (list #'cl-cc/codegen-native/targets/x86-64::emit-vm-num-eq (cl-cc/vm:make-vm-num-eq :dst :r0 :lhs :r1 :rhs :r2))
    (let ((bytes (%collect-emit-ops-bytes emit-fn inst)))
    (expect (> (length bytes) 0) :to-be-truthy))))

(it-sequential "x86-emit-comparison-emits-bytes eq"
  (destructuring-bind (emit-fn inst) (list #'cl-cc/codegen-native/targets/x86-64::emit-vm-eq (cl-cc/vm:make-vm-eq     :dst :r0 :lhs :r1 :rhs :r2))
    (let ((bytes (%collect-emit-ops-bytes emit-fn inst)))
    (expect (> (length bytes) 0) :to-be-truthy))))

;;; ─── Unary emitters ──────────────────────────────────────────────────────

(it-sequential "x86-emit-unary-non-empty neg"
  (destructuring-bind (emit-fn inst) (list #'cl-cc/codegen-native/targets/x86-64::emit-vm-neg (cl-cc/vm:make-vm-neg            :dst :r0 :src :r1))
    (expect (> (length (%collect-emit-ops-bytes emit-fn inst)) 0) :to-be-truthy)))

(it-sequential "x86-emit-unary-non-empty not"
  (destructuring-bind (emit-fn inst) (list #'cl-cc/codegen-native/targets/x86-64::emit-vm-not (cl-cc/vm:make-vm-not            :dst :r0 :src :r1))
    (expect (> (length (%collect-emit-ops-bytes emit-fn inst)) 0) :to-be-truthy)))

(it-sequential "x86-emit-unary-non-empty lognot"
  (destructuring-bind (emit-fn inst) (list #'cl-cc/codegen-native/targets/x86-64::emit-vm-lognot (cl-cc/vm:make-vm-lognot         :dst :r0 :src :r1))
    (expect (> (length (%collect-emit-ops-bytes emit-fn inst)) 0) :to-be-truthy)))

(it-sequential "x86-emit-unary-non-empty logcount"
  (destructuring-bind (emit-fn inst) (list #'cl-cc/codegen-native/targets/x86-64::emit-vm-logcount (cl-cc/vm:make-vm-logcount       :dst :r0 :src :r1))
    (expect (> (length (%collect-emit-ops-bytes emit-fn inst)) 0) :to-be-truthy)))

(it-sequential "x86-emit-unary-non-empty integer-length"
  (destructuring-bind (emit-fn inst) (list #'cl-cc/codegen-native/targets/x86-64::emit-vm-integer-length (cl-cc/vm:make-vm-integer-length :dst :r0 :src :r1))
    (expect (> (length (%collect-emit-ops-bytes emit-fn inst)) 0) :to-be-truthy)))

(it-sequential "x86-emit-unary-non-empty bswap"
  (destructuring-bind (emit-fn inst) (list #'cl-cc/codegen-native/targets/x86-64::emit-vm-bswap (cl-cc/vm:make-vm-bswap          :dst :r0 :src :r1))
    (expect (> (length (%collect-emit-ops-bytes emit-fn inst)) 0) :to-be-truthy)))

(it-sequential "x86-emit-unary-non-empty inc"
  (destructuring-bind (emit-fn inst) (list #'cl-cc/codegen-native/targets/x86-64::emit-vm-inc (cl-cc/vm:make-vm-inc            :dst :r0 :src :r1))
    (expect (> (length (%collect-emit-ops-bytes emit-fn inst)) 0) :to-be-truthy)))

(it-sequential "x86-emit-unary-non-empty dec"
  (destructuring-bind (emit-fn inst) (list #'cl-cc/codegen-native/targets/x86-64::emit-vm-dec (cl-cc/vm:make-vm-dec            :dst :r0 :src :r1))
    (expect (> (length (%collect-emit-ops-bytes emit-fn inst)) 0) :to-be-truthy)))

(it-sequential "x86-emit-unary-non-empty abs"
  (destructuring-bind (emit-fn inst) (list #'cl-cc/codegen-native/targets/x86-64::emit-vm-abs (cl-cc/vm:make-vm-abs            :dst :r0 :src :r1))
    (expect (> (length (%collect-emit-ops-bytes emit-fn inst)) 0) :to-be-truthy)))

(it-sequential "x86-emit-unary-non-empty rotate"
  (destructuring-bind (emit-fn inst) (list #'cl-cc/codegen-native/targets/x86-64::emit-vm-rotate (cl-cc/vm:make-vm-rotate         :dst :r0 :lhs :r1 :rhs :r2))
    (expect (> (length (%collect-emit-ops-bytes emit-fn inst)) 0) :to-be-truthy)))

;;; ─── Arithmetic Shift (documented 24-byte layout) ────────────────────────

(it-sequential "x86-emit-ash-emits-24-bytes"
  (let* ((inst (cl-cc/vm:make-vm-ash :dst :r0 :lhs :r1 :rhs :r2))
         (bytes (%collect-emit-ops-bytes #'cl-cc/codegen-native/targets/x86-64::emit-vm-ash inst)))
    (expect (= 24 (length bytes)) :to-be-truthy)))

;;; ─── Min / Max (define-cmov-emitter) ────────────────────────────────────

(it-sequential "x86-emit-min-max-emits-bytes min"
  (destructuring-bind (emit-fn inst) (list #'cl-cc/codegen-native/targets/x86-64::emit-vm-min (cl-cc/vm:make-vm-min :dst :r0 :lhs :r1 :rhs :r2))
    (let ((bytes (%collect-emit-ops-bytes emit-fn inst)))
    (expect (> (length bytes) 0) :to-be-truthy))))

(it-sequential "x86-emit-min-max-emits-bytes max"
  (destructuring-bind (emit-fn inst) (list #'cl-cc/codegen-native/targets/x86-64::emit-vm-max (cl-cc/vm:make-vm-max :dst :r0 :lhs :r1 :rhs :r2))
    (let ((bytes (%collect-emit-ops-bytes emit-fn inst)))
    (expect (> (length bytes) 0) :to-be-truthy))))

;;; ─── Select ──────────────────────────────────────────────────────────────

(it-sequential "x86-emit-select-emits-bytes"
  (let* ((inst (cl-cc/vm:make-vm-select :dst :r0 :cond-reg :r1 :then-reg :r2 :else-reg :r3))
         (bytes (%collect-emit-ops-bytes #'cl-cc/codegen-native/targets/x86-64::emit-vm-select inst)))
    (expect (> (length bytes) 0) :to-be-truthy)))

;;; ─── Bignum Runtime Call Emitter Tests ───────────────────────────────────

(it-sequential "x86-emit-bignum-ops-emit-bytes add"
  (destructuring-bind (ctor emitter) (list #'cl-cc/vm:make-vm-add-checked #'cl-cc/codegen-native/targets/x86-64::emit-vm-add-bignum)
    (let ((bytes (%collect-emit-ops-bytes
                emitter (funcall ctor :dst :r0 :lhs :r1 :rhs :r2))))
    (expect (> (length bytes) 0) :to-be-truthy))))

(it-sequential "x86-emit-bignum-ops-emit-bytes sub"
  (destructuring-bind (ctor emitter) (list #'cl-cc/vm:make-vm-sub-checked #'cl-cc/codegen-native/targets/x86-64::emit-vm-sub-bignum)
    (let ((bytes (%collect-emit-ops-bytes
                emitter (funcall ctor :dst :r0 :lhs :r1 :rhs :r2))))
    (expect (> (length bytes) 0) :to-be-truthy))))

(it-sequential "x86-emit-bignum-ops-emit-bytes mul"
  (destructuring-bind (ctor emitter) (list #'cl-cc/vm:make-vm-mul-checked #'cl-cc/codegen-native/targets/x86-64::emit-vm-mul-bignum)
    (let ((bytes (%collect-emit-ops-bytes
                emitter (funcall ctor :dst :r0 :lhs :r1 :rhs :r2))))
    (expect (> (length bytes) 0) :to-be-truthy))))

(it-sequential "x86-bignum-flag-dispatches-to-bignum-emitter"
  (let ((cl-cc/codegen-native/targets/x86-64::*x86-64-bignum-calls-enabled* t)
        (inst (cl-cc/vm:make-vm-add-checked :dst :r0 :lhs :r1 :rhs :r2)))
    (unwind-protect
         (let ((bytes (%collect-emit-ops-bytes #'cl-cc/codegen-native/targets/x86-64::emit-vm-add-wrapper inst)))
           (expect (> (length bytes) 0) :to-be-truthy))
      (setf cl-cc/codegen-native/targets/x86-64::*x86-64-bignum-calls-enabled* nil))))
