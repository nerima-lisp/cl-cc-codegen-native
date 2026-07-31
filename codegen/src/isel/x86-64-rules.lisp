(in-package :cl-cc/codegen)
;;;; FR-299: MIR ISel rules — x86-64 target
(define-isel-rules *isel-x86-64-rules* :x86-64
  (:x86-mov-imm (:const ?value) :mov-imm 1 1)
  (:x86-reg (:reg ?name) :reg 0 1)
  (:x86-move (:move ?src) :mov 1 1)
  (:x86-add-reg (:add ?lhs ?rhs) :add 1 1)
  (:x86-add-mem-reg (:add (:load ?base ?disp) ?rhs) :add-mem-reg 1 2)
  (:x86-sub-reg (:sub ?lhs ?rhs) :sub 1 1)
  (:x86-mul-reg (:mul ?lhs ?rhs) :imul 2 1)
  (:x86-address-base-index-scale-disp
   (:address ?base (:mul ?index (:const ?scale)) (:const ?disp))
   :x86-address 0 4)
  (:x86-lea-address
   (:add ?base (:add (:mul ?index (:const ?scale)) (:const ?disp)))
   :lea 1 5))
