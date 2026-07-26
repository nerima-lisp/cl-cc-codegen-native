;;;; t/package.lisp — test package for cl-cc-codegen-native
;;;;
;;;; CL-WEAVE:DESCRIBE collides with CL:DESCRIBE. Shadowing-import it: the
;;;; suite uses the test-framework meaning throughout.

(defpackage :cl-cc-codegen-native/test
  (:use :cl :cl-weave)
  (:shadowing-import-from :cl-weave #:describe))
