(in-package :cl-cc/codegen-native/scheduling)

(defun %native-inst-touches-phys-p (inst phys-key assignment)
  "Return true when INST reads or writes a virtual register assigned to PHYS-KEY."
  (or (some (lambda (reg) (eq (gethash reg assignment) phys-key))
            (instruction-defs inst))
      (some (lambda (reg) (eq (gethash reg assignment) phys-key))
            (instruction-uses inst))))

(defun %native-inst-reads-phys-p (inst phys-key assignment)
  "Return true when INST reads a virtual register assigned to PHYS-KEY."
  (some (lambda (reg) (eq (gethash reg assignment) phys-key))
        (instruction-uses inst)))

(defun %native-common-dominator (blocks)
  "Return the nearest common dominator for BLOCKS."
  (labels ((depth (b)
             (loop with n = 0
                   for cur = b then (bb-idom cur)
                   while (and cur (not (eq cur (bb-idom cur))))
                   do (incf n)
                   finally (return n)))
           (raise (b n)
             (loop repeat n do (setf b (bb-idom b)) finally (return b)))
           (join2 (a b)
             (let ((da (depth a))
                   (db (depth b)))
               (when (> da db) (setf a (raise a (- da db))))
               (when (> db da) (setf b (raise b (- db da))))
               (loop until (eq a b)
                     do (setf a (bb-idom a)
                              b (bb-idom b)))
               a)))
    (reduce #'join2 (rest blocks) :initial-value (first blocks))))

(defun %native-block-terminator (block)
  "Return BLOCK's final control-transfer instruction, if present."
  (let ((last (car (last (bb-instructions block)))))
    (and (typep last '(or vm-jump vm-jump-zero vm-ret vm-halt)) last)))

;; Per-instruction emitters (emit-vm-halt-inst through emit-vm-spill-load-inst),
;; *x86-64-emitter-entries*, *x86-64-emitter-table*, and
;; emit-vm-instruction-with-labels are in x86-64-codegen-dispatch.lisp (loaded next).

(defun codegen-hot-cold-ordered-instructions (instructions)
  "Return INSTRUCTIONS in the CFG hot/cold order used for native emission.

FR-036: codegen must emit the flat instruction stream produced by the optimizer's
CFG layout logic, not the original basic-block order.  CFG-FLATTEN-HOT-COLD also
patches broken implicit fall-through edges, so both label-offset computation and
the second emission pass must consume this exact list."
  (let ((cfg (cfg-build instructions)))
    (if (cfg-entry cfg)
        (progn
          (cfg-compute-dominators cfg)
          (cfg-compute-loop-depths cfg)
          (cfg-flatten-hot-cold cfg))
        instructions)))

(defparameter *shrink-wrap-enabled* t
  "When true, native backends may split callee-save saves/restores around the
   blocks that actually touch those registers.  Frame setup, stack probes,
   stack canaries, and final returns remain anchored at function entry/exit.")
