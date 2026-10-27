(defpackage #:cl-cc/codegen-native/emit/mlir
  (:use #:cl #:cl-cc/bootstrap #:cl-cc/vm #:cl-cc/mir #:cl-cc/target #:cl-cc/optimize)
  (:shadowing-import-from #:cl-cc/vm
   #:*command-line-args* #:*compile-file-pathname* #:*compile-file-truename* #:*compile-print* #:*compile-verbose* #:*default-external-format* #:*features* #:*load-pathname*
   #:*load-print* #:*load-truename* #:*load-verbose* #:*modules* #:*print-array* #:*print-base* #:*print-case* #:*print-circle*
   #:*print-escape* #:*print-gensym* #:*print-length* #:*print-level* #:*print-lines* #:*print-pprint-dispatch* #:*print-pretty* #:*print-radix*
   #:*print-readably* #:*print-right-margin* #:*random-state* #:*read-base* #:*read-default-float-format* #:*read-eval* #:*read-suppress* #:*readtable*
   #:*trace-output* #:add-method #:apropos #:apropos-list #:break #:compute-applicable-methods #:copy-pprint-dispatch #:copy-readtable
   #:decode-universal-time #:describe #:dribble #:ed #:elt #:encode-universal-time #:ensure-generic-function #:exit
   #:find-method #:get-dispatch-macro-character #:get-internal-real-time #:get-internal-run-time #:get-macro-character #:get-pprint-dispatch #:get-universal-time #:getenv
   #:inspect #:internal-time-units-per-second #:invoke-debugger #:length #:lisp-implementation-type #:lisp-implementation-version #:machine-instance #:machine-type
   #:machine-version #:make-random-state #:method-qualifiers #:open #:pprint-indent #:pprint-logical-block #:pprint-newline #:pprint-tab
   #:random #:random-state #:random-state-p #:read-delimited-list #:read-preserving-whitespace #:readtable-case #:remove-method #:room
   #:sequence #:set-dispatch-macro-character #:set-macro-character #:set-pprint-dispatch #:set-syntax-from-char #:setenv #:sleep #:software-type
   #:software-version #:step #:stream-external-format #:subseq #:time #:trace #:untrace #:vm-simd-vector-op-p
   #:with-standard-io-syntax)
  (:shadow
   #:%mir-inst->clcc-op #:%mlir-block-label-name #:%mlir-block-ref #:%mlir-block-terminated-p #:%mlir-call-target-name #:%mlir-const-type #:%mlir-const-value #:%mlir-downcase-name
   #:%mlir-emit-block #:%mlir-emit-bool-coercion #:%mlir-emit-constant #:%mlir-emit-declarations #:%mlir-emit-function #:%mlir-identifier-char-p #:%mlir-infer-function-return-type #:%mlir-lower-clcc-op
   #:%mlir-module-functions #:%mlir-next-temp #:%mlir-operand #:%mlir-operand-type #:%mlir-register-declaration #:%mlir-register-params #:%mlir-result-type-list #:%mlir-sanitize-name
   #:%mlir-symbol-name #:%mlir-type #:%mlir-value-name #:%mlir-value-type #:%mlir-zero-value #:*mlir-type-names* #:clcc-op #:emit-mlir
   #:make-mlir-module #:mlir-bridge-capabilities #:mlir-lower-context #:mlir-module #:mlir-module-body #:mlir-module-dialect #:mlir-module-metadata #:mlir-module-name
   #:vm-program->mlir-module)
  (:export
   #:emit-mlir #:make-mlir-module #:mlir-bridge-capabilities #:mlir-module #:mlir-module-body #:mlir-module-dialect #:mlir-module-metadata #:mlir-module-name
   #:vm-program->mlir-module)
)
