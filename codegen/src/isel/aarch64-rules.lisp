(in-package :cl-cc/codegen)
;;;; FR-299: MIR ISel rules — AArch64 target
(define-isel-rules *isel-aarch64-rules* :aarch64
  (:a64-movz-imm (:const ?value) :movz 1 1)
  (:a64-reg (:reg ?name) :reg 0 1)
  (:a64-move (:move ?src) :mov 1 1)
  (:a64-add-reg (:add ?lhs ?rhs) :add 1 1)
  (:a64-add-scaled-address
   (:add ?base (:mul ?index (:const ?scale)))
   :add-scaled 1 3)
  (:a64-sub-reg (:sub ?lhs ?rhs) :sub 1 1)
  (:a64-mul-reg (:mul ?lhs ?rhs) :mul 2 1)
  (:a64-ldr-scaled
   (:load ?base (:mul ?index (:const ?scale)))
   :ldr-scaled 1 3)
  (:a64-bitfield-extract
   (:band (:shr ?value (:const ?lsb)) (:const ?mask))
   :ubfx 1 4))
