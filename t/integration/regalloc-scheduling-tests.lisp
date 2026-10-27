(in-package :cl-cc/codegen-native/scheduling/test)

;;; FR-068: Post-RA Instruction Scheduling

(defun %test-regalloc-result (pairs)
  (let ((assignment (make-hash-table :test #'eq)))
    (dolist (pair pairs)
      (setf (gethash (car pair) assignment) (cdr pair)))
    (cl-cc/codegen-native/regalloc::make-regalloc-result
     :assignment assignment
     :spill-map (make-hash-table :test #'eq)
     :spill-count 0
     :instructions nil)))
(it-sequential "post-ra-scheduler-reorders-independent-instructions"
  (let* ((insts (list (cl-cc/vm:make-vm-const :dst :r0 :value 1)
                      (cl-cc/vm:make-vm-mul :dst :r2 :lhs :r3 :rhs :r4)
                      (cl-cc/vm:make-vm-halt :reg :r0)))
         (ra (%test-regalloc-result '((:r0 . :rax) (:r2 . :rdx)
                                      (:r3 . :rbx) (:r4 . :rcx))))
         (scheduled (cl-cc/codegen-native/scheduling:schedule-post-ra insts ra)))
    (expect (typep (first scheduled) 'cl-cc/vm:vm-mul) :to-be-truthy)
    (expect (typep (second scheduled) 'cl-cc/vm:vm-const) :to-be-truthy)
    (expect (typep (third scheduled) 'cl-cc/vm:vm-halt) :to-be-truthy)))

(it-sequential "post-ra-scheduler-preserves-raw-dependencies"
  (let* ((insts (list (cl-cc/vm:make-vm-const :dst :r0 :value 1)
                      (cl-cc/vm:make-vm-add :dst :r1 :lhs :r0 :rhs :r2)
                      (cl-cc/vm:make-vm-halt :reg :r1)))
         (ra (%test-regalloc-result '((:r0 . :rax) (:r1 . :rcx) (:r2 . :rdx))))
         (scheduled (cl-cc/codegen-native/scheduling:schedule-post-ra insts ra)))
    (expect (typep (first scheduled) 'cl-cc/vm:vm-const) :to-be-truthy)
    (expect (typep (second scheduled) 'cl-cc/vm:vm-add) :to-be-truthy)
    (expect (typep (third scheduled) 'cl-cc/vm:vm-halt) :to-be-truthy)))

(it-sequential "post-ra-scheduler-preserves-physical-waw-dependencies"
  (let* ((insts (list (cl-cc/vm:make-vm-const :dst :r0 :value 1)
                      (cl-cc/vm:make-vm-const :dst :r1 :value 2)
                      (cl-cc/vm:make-vm-halt :reg :r1)))
         (ra (%test-regalloc-result '((:r0 . :rax) (:r1 . :rax))))
         (scheduled (cl-cc/codegen-native/scheduling:schedule-post-ra insts ra)))
    (expect (cl-cc/vm:vm-dst (first scheduled)) :to-be :r0)
    (expect (cl-cc/vm:vm-dst (second scheduled)) :to-be :r1)
    (expect (typep (third scheduled) 'cl-cc/vm:vm-halt) :to-be-truthy)))

(it-sequential "post-ra-scheduler-treats-unknown-registers-as-barriers"
  (let* ((unknown (cl-cc/vm:make-vm-const :dst :unknown :value 7))
         (insts (list (cl-cc/vm:make-vm-const :dst :r0 :value 1)
                      unknown
                      (cl-cc/vm:make-vm-mul :dst :r2 :lhs :r3 :rhs :r4)
                      (cl-cc/vm:make-vm-halt :reg :r0)))
         (ra (%test-regalloc-result '((:r0 . :rax) (:r2 . :rdx)
                                      (:r3 . :rbx) (:r4 . :rcx))))
         (scheduled (cl-cc/codegen-native/scheduling:schedule-post-ra insts ra)))
    (expect (typep (first scheduled) 'cl-cc/vm:vm-const) :to-be-truthy)
    (expect (second scheduled) :to-be unknown)
    (expect (typep (third scheduled) 'cl-cc/vm:vm-mul) :to-be-truthy)
    (expect (typep (fourth scheduled) 'cl-cc/vm:vm-halt) :to-be-truthy)))

(it-sequential "post-ra-scheduler-integrates-with-native-backends"
  (let ((program (cl-cc/vm:make-vm-program
                  :instructions (list (cl-cc/vm:make-vm-const :dst :r0 :value 1)
                                      (cl-cc/vm:make-vm-const :dst :r1 :value 2)
                                      (cl-cc/vm:make-vm-add :dst :r2 :lhs :r0 :rhs :r1)
                                      (cl-cc/vm:make-vm-halt :reg :r2))
                  :result-register :r2
                  :leaf-p t)))
    (dolist (bytes (list (cl-cc/codegen-native/targets/x86-64:compile-to-x86-64-bytes program)
                         (cl-cc/codegen-native/targets/aarch64:compile-to-aarch64-bytes program)
                         (cl-cc/codegen-native/targets/riscv64:compile-to-riscv64-bytes program)))
      (expect (typep bytes '(simple-array (unsigned-byte 8) (*))) :to-be-truthy)
      (expect (plusp (length bytes)) :to-be-truthy))))
