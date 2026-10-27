;;;; packages/emit/tests/mir-isel-tests.lisp — MIR pipeline / ISel smoke tests

(in-package :cl-cc/codegen-native/lowering/test)


(it-sequential "mir-isel-maximal-munch-prefers-largest-x86-tile"
  (let* ((tree '(:add (:reg r1) (:add (:mul (:reg r2) (:const 4)) (:const 8))))
         (tiles (cl-cc/codegen-native/lowering:isel-maximal-munch tree :x86-64))
         (root-rule (car (last tiles))))
    (expect (cl-cc/codegen-native/lowering:isel-rule-name (car root-rule)) :to-be :x86-lea-address)))

(it-sequential "mir-isel-maximal-munch-prefers-aarch64-scaled-address"
  (let* ((tree '(:add (:reg x1) (:mul (:reg x2) (:const 8))))
         (tiles (cl-cc/codegen-native/lowering:isel-maximal-munch tree :aarch64))
         (root-rule (car (last tiles))))
    (expect (cl-cc/codegen-native/lowering:isel-rule-name (car root-rule)) :to-be :a64-add-scaled-address)))

(it-sequential "mir-vm-program-roundtrip-preserves-unsupported-instructions"
  (let* ((instructions (list (cl-cc/vm:make-vm-const :dst 0 :value 1)
                             (cl-cc/vm:make-vm-print :reg 0)
                             (cl-cc/vm:make-vm-halt :reg 0)))
         (program (cl-cc/vm:make-vm-program :instructions instructions :result-register 0))
         (selected (cl-cc/codegen-native/lowering:isel-vm-program program :target :x86-64)))
    (expect (= (length instructions) (length (cl-cc/vm:vm-program-instructions selected))) :to-be-truthy)
    (expect (typep (second (cl-cc/vm:vm-program-instructions selected)) 'cl-cc/vm:vm-print) :to-be-truthy)))

(it-sequential "mir-vm-program-constant-folds-before-isel"
  (let* ((program (cl-cc/vm:make-vm-program
                   :instructions (list (cl-cc/vm:make-vm-const :dst 0 :value 2)
                                       (cl-cc/vm:make-vm-const :dst 1 :value 3)
                                       (cl-cc/vm:make-vm-add :dst 2 :lhs 0 :rhs 1)
                                       (cl-cc/vm:make-vm-halt :reg 2))
                   :result-register 2))
         (selected (cl-cc/codegen-native/lowering:isel-vm-program program :target :x86-64))
         (insts (cl-cc/vm:vm-program-instructions selected)))
    (expect (typep (third insts) 'cl-cc/vm:vm-const) :to-be-truthy)
    (expect (cl-cc/vm:vm-value (third insts)) :to-equal 5)))

