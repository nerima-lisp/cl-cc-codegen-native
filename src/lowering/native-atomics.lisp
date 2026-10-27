(in-package :cl-cc/codegen-native/lowering)

(defun codegen-memory-order (order)
  "Normalize C11 memory order keywords for backend lowering."
  (case order
    ((nil :seq-cst) :seq-cst)
    ((:acquire :release :relaxed) order)
    ((:acq-rel) :seq-cst)
    (otherwise (error "Invalid atomic memory order: ~S" order))))

(defun vm-atomic-memory-order* (inst)
  "Return INST's memory order when present; VM atomics default to :SEQ-CST."
  (declare (ignore inst))
  :seq-cst)
