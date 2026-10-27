;;;; t/wasm-binary-golden-test.lisp: WASM binary serialization golden

(in-package :cl-cc-codegen-native/test)

(describe-sequential "WASM standard module serialization golden"
  (it "matches the public binary API and fixed bytes for one exported empty function"
    (let* ((module (cl-cc/codegen-native/targets/wasm::make-empty-wasm-module))
           (func (cl-cc/codegen-native/targets/wasm::make-wasm-function-def
                  :wat-name "main"
                  :exported-p t
                  :export-name "run"))
           (public-api-bytes
             (cl-cc/binary/wasm:encode-wasm-module
              (list
               (cl-cc/binary/wasm:encode-wasm-type-section (quote ((nil nil))))
               (cl-cc/binary/wasm:encode-wasm-function-section (quote (0)))
               (cl-cc/binary/wasm:encode-wasm-export-section (quote (("run" 0 0))))
               (cl-cc/binary/wasm:encode-wasm-code-section (quote (#(#x00 #x0b)))))))
           (golden-bytes
             #(#x00 #x61 #x73 #x6d #x01 #x00 #x00 #x00
               #x01 #x04 #x01 #x60 #x00 #x00
               #x03 #x02 #x01 #x00
               #x07 #x07 #x01 #x03 #x72 #x75 #x6e #x00 #x00
               #x0a #x04 #x01 #x02 #x00 #x0b)))
      (cl-cc/codegen-native/targets/wasm::wasm-module-add-function module func)
      (let ((native-bytes
              (cl-cc/codegen-native/targets/wasm:emit-wasm-binary-module module)))
        (expect native-bytes :to-equalp public-api-bytes)
        (expect native-bytes :to-equalp golden-bytes)
        (expect public-api-bytes :to-equalp golden-bytes)))))

