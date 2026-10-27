(defpackage #:cl-cc/codegen-native/emit/llvm
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
   #:%llvm-block-label-name #:%llvm-block-ref #:%llvm-block-terminated-p #:%llvm-call-target-name #:%llvm-const-type #:%llvm-const-value #:%llvm-downcase-name #:%llvm-emit-binary
   #:%llvm-emit-block #:%llvm-emit-bool-coercion #:%llvm-emit-call #:%llvm-emit-compare #:%llvm-emit-const #:%llvm-emit-declarations #:%llvm-emit-function #:%llvm-emit-gep-if-needed
   #:%llvm-emit-inst #:%llvm-emit-move #:%llvm-emit-phi #:%llvm-global-name #:%llvm-identifier-char-p #:%llvm-infer-function-return-type #:%llvm-module-functions #:%llvm-next-temp
   #:%llvm-operand #:%llvm-operand-type #:%llvm-register-declaration #:%llvm-sanitize-name #:%llvm-string-prefix-p #:%llvm-type #:%llvm-value-name #:%llvm-value-type
   #:%llvm-zero-value #:*llvm-type-names* #:+llvm-ir-default-data-layout+ #:+llvm-ir-default-target-triple+ #:emit-llvm-ir #:llvm-ir-bridge-capabilities #:llvm-ir-module #:llvm-ir-module-body
   #:llvm-ir-module-data-layout #:llvm-ir-module-metadata #:llvm-ir-module-name #:llvm-ir-module-target-triple #:llvm-lower-context #:llvmctx-declarations #:llvmctx-temp-counter #:make-llvm-ir-module
   #:make-llvm-lower-context #:vm-program->llvm-ir-module)
  (:export
   #:emit-llvm-ir #:llvm-ir-bridge-capabilities #:llvm-ir-module #:llvm-ir-module-body #:llvm-ir-module-data-layout #:llvm-ir-module-metadata #:llvm-ir-module-name #:llvm-ir-module-target-triple
   #:make-llvm-ir-module #:vm-program->llvm-ir-module)
)
