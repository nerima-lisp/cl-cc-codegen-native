;;;; packages/codegen/src/win-cfg.lisp - Windows Control Flow Guard support (FR-773)

(in-package :cl-cc/codegen-native/hardening)

(defparameter *win-cfg-enabled* nil
  "When true, experimental Windows Control Flow Guard checks may be emitted.")

(defvar *win-cfg-function-table* (make-hash-table :test #'eq)
  "Process-local GuardCF function-id table used by generated indirect calls.")

(define-condition win-cfg-invalid-target (error)
  ((target :initarg :target :reader win-cfg-invalid-target))
  (:report (lambda (c stream)
             (format stream "Windows CFG rejected indirect-call target: ~S"
                     (win-cfg-invalid-target c)))))

(defun win-cfg-register-function (target &key (name target))
  "Register TARGET in the GuardCF function-id table and return TARGET."
  (setf (gethash target *win-cfg-function-table*) name)
  target)

(defun win-cfg-unregister-function (target)
  "Remove TARGET from the GuardCF function-id table."
  (remhash target *win-cfg-function-table*)
  target)

(defun win-cfg-function-registered-p (target)
  "Return true when TARGET is present in the GuardCF function-id table."
  (nth-value 1 (gethash target *win-cfg-function-table*)))

(defun win-cfg-function-table-entries ()
  "Return GuardCF table entries as (TARGET . NAME) pairs."
  (let ((entries nil))
    (maphash (lambda (target name) (push (cons target name) entries))
             *win-cfg-function-table*)
    (nreverse entries)))

(defun _guard_check_icall (target)
  "Validate TARGET against the GuardCF function-id table.

When CFG support is disabled, return TARGET unchanged.  When enabled, TARGET
must have been registered with WIN-CFG-REGISTER-FUNCTION."
  (cond
    ((not *win-cfg-enabled*) target)
    ((win-cfg-function-registered-p target) target)
    (t (error 'win-cfg-invalid-target :target target))))

(defun _guard_dispatch_icall (target &rest args)
  "Validate TARGET with _guard_check_icall and dispatch to it with ARGS."
  (apply (_guard_check_icall target) args))                           ; reject trap                           ; reject trap

(defun win-cfg-guard-fids-table-metadata (&optional (entries (win-cfg-function-table-entries)))
  "Return PE/COFF GuardCF __guard_fids_table section metadata.

Each row contains the registered target, symbolic name, and GFID flags.  The
section descriptor is deliberately data-only so object writers can lower it into
.gfids$y / load-config records without coupling to a concrete COFF writer."
  (list :section "__guard_fids_table"
        :comdat ".gfids$y"
        :entry-size 8
        :flags '(:image-scn-cnt-initialized-data :image-scn-mem-read)
        :entries (mapcar (lambda (entry)
                           (list :target (car entry)
                                 :name (cdr entry)
                                 :guard-flags #x1))
                         entries)))

(defun win-cfg-guard-check-icall-symbol ()
  "Return the external symbol name used by Windows CFG indirect-call checks."
  "_guard_check_icall")

(defun win-cfg-guard-dispatch-icall-symbol ()
  "Return the external symbol name used by Windows CFG guarded dispatch."
  "_guard_dispatch_icall")

(defun win-cfg-enabled-p ()
  "Return true only when experimental Windows CFG support is enabled."
  (and *win-cfg-enabled* t))
