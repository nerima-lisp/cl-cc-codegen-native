(in-package :cl-cc/codegen-native/lowering/test)

(it-sequential "burs-select-instructions-selects-minimum-cost-cover"
  (let ((cl-cc/codegen-native/lowering:*burs-rules* nil))
    (cl-cc/codegen-native/lowering:register-burs-rule '(add lhs rhs) '(slow-add lhs rhs) 10)
    (cl-cc/codegen-native/lowering:register-burs-rule '(add lhs rhs) '(fast-add lhs rhs) 1)
    (multiple-value-bind (rules cost)
        (cl-cc/codegen-native/lowering:burs-select-instructions '(add r1 r2))
      (expect (= 2001 cost) :to-be-truthy)
      (expect (mapcar #'cl-cc/codegen-native/lowering::burs-rule-replacement rules) :to-equal '((identity r1) (identity r2) (fast-add lhs rhs))))))

(it-sequential "burs-select-instructions-prefers-earlier-rule-on-cost-tie"
  (let ((cl-cc/codegen-native/lowering:*burs-rules* nil))
    (cl-cc/codegen-native/lowering:register-burs-rule '(add lhs rhs) '(first-add lhs rhs) 1)
    (cl-cc/codegen-native/lowering:register-burs-rule '(add lhs rhs) '(second-add lhs rhs) 1)
    (multiple-value-bind (rules cost)
        (cl-cc/codegen-native/lowering:burs-select-instructions '(add r1 r2))
      (expect (= 2001 cost) :to-be-truthy)
      (expect (cl-cc/codegen-native/lowering::burs-rule-replacement (third rules)) :to-equal '(first-add lhs rhs)))))

(it-sequential "burs-select-instructions-matches-nested-tile-patterns"
  (let ((cl-cc/codegen-native/lowering:*burs-rules* nil))
    (cl-cc/codegen-native/lowering:register-burs-rule '(add (load addr) reg) '(add reg (mem addr)) 2)
    (cl-cc/codegen-native/lowering:register-burs-rule '(add reg1 reg2) '(add reg1 reg2) 1)
    (multiple-value-bind (rules cost)
        (cl-cc/codegen-native/lowering:burs-select-instructions '(add (load local) r1))
      (expect (= 2002 cost) :to-be-truthy)
      (expect (mapcar #'cl-cc/codegen-native/lowering::burs-rule-replacement rules) :to-equal '((identity local) (identity r1) (add reg (mem addr)))))))

(it-sequential "burs-select-instructions-signals-on-uncoverable-nonterminal"
  (let ((cl-cc/codegen-native/lowering:*burs-rules* nil))
    (let ((%%signaled1 nil)) (handler-case (progn (cl-cc/codegen-native/lowering:burs-select-instructions '(unknown r1))) (error () (setf %%signaled1 t))) (expect %%signaled1 :to-be-truthy))))
