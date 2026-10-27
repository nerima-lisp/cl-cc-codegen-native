;;;; packages/codegen/src/wasm-binary.lisp — WASM Binary Backend (FR-297)
;;;
;;; Binary encoding: LEB128, section buffers, type/function/export sections,
;;; module serialization, and compile-to-wasm-binary entry point.
;;;
;;; Load order: after wasm-feature-params.lisp and before wasm-output.lisp.
;;; AOT helpers live in wasm-aot.lisp.
;;; Debug/devtools custom sections live in wasm-binary-debug.lisp.

(in-package :cl-cc/codegen-native/targets/wasm)

;;; ─────────────────────────────────────────────────────────────────────────────
;;; WASM binary backend (FR-297)
;;; ─────────────────────────────────────────────────────────────────────────────

(defun wasm-binary-write-u8 (buffer byte)
  "Write BYTE to BUFFER using the unified byte-buffer API."
  (cl-cc/binary::buffer-write-byte buffer byte))

(defun wasm-binary-write-bytes (buffer bytes)
  "Write BYTES to BUFFER using the unified byte-buffer API."
  (cl-cc/binary::buffer-write-bytes buffer bytes))

(defun wasm-encode-unsigned-leb128 (value)
  "Return VALUE encoded as an unsigned LEB128 byte vector."
  (coerce (cl-cc/binary/wasm:encode-uleb128 value)
          '(simple-array (unsigned-byte 8) (*))))

(defun wasm-encode-signed-leb128 (value)
  "Return VALUE encoded as a signed LEB128 byte vector."
  (coerce (cl-cc/binary/wasm:encode-sleb128 value)
          '(simple-array (unsigned-byte 8) (*))))

(defun wasm-binary-write-uleb128 (buffer value)
  "Write VALUE as unsigned LEB128 to BUFFER."
  (wasm-binary-write-bytes buffer (wasm-encode-unsigned-leb128 value)))

(defun wasm-binary-section-buffer ()
  "Create a temporary byte-buffer for a section payload."
  (cl-cc/binary::make-byte-buffer 32))

(defun wasm-binary-section-bytes (writer)
  "Return bytes produced by calling WRITER with a temporary section buffer."
  (let ((payload (wasm-binary-section-buffer)))
    (funcall writer payload)
    (cl-cc/binary::buffer-get-bytes payload)))

(defun wasm-binary-write-section (buffer section-id writer)
  "Write a standard WASM section with SECTION-ID and payload from WRITER."
  (wasm-binary-write-bytes
   buffer
   (cl-cc/binary/wasm:encode-wasm-section
    section-id
    (wasm-binary-section-bytes writer))))

(defun wasm-binary-write-name (buffer name)
  "Write NAME as a UTF-8 WebAssembly name."
  (let ((bytes (sb-ext:string-to-octets name :external-format :utf-8)))
    (wasm-binary-write-uleb128 buffer (length bytes))
    (wasm-binary-write-bytes buffer bytes)))

(defparameter *wasm-value-type-byte-table*
  ;; Populated at load time so the constants are already bound.
  (list (cons :i32      +wasm-i32+)
        (cons :i64      +wasm-i64+)
        (cons :f32      +wasm-f32+)
        (cons :f64      +wasm-f64+)
        (cons :f16      +wasm-f16+)
        (cons :funcref  +wasm-funcref+)
        (cons :externref +wasm-externref+)
        (cons :stringref +wasm-stringref+)
        (cons :eqref    +wasm-eqref+))
  "Alist mapping WASM value-type keywords to their binary encoding bytes.")

(defun wasm-binary-value-type-byte (type)
  "Return binary value-type byte for TYPE."
  (let ((entry (assoc type *wasm-value-type-byte-table*)))
    (or (and entry (cdr entry))
        (error "Unknown WASM value type: ~S" type))))

(defun wasm-binary-write-valtype-vector (buffer types)
  "Write a vector of value TYPES."
  (wasm-binary-write-uleb128 buffer (length types))
  (dolist (type types)
    (wasm-binary-write-u8 buffer (wasm-binary-value-type-byte type))))

(defun wasm-binary-write-func-type (buffer params results)
  "Write a WASM function type."
  (wasm-binary-write-u8 buffer +wasm-type-func+)
  (wasm-binary-write-valtype-vector buffer params)
  (wasm-binary-write-valtype-vector buffer results))

(defun wasm-encode-vm-instruction-opcode (inst)
  "Return core WASM opcode bytes corresponding to VM instruction INST."
  (typecase inst
    (vm-const
     (let ((value (vm-value inst)))
       (cond
         ((integerp value)
          (concatenate '(simple-array (unsigned-byte 8) (*))
                       (vector +wasm-i64-const+)
                       (wasm-encode-signed-leb128 value)))
         ((null value) (vector +wasm-ref-null+ +heap-none+))
         (t (error "Unsupported WASM binary VM-CONST literal: ~S" value)))))
    ((or vm-float-add vm-float-sub vm-float-mul vm-float-div)
     (%wasm-reject-float-arithmetic inst))
    ((or vm-add vm-integer-add) (vector +wasm-i64-add+))
    ((or vm-sub vm-integer-sub) (vector +wasm-i64-sub+))
    ((or vm-mul vm-integer-mul) (vector +wasm-i64-mul+))
    (vm-rotate (vector +wasm-i64-rotr+))
    (vm-logcount (vector +wasm-i64-popcnt+))
    (vm-integer-length (vector +wasm-i64-clz+))
    (vm-call (concatenate '(simple-array (unsigned-byte 8) (*))
                          (vector +wasm-call-indirect+)
                          (wasm-encode-unsigned-leb128 +type-idx-main-func+)
                          (wasm-encode-unsigned-leb128 0)))
    (vm-ret (vector +wasm-return+))
    (vm-halt (vector +wasm-return+))
    (t (error "Unsupported WASM binary instruction: ~A" (type-of inst)))))

(defun wasm-binary-module-functions (module)
  "Return MODULE functions in emission order."
  (or (wasm-module-functions module) nil))

(defun wasm-binary-write-type-section (buffer &key (params nil) (results nil))
  "Write a Type section containing a single MVP function signature."
  (wasm-binary-write-bytes
   buffer
   (cl-cc/binary/wasm:encode-wasm-type-section
    (list (list (mapcar #'wasm-binary-value-type-byte params)
                (mapcar #'wasm-binary-value-type-byte results))))))

(defun wasm-binary-write-function-section (buffer functions)
  "Write the Function section for FUNCTIONS, all using type index 0."
  (wasm-binary-write-bytes
   buffer
   (cl-cc/binary/wasm:encode-wasm-function-section
    (make-list (length functions) :initial-element 0))))

(defun wasm-binary-export-name-for-function (func)
  "Return FUNC's export name, or NIL when it should not be exported."
  (when (wasm-func-exported-p func)
    (or (wasm-func-export-name func)
        (let ((wat-name (wasm-func-wat-name func)))
          (if (and wat-name (> (length wat-name) 0)
                   (char= (char wat-name 0) #\$))
              (subseq wat-name 1)
              wat-name)))))

(defun wasm-binary-write-export-section (buffer functions)
  "Write the Export section for exported FUNCTIONS."
  (let ((exports (remove-if-not #'wasm-binary-export-name-for-function functions)))
    (when exports
      (wasm-binary-write-bytes
       buffer
       (cl-cc/binary/wasm:encode-wasm-export-section
        (mapcar (lambda (func)
                  (list (wasm-binary-export-name-for-function func)
                        +wasm-export-func+
                        (or (wasm-func-index func) 0)))
                exports))))))

(defun wasm-binary-write-local-decls (buffer local-groups)
  "Write local declaration groups as (COUNT TYPE) entries."
  (wasm-binary-write-uleb128 buffer (length local-groups))
  (dolist (group local-groups)
    (destructuring-bind (count type) group
      (wasm-binary-write-uleb128 buffer count)
      (wasm-binary-write-u8 buffer (wasm-binary-value-type-byte type)))))

(defun wasm-binary-function-body-bytes (func)
  "Return a stack-neutral MVP function body for FUNC."
  (when (wasm-func-source-instructions func)
    (error "Cannot encode WASM binary function ~A instruction ~A"
           (wasm-func-wat-name func)
           (type-of (first (wasm-func-source-instructions func)))))
  (when (wasm-func-body func)
    (error "Cannot encode WAT body for WASM binary function ~A, unsupported instruction ~S"
           (wasm-func-wat-name func)
           (first (wasm-func-body func))))
  (coerce (vector 0 +wasm-end+)
          '(simple-array (unsigned-byte 8) (*))))

(defun wasm-binary-write-code-section (buffer functions)
  "Write the Code section for FUNCTIONS."
  (wasm-binary-write-bytes
   buffer
   (cl-cc/binary/wasm:encode-wasm-code-section
    (mapcar #'wasm-binary-function-body-bytes functions))))

(defun emit-wasm-binary-module (module)
  "Serialize MODULE to a minimal WebAssembly binary module byte array."
  (let* ((functions (wasm-binary-module-functions module))
         (exports (remove-if-not #'wasm-binary-export-name-for-function functions))
         (sections
           (append
            (list
             (cl-cc/binary/wasm:encode-wasm-type-section (list (list nil nil)))
             (cl-cc/binary/wasm:encode-wasm-function-section
              (make-list (length functions) :initial-element 0)))
            (when exports
              (list
               (cl-cc/binary/wasm:encode-wasm-export-section
                (mapcar (lambda (func)
                          (list (wasm-binary-export-name-for-function func)
                                +wasm-export-func+
                                (or (wasm-func-index func) 0)))
                        exports))))
            (list
             (cl-cc/binary/wasm:encode-wasm-code-section
              (mapcar #'wasm-binary-function-body-bytes functions))))))
    (cl-cc/binary/wasm:encode-wasm-module sections)))

(defun compile-to-wasm-binary (program)
  "Compile a vm-program to a minimal WebAssembly binary module byte array."
  (let ((module (extract-wasm-functions program)))
    (emit-wasm-binary-module module)))

;;; AOT helpers (wasm-aot-result struct, tool integration, hashing, base64,
;;; compile-to-aot-wasm) live in wasm-aot.lisp.
;;; Debug/devtools custom sections (DWARF, name section, branch hints, devtools JS)
;;; live in wasm-binary-debug.lisp.
