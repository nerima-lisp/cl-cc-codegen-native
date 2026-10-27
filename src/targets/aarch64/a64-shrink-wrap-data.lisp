(in-package :cl-cc/codegen-native/targets/aarch64)

(defstruct a64-shrink-save
  "Codegen-local pseudo-instruction that saves one AArch64 callee-saved pair."
  pair)

(defstruct a64-shrink-restore
  "Codegen-local pseudo-instruction that restores one AArch64 callee-saved pair."
  pair)
