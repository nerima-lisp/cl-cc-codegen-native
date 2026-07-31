;;;; packages/emit/src/wasm-trampoline.lisp - PC-Dispatch Trampoline Builder
;;;
;;; Converts a flat list of VM instructions (a function body) into a WAT
;;; body using a PC-dispatch trampoline: loop { block { br_table } }.
;;; This bridges the VM's flat label-jump model to WASM structured control flow.
;;;
;;; Basic-block/label infrastructure, atomic lowering policy, and the
;;; register-map local get/set + FR-142 type-tracking primitives that the
;;; rest of the trampoline (and wasm-trampoline-gc.lisp,
;;; wasm-trampoline-fixnum.lisp, wasm-trampoline-proposals.lisp — split out
;;; in 2026-07, all in this same package) build on.

(in-package :cl-cc/codegen)

;;; ─────────────────────────────────────────────────────────────────────────────
;;; Step 1: Group instructions into basic blocks by label
;;; ─────────────────────────────────────────────────────────────────────────────

(defstruct (wasm-basic-block (:conc-name wasm-bb-))
  "A basic block in the function: a label and its instructions."
  (label nil :type (or null string))   ; nil for the implicit entry block
  (pc-index nil :type (or null integer)) ; the $pc value that dispatches here
  (instructions nil :type list))       ; the instructions in this block

(defun group-into-basic-blocks (instructions)
  "Split INSTRUCTIONS into basic blocks at vm-label boundaries.
   Returns a list of wasm-basic-block structs in order."
  (let ((blocks nil)
        (current-label nil)
        (current-instrs nil)
        (pc-counter 0))
    (flet ((flush ()
             (when (or current-label current-instrs)
               (push (make-wasm-basic-block
                      :label current-label
                      :pc-index (prog1 pc-counter (incf pc-counter))
                      :instructions (nreverse current-instrs))
                     blocks)
               (setf current-label nil
                     current-instrs nil))))
      (dolist (inst instructions)
        (if (typep inst 'vm-label)
            (progn
              (flush)
              (setf current-label (vm-name inst)))
            (push inst current-instrs)))
      (flush))
    (nreverse blocks)))

;;; ─────────────────────────────────────────────────────────────────────────────
;;; Step 2: Build a label -> pc-index map
;;; ─────────────────────────────────────────────────────────────────────────────

(defun build-label-pc-map (basic-blocks)
  "Build a hash table from label name (string) -> pc-index (integer)."
  (let ((map (make-hash-table :test #'equal)))
    (dolist (bb basic-blocks map)
      (when (wasm-bb-label bb)
        (setf (gethash (wasm-bb-label bb) map) (wasm-bb-pc-index bb))))))

;;; ─────────────────────────────────────────────────────────────────────────────
;;; Dynamic calling-convention state
;;; ─────────────────────────────────────────────────────────────────────────────

(defvar *wasm-label-to-table-idx* nil
  "Dynamic binding: hash table mapping function entry-label name (string) to its
   WASM funcref table index (= wasm-func-index).  Bound in build-all-wasm-functions
   so that emit-trampoline-instruction can emit real table indices for vm-closure.")

;;; ─────────────────────────────────────────────────────────────────────────────
;;; Wasm atomic lowering policy
;;; ─────────────────────────────────────────────────────────────────────────────

(defun wasm-require-threads-for-atomic (inst)
  "Signal unless INST can be emitted as a true Wasm atomic operation."
  (unless (wasm-threads-feature-enabled-p)
    (error "Wasm atomic instruction ~A requires Wasm threads."
           (type-of inst)))
  t)

(defun wasm-unsupported-atomic-swap (inst)
  "Signal the lack of a correct Wasm atomic swap lowering for INST."
  (error "Wasm atomic swap ~A requires atomic.rmw.xchg lowering."
         (type-of inst)))

(defmacro with-wasm-atomic-threads ((inst) &body body)
  "Run BODY only when Wasm threads are enabled for atomic lowering."
  `(progn
     (wasm-require-threads-for-atomic ,inst)
     ,@body))

;;; ─────────────────────────────────────────────────────────────────────────────
;;; Step 3: Emit WAT for a single instruction
;;; ─────────────────────────────────────────────────────────────────────────────
;;; Returns T if instruction was handled, NIL if not supported (emits comment).
;;; REG-MAP is a wasm-reg-map for mapping :R0 etc. to local indices.
;;; LABEL-PC-MAP maps label names to pc-index integers.
;;; NUM-BLOCKS is total number of basic blocks.

(defun reg-local-ref (reg-map reg)
  "Return WAT for getting a register's local variable, e.g. '(local.get 3)'."
  (format nil "(local.get ~D)" (wasm-reg-to-local reg-map reg)))

(defun reg-local-set (reg-map reg value-wat)
  "Return WAT for setting a register's local variable.
   Also clears any known type for the destination register (FR-142)."
  (let ((known-types (wasm-reg-map-known-types reg-map)))
    (when known-types (remhash reg known-types)))
  (let ((ranges (wasm-reg-map-fixnum-ranges reg-map)))
    (when ranges (remhash reg ranges)))
  (let ((array-types (wasm-reg-map-array-element-types reg-map)))
    (when array-types (remhash reg array-types)))
  (let ((dst (wasm-reg-to-local reg-map reg)))
    (if (and (stringp value-wat)
             (search "(local.get " value-wat)
             (= (position #\( value-wat) 0))
        (format nil "(local.tee ~D ~A)" dst value-wat)
        (format nil "(local.set ~D ~A)" dst value-wat))))

;;; ─────────────────────────────────────────────────────────────────────────────
;;; FR-142: ref.cast elimination — type tracking helpers
;;; ─────────────────────────────────────────────────────────────────────────────

(defun reg-record-type (reg-map reg type-keyword)
  "Record that VM register REG holds a value of wasm type TYPE-KEYWORD.
   TYPE-KEYWORD examples: :closure, :cons, :i31ref, :string, :symbol."
  (let ((known-types (wasm-reg-map-known-types reg-map)))
    (when known-types
      (setf (gethash reg known-types) type-keyword))))

(defun reg-known-type (reg-map reg)
  "Return the known wasm type for VM register REG, or NIL if unknown."
  (let ((known-types (wasm-reg-map-known-types reg-map)))
    (and known-types (gethash reg known-types))))

(defun reg-clear-type (reg-map reg)
  "Clear any known type for VM register REG."
  (let ((known-types (wasm-reg-map-known-types reg-map)))
    (when known-types (remhash reg known-types))))
