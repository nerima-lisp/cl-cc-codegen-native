(in-package :cl-cc/codegen-native/lowering)

(defun vm-const-to-integer (value)
  "Convert a supported VM-CONST literal to its native integer value."
  (cond ((null value) 0)
        ((eq value t) 1)
        ((integerp value) value)
        (t (error "Unsupported VM-CONST literal for native codegen: ~S" value))))
