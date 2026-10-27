;;;; tests/unit/emit/x86-64-vm-emitter-tests.lisp — VM Instruction Emitter Byte-Size Tests
;;;;
;;;; Continuation of x86-64-encoding-tests.lisp.
;;;; Tests for VM instruction emitters: exact byte counts and instruction-size
;;;; dispatch table completeness.

(in-package :cl-cc/codegen-native/targets/x86-64/test)


;;; ─── VM instruction emitter byte sizes ──────────────────────────────────────

(it-sequential "x86-vm-emitter-byte-size vm-neg"
  (destructuring-bind (emit-fn expected-size) (list (lambda (s) (cl-cc/codegen-native/targets/x86-64::emit-vm-neg
                           (cl-cc/vm:make-vm-neg :dst :R0 :src :R1) s)) 6)
    (expect (length (%x86-encoding-collect-bytes emit-fn)) :to-equal expected-size)))

(it-sequential "x86-vm-emitter-byte-size vm-not"
  (destructuring-bind (emit-fn expected-size) (list (lambda (s) (cl-cc/codegen-native/targets/x86-64::emit-vm-not
                           (cl-cc/vm:make-vm-not :dst :R0 :src :R1) s)) 10)
    (expect (length (%x86-encoding-collect-bytes emit-fn)) :to-equal expected-size)))

(it-sequential "x86-vm-emitter-byte-size vm-lognot"
  (destructuring-bind (emit-fn expected-size) (list (lambda (s) (cl-cc/codegen-native/targets/x86-64::emit-vm-lognot
                           (cl-cc/vm:make-vm-lognot :dst :R0 :src :R1) s)) 6)
    (expect (length (%x86-encoding-collect-bytes emit-fn)) :to-equal expected-size)))

(it-sequential "x86-vm-emitter-byte-size vm-inc"
  (destructuring-bind (emit-fn expected-size) (list (lambda (s) (cl-cc/codegen-native/targets/x86-64::emit-vm-inc
                           (cl-cc/vm:make-vm-inc :dst :R0 :src :R1) s)) 7)
    (expect (length (%x86-encoding-collect-bytes emit-fn)) :to-equal expected-size)))

(it-sequential "x86-vm-emitter-byte-size vm-dec"
  (destructuring-bind (emit-fn expected-size) (list (lambda (s) (cl-cc/codegen-native/targets/x86-64::emit-vm-dec
                           (cl-cc/vm:make-vm-dec :dst :R0 :src :R1) s)) 7)
    (expect (length (%x86-encoding-collect-bytes emit-fn)) :to-equal expected-size)))

(it-sequential "x86-vm-emitter-byte-size vm-abs"
  (destructuring-bind (emit-fn expected-size) (list (lambda (s) (cl-cc/codegen-native/targets/x86-64::emit-vm-abs
                           (cl-cc/vm:make-vm-abs :dst :R0 :src :R1) s)) 15)
    (expect (length (%x86-encoding-collect-bytes emit-fn)) :to-equal expected-size)))

(it-sequential "x86-vm-emitter-byte-size vm-min"
  (destructuring-bind (emit-fn expected-size) (list (lambda (s) (cl-cc/codegen-native/targets/x86-64::emit-vm-min
                           (cl-cc/vm:make-vm-min :dst :R0 :lhs :R1 :rhs :R2) s)) 10)
    (expect (length (%x86-encoding-collect-bytes emit-fn)) :to-equal expected-size)))

(it-sequential "x86-vm-emitter-byte-size vm-max"
  (destructuring-bind (emit-fn expected-size) (list (lambda (s) (cl-cc/codegen-native/targets/x86-64::emit-vm-max
                            (cl-cc/vm:make-vm-max :dst :R0 :lhs :R1 :rhs :R2) s)) 10)
    (expect (length (%x86-encoding-collect-bytes emit-fn)) :to-equal expected-size)))

(it-sequential "x86-vm-emitter-byte-size vm-select"
  (destructuring-bind (emit-fn expected-size) (list (lambda (s) (cl-cc/codegen-native/targets/x86-64::emit-vm-select
                            (cl-cc/vm:make-vm-select :dst :R0 :cond-reg :R1 :then-reg :R2 :else-reg :R3) s)) 10)
    (expect (length (%x86-encoding-collect-bytes emit-fn)) :to-equal expected-size)))

(it-sequential "x86-vm-emitter-byte-size vm-logand"
  (destructuring-bind (emit-fn expected-size) (list (lambda (s) (cl-cc/codegen-native/targets/x86-64::emit-vm-logand
                            (cl-cc/vm:make-vm-logand :dst :R0 :lhs :R1 :rhs :R2) s)) 6)
    (expect (length (%x86-encoding-collect-bytes emit-fn)) :to-equal expected-size)))

(it-sequential "x86-vm-emitter-byte-size vm-logior"
  (destructuring-bind (emit-fn expected-size) (list (lambda (s) (cl-cc/codegen-native/targets/x86-64::emit-vm-logior
                           (cl-cc/vm:make-vm-logior :dst :R0 :lhs :R1 :rhs :R2) s)) 6)
    (expect (length (%x86-encoding-collect-bytes emit-fn)) :to-equal expected-size)))

(it-sequential "x86-vm-emitter-byte-size vm-logxor"
  (destructuring-bind (emit-fn expected-size) (list (lambda (s) (cl-cc/codegen-native/targets/x86-64::emit-vm-logxor
                           (cl-cc/vm:make-vm-logxor :dst :R0 :lhs :R1 :rhs :R2) s)) 6)
    (expect (length (%x86-encoding-collect-bytes emit-fn)) :to-equal expected-size)))

(it-sequential "x86-vm-emitter-byte-size vm-logeqv"
  (destructuring-bind (emit-fn expected-size) (list (lambda (s) (cl-cc/codegen-native/targets/x86-64::emit-vm-logeqv
                           (cl-cc/vm:make-vm-logeqv :dst :R0 :lhs :R1 :rhs :R2) s)) 9)
    (expect (length (%x86-encoding-collect-bytes emit-fn)) :to-equal expected-size)))

(it-sequential "x86-vm-emitter-byte-size vm-and"
  (destructuring-bind (emit-fn expected-size) (list (lambda (s) (cl-cc/codegen-native/targets/x86-64::emit-vm-and
                           (cl-cc/vm:make-vm-and :dst :R0 :lhs :R1 :rhs :R2) s)) 17)
    (expect (length (%x86-encoding-collect-bytes emit-fn)) :to-equal expected-size)))

(it-sequential "x86-vm-emitter-byte-size vm-or"
  (destructuring-bind (emit-fn expected-size) (list (lambda (s) (cl-cc/codegen-native/targets/x86-64::emit-vm-or
                           (cl-cc/vm:make-vm-or  :dst :R0 :lhs :R1 :rhs :R2) s)) 17)
    (expect (length (%x86-encoding-collect-bytes emit-fn)) :to-equal expected-size)))

(it-sequential "x86-vm-emitter-byte-size vm-true-pred"
  (destructuring-bind (emit-fn expected-size) (list (lambda (s) (cl-cc/codegen-native/targets/x86-64::emit-vm-true-pred
                             (cl-cc/vm:make-vm-number-p :dst :R0 :src :R1) s)) 10)
    (expect (length (%x86-encoding-collect-bytes emit-fn)) :to-equal expected-size)))

(it-sequential "x86-vm-emitter-byte-size vm-false-pred"
  (destructuring-bind (emit-fn expected-size) (list (lambda (s) (cl-cc/codegen-native/targets/x86-64::emit-vm-false-pred
                             (cl-cc/vm:make-vm-cons-p :dst :R0 :src :R1) s)) 10)
    (expect (length (%x86-encoding-collect-bytes emit-fn)) :to-equal expected-size)))

(it-sequential "x86-vm-emitter-byte-size vm-truncate"
  (destructuring-bind (emit-fn expected-size) (list (lambda (s) (cl-cc/codegen-native/targets/x86-64::emit-vm-truncate
                           (cl-cc/vm:make-vm-truncate :dst :R0 :lhs :R1 :rhs :R2) s)) 21)
    (expect (length (%x86-encoding-collect-bytes emit-fn)) :to-equal expected-size)))

(it-sequential "x86-vm-emitter-byte-size vm-rem"
  (destructuring-bind (emit-fn expected-size) (list (lambda (s) (cl-cc/codegen-native/targets/x86-64::emit-vm-rem
                           (cl-cc/vm:make-vm-rem :dst :R0 :lhs :R1 :rhs :R2) s)) 21)
    (expect (length (%x86-encoding-collect-bytes emit-fn)) :to-equal expected-size)))

(it-sequential "x86-vm-emitter-byte-size vm-ash"
  (destructuring-bind (emit-fn expected-size) (list (lambda (s) (cl-cc/codegen-native/targets/x86-64::emit-vm-ash
                            (cl-cc/vm:make-vm-ash :dst :R0 :lhs :R1 :rhs :R2) s)) 24)
    (expect (length (%x86-encoding-collect-bytes emit-fn)) :to-equal expected-size)))

(it-sequential "x86-vm-emitter-byte-size vm-mul"
  (destructuring-bind (emit-fn expected-size) (list (lambda (s) (cl-cc/codegen-native/targets/x86-64::emit-vm-mul
                            (cl-cc/vm:make-vm-mul :dst :R0 :lhs :R1 :rhs :R2) s)) 7)
    (expect (length (%x86-encoding-collect-bytes emit-fn)) :to-equal expected-size)))

(it-sequential "x86-vm-emitter-byte-size vm-integer-mul-high-u"
  (destructuring-bind (emit-fn expected-size) (list (lambda (s) (cl-cc/codegen-native/targets/x86-64::emit-vm-integer-mul-high-u
                             (cl-cc/vm:make-vm-integer-mul-high-u :dst :R0 :lhs :R1 :rhs :R2) s)) 19)
    (expect (length (%x86-encoding-collect-bytes emit-fn)) :to-equal expected-size)))

(it-sequential "x86-vm-emitter-byte-size vm-integer-mul-high-s"
  (destructuring-bind (emit-fn expected-size) (list (lambda (s) (cl-cc/codegen-native/targets/x86-64::emit-vm-integer-mul-high-s
                             (cl-cc/vm:make-vm-integer-mul-high-s :dst :R0 :lhs :R1 :rhs :R2) s)) 19)
    (expect (length (%x86-encoding-collect-bytes emit-fn)) :to-equal expected-size)))

(it-sequential "x86-vm-emitter-byte-size vm-div"
  (destructuring-bind (emit-fn expected-size) (list (lambda (s) (cl-cc/codegen-native/targets/x86-64::emit-vm-div
                            (cl-cc/vm:make-vm-div :dst :R0 :lhs :R1 :rhs :R2) s)) 34)
    (expect (length (%x86-encoding-collect-bytes emit-fn)) :to-equal expected-size)))

(it-sequential "x86-vm-emitter-byte-size vm-mod"
  (destructuring-bind (emit-fn expected-size) (list (lambda (s) (cl-cc/codegen-native/targets/x86-64::emit-vm-mod
                           (cl-cc/vm:make-vm-mod :dst :R0 :lhs :R1 :rhs :R2) s)) 37)
    (expect (length (%x86-encoding-collect-bytes emit-fn)) :to-equal expected-size)))

(it-sequential "x86-vm-emitter-byte-size vm-lt"
  (destructuring-bind (emit-fn expected-size) (list (lambda (s) (cl-cc/codegen-native/targets/x86-64::emit-vm-lt
                           (cl-cc/vm:make-vm-lt :dst :R0 :lhs :R1 :rhs :R2) s)) 10)
    (expect (length (%x86-encoding-collect-bytes emit-fn)) :to-equal expected-size)))

(it-sequential "x86-vm-emitter-byte-size vm-gt"
  (destructuring-bind (emit-fn expected-size) (list (lambda (s) (cl-cc/codegen-native/targets/x86-64::emit-vm-gt
                           (cl-cc/vm:make-vm-gt :dst :R0 :lhs :R1 :rhs :R2) s)) 10)
    (expect (length (%x86-encoding-collect-bytes emit-fn)) :to-equal expected-size)))

(it-sequential "x86-vm-emitter-byte-size vm-le"
  (destructuring-bind (emit-fn expected-size) (list (lambda (s) (cl-cc/codegen-native/targets/x86-64::emit-vm-le
                           (cl-cc/vm:make-vm-le :dst :R0 :lhs :R1 :rhs :R2) s)) 10)
    (expect (length (%x86-encoding-collect-bytes emit-fn)) :to-equal expected-size)))

(it-sequential "x86-vm-emitter-byte-size vm-ge"
  (destructuring-bind (emit-fn expected-size) (list (lambda (s) (cl-cc/codegen-native/targets/x86-64::emit-vm-ge
                           (cl-cc/vm:make-vm-ge :dst :R0 :lhs :R1 :rhs :R2) s)) 10)
    (expect (length (%x86-encoding-collect-bytes emit-fn)) :to-equal expected-size)))

(it-sequential "x86-vm-emitter-byte-size vm-num-eq"
  (destructuring-bind (emit-fn expected-size) (list (lambda (s) (cl-cc/codegen-native/targets/x86-64::emit-vm-num-eq
                           (cl-cc/vm:make-vm-num-eq :dst :R0 :lhs :R1 :rhs :R2) s)) 10)
    (expect (length (%x86-encoding-collect-bytes emit-fn)) :to-equal expected-size)))

(it-sequential "x86-vm-emitter-byte-size vm-eq"
  (destructuring-bind (emit-fn expected-size) (list (lambda (s) (cl-cc/codegen-native/targets/x86-64::emit-vm-eq
                           (cl-cc/vm:make-vm-eq :dst :R0 :lhs :R1 :rhs :R2) s)) 10)
    (expect (length (%x86-encoding-collect-bytes emit-fn)) :to-equal expected-size)))

(it-sequential "x86-vm-emitter-byte-size vm-null-p"
  (destructuring-bind (emit-fn expected-size) (list (lambda (s) (cl-cc/codegen-native/targets/x86-64::emit-vm-null-p
                           (cl-cc/vm:make-vm-null-p :dst :R0 :src :R1) s)) 10)
    (expect (length (%x86-encoding-collect-bytes emit-fn)) :to-equal expected-size)))

(it-sequential "x86-vm-emitter-byte-size vm-logtest"
  (destructuring-bind (emit-fn expected-size) (list (lambda (s) (cl-cc/codegen-native/targets/x86-64::emit-vm-logtest
                           (cl-cc/vm:make-vm-logtest :dst :R0 :lhs :R1 :rhs :R2) s)) 13)
    (expect (length (%x86-encoding-collect-bytes emit-fn)) :to-equal expected-size)))

(it-sequential "x86-vm-emitter-byte-size vm-logbitp"
  (destructuring-bind (emit-fn expected-size) (list (lambda (s) (cl-cc/codegen-native/targets/x86-64::emit-vm-logbitp
                           (cl-cc/vm:make-vm-logbitp :dst :R0 :lhs :R1 :rhs :R2) s)) 15)
    (expect (length (%x86-encoding-collect-bytes emit-fn)) :to-equal expected-size)))

;;; ─── instruction-size table ──────────────────────────────────────────────────

(it-sequential "x86-instruction-size-table-coverage"
  (dolist (tp '(cl-cc/vm:vm-const cl-cc/vm::vm-move cl-cc/vm:vm-add cl-cc/vm:vm-sub cl-cc/vm:vm-mul
                cl-cc/vm::vm-integer-mul-high-u cl-cc/vm::vm-integer-mul-high-s
                cl-cc/vm:vm-halt cl-cc/vm::vm-label cl-cc/vm::vm-jump cl-cc/vm::vm-jump-zero cl-cc/vm::vm-ret
                cl-cc/vm:vm-lt cl-cc/vm:vm-gt cl-cc/vm:vm-le cl-cc/vm:vm-ge cl-cc/vm::vm-num-eq cl-cc/vm:vm-eq
                cl-cc/vm:vm-neg cl-cc/vm::vm-not cl-cc/vm:vm-lognot cl-cc/vm:vm-inc cl-cc/vm:vm-dec
                cl-cc/vm::vm-abs cl-cc/vm:vm-min cl-cc/vm:vm-max cl-cc/vm::vm-select cl-cc/vm::vm-ash
                cl-cc/vm::vm-truncate cl-cc/vm::vm-rem cl-cc/vm::vm-div cl-cc/vm::vm-mod
                cl-cc/vm::vm-and cl-cc/vm::vm-or cl-cc/vm:vm-logand cl-cc/vm:vm-logior cl-cc/vm:vm-logxor
                cl-cc/vm::vm-logeqv cl-cc/vm::vm-logtest cl-cc/vm::vm-logbitp
                cl-cc/vm::vm-null-p cl-cc/vm::vm-number-p cl-cc/vm::vm-integer-p
                cl-cc/vm::vm-cons-p cl-cc/vm::vm-symbol-p cl-cc/vm::vm-function-p
                cl-cc/codegen-native/regalloc::vm-spill-store cl-cc/codegen-native/regalloc::vm-spill-load))
    (expect (gethash tp cl-cc/codegen-native/targets/x86-64::*x86-64-instruction-sizes*) :to-be-truthy)))
