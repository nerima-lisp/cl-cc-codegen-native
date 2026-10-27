(in-package :cl-cc/codegen-native/scheduling)

(defun x86-64-macro-fusion-compare-p (inst)
  "Return true when INST can form the compare/test side of an x86-64 macro-fusion pair."
  (member (type-of inst)
          '(vm-lt vm-gt vm-le vm-ge vm-eq vm-num-eq vm-null-p vm-integer-p)
          :test #'eq))

(defun x86-64-macro-fusion-branch-p (inst)
  "Return true when INST is a conditional branch eligible for x86-64 macro-fusion."
  (typep inst 'vm-jump-zero))

(defun x86-64-macro-fusion-candidate-p (compare branch)
  "Return true when COMPARE and BRANCH are an adjacent FR-721 macro-fusion pair."
  (and (x86-64-macro-fusion-compare-p compare)
       (x86-64-macro-fusion-branch-p branch)
       (let ((dst (opt-inst-dst compare)))
         (and dst (member dst (opt-inst-read-regs branch) :test #'eql)))))

(defun x86-64-preserve-macro-fusion (instructions)
  "Preserve adjacent compare/test + Jcc pairs for FR-721 Macro-Fusion Awareness.

The post-RA scheduler is conservative, but this helper provides a deterministic
post-pass that repairs the common VM shape where a comparison immediately feeds a
VM-JUMP-ZERO.  Non-candidate instructions retain their relative order."
  (labels ((walk (rest acc)
             (cond
               ((endp rest) (nreverse acc))
               ((and (consp (cdr rest))
                     (x86-64-macro-fusion-candidate-p (first rest) (second rest)))
                (walk (cddr rest) (list* (second rest) (first rest) acc)))
               (t (walk (cdr rest) (cons (first rest) acc))))))
    (walk instructions nil)))
