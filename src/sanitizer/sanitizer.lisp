;;;; packages/codegen/src/sanitizer.lisp — FR-554 sanitizer instrumentation

(in-package :cl-cc/codegen-native/sanitizer)

(defconstant +asan-shadow-base-x86-64+ #x7fff8000
  "Linux x86-64 ASan shadow base.  One shadow byte covers 8 app bytes.")

(defparameter *asan-instrumentation-enabled* nil
  "When true, emit x86-64 ASan shadow checks before memory loads/stores.")

(defparameter *ubsan-instrumentation-enabled* nil
  "When true, emit x86-64 UBSan overflow/null checks around unsafe operations.")

(defparameter *asan-shadow-base* +asan-shadow-base-x86-64+
  "Current ASan shadow-memory base used by native x86-64 instrumentation.")

(defstruct sanitizer-options
  "Sanitizer options carried by the code generator.  Disabled options emit no code."
  (address nil :type boolean)
  (undefined nil :type boolean)
  (shadow-base +asan-shadow-base-x86-64+ :type integer))

(defun sanitizer-enabled-p (&optional (options nil options-supplied-p))
  "Return true when any sanitizer instrumentation is enabled."
  (if options-supplied-p
      (and options
           (or (sanitizer-options-address options)
               (sanitizer-options-undefined options)))
      (or *asan-instrumentation-enabled*
          *ubsan-instrumentation-enabled*)))
