;;;; packages/emit/src/regalloc-advanced.lisp — FR-736 BURS Instruction Selection
;;;;
;;;; Bottom-Up Rewrite System instruction selection, consumed by cl-cc's own
;;;; test suite (packages/emit/tests/regalloc-tests.lisp). The Phase 132 batch
;;;; this file originally shipped with also included FR-734 register
;;;; coalescing, FR-735 rematerialization and FR-737 anti-dependence breaking;
;;;; all three were dead (superseded by working implementations in
;;;; regalloc/src/regalloc-allocate.lisp, regalloc/src/regalloc.lisp and
;;;; regalloc/src/regalloc-spill.lisp) and removed in 2026-07.

(in-package :cl-cc/emit)

(defstruct burs-rule
  "A BURS (Bottom-Up Rewrite System) instruction selection rule."
  (pattern nil :type list)
  (replacement nil :type list)
  (cost 1 :type fixnum))

(defvar *burs-rules* nil
  "List of all BURS rewrite rules for instruction selection.")

(defun register-burs-rule (pattern replacement &optional (cost 1))
  "Register a BURS rewrite rule: PATTERN → REPLACEMENT with COST."
  (push (make-burs-rule :pattern pattern :replacement replacement :cost cost)
        *burs-rules*))

(defconstant +burs-terminal-cost+ 1000
  "Fallback cost for covering terminal IR leaves without a registered rule.")

(defun %burs-pattern-frontier (pattern tree)
  "Return frontier subtrees when PATTERN structurally matches TREE, or NIL.
Symbol leaves in PATTERN are tile operands and must match terminal IR leaves.
Conses in PATTERN must match the IR operator and arity exactly."
  (cond
    ((symbolp pattern)
     (and (atom tree) (list tree)))
    ((and (consp pattern) (consp tree)
          (eq (car pattern) (car tree))
          (= (length pattern) (length tree)))
     (loop for pattern-child in (cdr pattern)
           for tree-child in (cdr tree)
           for frontier = (%burs-pattern-frontier pattern-child tree-child)
           when (null frontier)
             do (return nil)
           append frontier))
    (t nil)))

(defun %make-burs-terminal-rule (tree)
  "Create a synthetic terminal-covering rule for TREE."
  (make-burs-rule :pattern (list 'terminal tree)
                  :replacement (list 'identity tree)
                  :cost +burs-terminal-cost+))

(defun burs-select-instructions (ir-tree)
  "Select optimal instruction sequence for IR-TREE using BURS dynamic programming.
Computes minimum-cost covering of each node."
  (let ((memo (make-hash-table :test #'equal))
        (ordered-rules (reverse *burs-rules*)))
    (labels ((cover (tree)
               (multiple-value-bind (cached cached-p) (gethash tree memo)
                 (if cached-p
                     (values (first cached) (second cached))
                     (multiple-value-bind (rules cost) (cover-uncached tree)
                       (setf (gethash tree memo) (list rules cost))
                       (values rules cost)))))
             (cover-uncached (tree)
               (if (atom tree)
                   (let ((rule (%make-burs-terminal-rule tree)))
                     (values (list rule) (burs-rule-cost rule)))
                   (let ((best-cost most-positive-fixnum)
                         (best-rules nil))
                     (dolist (rule ordered-rules)
                       (let ((frontier (%burs-pattern-frontier
                                        (burs-rule-pattern rule) tree)))
                         (when frontier
                           (let ((candidate-cost (burs-rule-cost rule))
                                 (candidate-rules nil)
                                 (valid-cover-p t))
                             (dolist (subtree frontier)
                               (multiple-value-bind (subtree-rules subtree-cost)
                                   (cover subtree)
                                 (if subtree-rules
                                     (progn
                                       (incf candidate-cost subtree-cost)
                                       (setf candidate-rules
                                             (append candidate-rules subtree-rules)))
                                     (setf valid-cover-p nil))))
                             (when (and valid-cover-p (< candidate-cost best-cost))
                               (setf best-cost candidate-cost)
                               (setf best-rules (append candidate-rules
                                                        (list rule))))))))
                     (if best-rules
                         (values best-rules best-cost)
                         (error "No BURS cover for IR tree: ~S" tree))))))
      (cover ir-tree))))

;; Pre-register standard x86-64 BURS rules
(eval-when (:load-toplevel :execute)
  (register-burs-rule '(add (load addr) reg) '(add reg (mem addr)) 2)
  (register-burs-rule '(add reg1 reg2) '(add reg1 reg2) 1)
  (register-burs-rule '(mul reg const) '(lea reg (reg const)) 1))

;; ── Exports ──
(export '(burs-rule make-burs-rule *burs-rules*
          register-burs-rule burs-select-instructions))
