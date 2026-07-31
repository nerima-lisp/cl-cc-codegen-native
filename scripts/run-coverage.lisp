;;;; scripts/run-coverage.lisp
;;;;
;;;; Run the suite under SBCL's sb-cover instrumentation (via cl-weave's
;;;; built-in :coverage support — no adapter) and print expression/branch
;;;; percentages for codegen/src, regalloc/src and emit/src. Informational:
;;;; unlike run-tests.lisp's test-op, this does not fail the run below any
;;;; threshold. Wire a :coverage-minimum-expression/:coverage-minimum-branch
;;;; gate into cl-cc-codegen-native.asd's :perform once a baseline is known.
;;;;
;;;; sb-cover only instruments code compiled under
;;;; (optimize sb-cover:store-coverage-data); cl-weave's :coverage option
;;;; resets counters and reads them back around the run, it does not
;;;; recompile anything. That policy has to be proclaimed, and the target
;;;; system loaded (forced, so ASDF cannot skip recompilation), before this
;;;; script's own run-all call.

(require :asdf)
(require :sb-cover)

(defun script-directory ()
  (make-pathname :name nil
                 :type nil
                 :defaults (or *load-truename*
                               *compile-file-truename*
                               (error "Unable to determine the script location"))))

(let ((root (script-directory)))
  (asdf:initialize-source-registry
   `(:source-registry (:tree ,(merge-pathnames "../" root)) :inherit-configuration))
  (proclaim '(optimize sb-cover:store-coverage-data))
  (asdf:load-system "cl-cc-codegen-native/test" :force t)
  (let* ((src-dirs (list (asdf:system-relative-pathname "cl-cc-codegen-native" "codegen/src/")
                          (asdf:system-relative-pathname "cl-cc-codegen-native" "regalloc/src/")
                          (asdf:system-relative-pathname "cl-cc-codegen-native" "emit/src/")))
         (passed (uiop:symbol-call :cl-weave :run-all :reporter :spec
                                    :coverage t
                                    :coverage-include-pathnames src-dirs))
         (stats (uiop:symbol-call :cl-weave :coverage-statistics
                                   :include-pathnames src-dirs)))
    (destructuring-bind (&key expression-covered expression-total
                               branch-covered branch-total)
        stats
      (format t "~&~%Coverage (codegen/src, regalloc/src, emit/src):~%")
      (format t "  Expression: ~,1F% (~D/~D)~%"
              (if (zerop expression-total) 100.0
                  (* 100.0 (/ expression-covered expression-total)))
              expression-covered expression-total)
      (format t "  Branch:     ~,1F% (~D/~D)~%"
              (if (zerop branch-total) 100.0
                  (* 100.0 (/ branch-covered branch-total)))
              branch-covered branch-total))
    (unless passed
      (uiop:quit 1))))
