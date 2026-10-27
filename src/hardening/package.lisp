(defpackage #:cl-cc/codegen-native/hardening
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
   #:*win-cfg-enabled* #:*win-cfg-function-table* #:win-cfg-enabled-p #:win-cfg-function-registered-p #:win-cfg-function-table-entries #:win-cfg-guard-check-icall-symbol #:win-cfg-guard-dispatch-icall-symbol #:win-cfg-guard-fids-table-metadata
   #:win-cfg-invalid-target #:win-cfg-register-function #:win-cfg-unregister-function #:_guard_check_icall #:_guard_dispatch_icall)
  (:export
   #:*win-cfg-enabled* #:*win-cfg-function-table* #:win-cfg-enabled-p #:win-cfg-function-registered-p #:win-cfg-function-table-entries #:win-cfg-guard-check-icall-symbol #:win-cfg-guard-dispatch-icall-symbol #:win-cfg-guard-fids-table-metadata
   #:win-cfg-invalid-target #:win-cfg-register-function #:win-cfg-unregister-function #:_guard_check_icall #:_guard_dispatch_icall)
)
