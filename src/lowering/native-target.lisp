(in-package :cl-cc/codegen-native/lowering)

(defclass target () ())

(defgeneric emit-instruction (target instruction stream))

(defgeneric target-register (target virtual-register))

;;; Byte-vector output used by native target emitters.

(defmacro with-output-to-vector ((stream-var) &body body)
  "Execute BODY with STREAM-VAR bound to an output stream that collects bytes into a vector."
  `(let ((bytes '()))
      (flet ((stream-write-byte (byte)
               (push byte bytes)))
        (let ((,stream-var #'stream-write-byte))
          ,@body
          (coerce (nreverse bytes) '(simple-array (unsigned-byte 8) (*)))))))
