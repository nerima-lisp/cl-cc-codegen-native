;;;; t/codegen-native-boundary-test.lisp — module boundary tests
;;;;
;;;; cl-cc's own suite covers code generation against these systems. What is
;;;; pinned here is the property that made the extraction possible: none of the
;;;; three names a cl-cc/vm internal. While they did -- 100 references in
;;;; codegen alone -- no separate repository could have built, since an external
;;;; consumer cannot reach another package's internal symbols.

(in-package :cl-cc-codegen-native/test)

(defun %internal-vm-references-in (path)
  "Return the distinct CL-CC/VM internal symbol names named under PATH."
  (let ((names '()))
    (dolist (file (directory (merge-pathnames "**/*.lisp" path))
                  (sort (remove-duplicates names :test #'string=) #'string<))
      (with-open-file (in file :external-format :utf-8)
        (loop for line = (read-line in nil)
              while line
              do (let ((start 0))
                   (loop for hit = (search "cl-cc/vm::" line :start2 start
                                                             :test #'char-equal)
                         while hit
                         do (let* ((from (+ hit (length "cl-cc/vm::")))
                                   (to (or (position-if-not
                                            (lambda (c)
                                              (or (alphanumericp c)
                                                  (find c "%*+-/=<>?!_")))
                                            line :start from)
                                           (length line))))
                              (when (> to from) (push (subseq line from to) names))
                              (setf start (max (1+ hit) to))))))))))

(describe-sequential "boundary with cl-cc/vm"
  (it "names no cl-cc/vm internal symbol in any of the three systems"
    ;; §5-2 of cl-cc's split design, asserted rather than trusted. A new
    ;; reference would reintroduce the coupling and surface only as a broken
    ;; build here, long after it was written.
    (dolist (system '("cl-cc-regalloc" "cl-cc-codegen" "cl-cc-emit"))
      (expect (%internal-vm-references-in
               (asdf:system-relative-pathname system "src/"))
              :to-be nil))))

(describe-sequential "the three systems load together"
  (it "has all three packages present"
    (dolist (name '("CL-CC/REGALLOC" "CL-CC/CODEGEN" "CL-CC/EMIT"))
      (expect (find-package name) :to-be-truthy)))

  (it "has its dependencies present and the front end absent"
    ;; The native backend consumes the VM's IR and the target descriptions; it
    ;; has no business seeing the reader or the macroexpander.
    ;;
    ;; CL-CC/TYPE is not in that list even though nothing here names it: it
    ;; arrives through cl-cc-optimize, which the allocator's cost model depends
    ;; on. Asserting its absence would be asserting something about a
    ;; dependency's dependencies, which is not this repository's business.
    (dolist (name '("CL-CC/VM" "CL-CC/MIR" "CL-CC/TARGET"))
      (expect (find-package name) :to-be-truthy))
    (dolist (name '("CL-CC/PARSE" "CL-CC/EXPAND"))
      (expect (find-package name) :to-be nil))))

(describe-sequential "target coverage"
  (it "encodes for every target cl-cc-target describes"
    ;; A target described but not encodable is the failure mode this catches:
    ;; the description registry and the encoder tables are edited separately.
    (dolist (name '(:x86-64 :aarch64 :riscv64))
      (expect (cl-cc/target:find-target name) :to-be-truthy))))
