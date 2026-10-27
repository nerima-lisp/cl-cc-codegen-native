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
        (expect public-api-bytes :to-equalp golden-bytes))))
  (it "encodes non-ASCII export names as UTF-8"
    (let* ((module (cl-cc/codegen-native/targets/wasm::make-empty-wasm-module))
           (func (cl-cc/codegen-native/targets/wasm::make-wasm-function-def
                  :wat-name "main"
                  :exported-p t
                  :export-name "runλ"))
           (public-api-bytes
             (cl-cc/binary/wasm:encode-wasm-module
              (list
               (cl-cc/binary/wasm:encode-wasm-type-section (list (list nil nil)))
               (cl-cc/binary/wasm:encode-wasm-function-section (list 0))
               (cl-cc/binary/wasm:encode-wasm-export-section (list (list "runλ" 0 0)))
               (cl-cc/binary/wasm:encode-wasm-code-section
                (list #(#x00 #x0b))))))
           (golden-bytes
             #(#x00 #x61 #x73 #x6d #x01 #x00 #x00 #x00
               #x01 #x04 #x01 #x60 #x00 #x00
               #x03 #x02 #x01 #x00
               #x07 #x09 #x01 #x05 #x72 #x75 #x6e #xce #xbb #x00 #x00
               #x0a #x04 #x01 #x02 #x00 #x0b)))
      (cl-cc/codegen-native/targets/wasm::wasm-module-add-function module func)
      (let ((native-bytes
              (cl-cc/codegen-native/targets/wasm:emit-wasm-binary-module module)))
        (expect native-bytes :to-equalp public-api-bytes)
        (expect native-bytes :to-equalp golden-bytes)
        (expect public-api-bytes :to-equalp golden-bytes))
      (expect
       (cl-cc/codegen-native/targets/wasm:wasm-binary-section-bytes
        (lambda (buffer)
          (cl-cc/codegen-native/targets/wasm:wasm-binary-write-name buffer "runλ")))
       :to-equalp
       #(#x05 #x72 #x75 #x6e #xce #xbb))))
  (it "returns only the unframed payload for the WAT name custom section"
    (let ((module (cl-cc/codegen-native/targets/wasm::make-empty-wasm-module)))
      (cl-cc/codegen-native/targets/wasm::wasm-module-add-function
       module
       (cl-cc/codegen-native/targets/wasm::make-wasm-function-def
        :wat-name "main"))
      (expect
       (cl-cc/codegen-native/targets/wasm::%wasm-build-name-section-bytes module)
       :to-equalp
       #(#x00 #x12 #x11 #x63 #x6c #x2d #x63 #x63 #x2d #x77
         #x61 #x73 #x6d #x2d #x6d #x6f #x64 #x75 #x6c #x65
         #x01 #x07 #x01 #x00 #x04 #x6d #x61 #x69 #x6e
         #x02 #x0c #x01 #x00 #x02 #x00 #x02 #x70 #x63
         #x01 #x03 #x74 #x6d #x70 #x03 #x03 #x01 #x00 #x00))))
  (it "encodes non-ASCII debug names as UTF-8"
    (let ((module (cl-cc/codegen-native/targets/wasm::make-empty-wasm-module)))
      (cl-cc/codegen-native/targets/wasm::wasm-module-add-function
       module
       (cl-cc/codegen-native/targets/wasm::make-wasm-function-def
        :wat-name "λ"))
      (expect
       (cl-cc/codegen-native/targets/wasm::%wasm-build-name-section-bytes module)
       :to-equalp
       #(#x00 #x12 #x11 #x63 #x6c #x2d #x63 #x63 #x2d #x77
         #x61 #x73 #x6d #x2d #x6d #x6f #x64 #x75 #x6c #x65
         #x01 #x05 #x01 #x00 #x02 #xce #xbb
         #x02 #x0c #x01 #x00 #x02 #x00 #x02 #x70 #x63
         #x01 #x03 #x74 #x6d #x70
         #x03 #x03 #x01 #x00 #x00))))
  (it "encodes non-ASCII AOT custom section names as UTF-8"
    (expect
     (cl-cc/codegen-native/targets/wasm:wasm-binary-section-bytes
      (lambda (buffer)
        (cl-cc/codegen-native/targets/wasm/infra::wasm-binary-write-custom-section
         buffer "λ" "")))
     :to-equalp
     #(#x00 #x03 #x02 #xce #xbb))))

