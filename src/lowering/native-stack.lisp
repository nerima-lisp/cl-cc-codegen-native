(in-package :cl-cc/codegen-native/lowering)

(defconstant +stack-probe-page-size+ 4096
  "Page stride used by native backend stack probing.")

(defun stack-probe-count (frame-size)
  "Return how many guard-page probes are needed for FRAME-SIZE bytes."
  (if (>= frame-size +stack-probe-page-size+)
      (floor frame-size +stack-probe-page-size+)
      0))
