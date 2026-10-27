(defpackage #:cl-cc/codegen-native/emit/ebpf
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
   #:%align-up #:%append-bytes #:%byte-vector #:%bytes-of-string #:%ebpf-check-register #:%ebpf-emit-insn #:%ebpf-emit-ld-map-fd #:%ebpf-helper-id
   #:%ebpf-instruction-heap-op-p #:%ebpf-lower-inst #:%ebpf-map-def-bytes #:%ebpf-program-exits-p #:%ebpf-section-name #:%ebpf-valid-register-p #:%emit-cstr #:%emit-elf64-section-header
   #:%emit-elf64-symbol #:%emit-le #:%section-name-offsets #:%string-table #:%u16 #:%u32 #:%u8 #:+bpf-helper-map-lookup-elem+
   #:+bpf-helper-map-update-elem+ #:+bpf-map-type-array+ #:+bpf-map-type-hash+ #:+ebpf-instruction-size+ #:+ebpf-max-verifier-instructions+ #:+ebpf-op-add64-imm+ #:+ebpf-op-add64-reg+ #:+ebpf-op-call+
   #:+ebpf-op-exit+ #:+ebpf-op-ld-map-fd+ #:+ebpf-op-mov64-imm+ #:+ebpf-op-mov64-reg+ #:+ebpf-pseudo-map-fd+ #:+ebpf-target-flag+ #:compile-ebpf-program #:ebpf-map-def
   #:ebpf-map-def-fd #:ebpf-map-def-flags #:ebpf-map-def-key-size #:ebpf-map-def-max-entries #:ebpf-map-def-name #:ebpf-map-def-type #:ebpf-map-def-value-size #:ebpf-program-plan
   #:ebpf-program-plan-hook-point #:ebpf-program-plan-instructions #:ebpf-program-plan-maps #:ebpf-program-plan-program-name #:ebpf-program-plan-uses-helpers-p #:ebpf-program-plan-verifier-safe-p #:ebpf-target-flag-p #:emit-ebpf-bytecode
   #:emit-ebpf-elf-object #:make-ebpf-map-def #:make-ebpf-program-plan #:plan-ebpf-program #:validate-ebpf-verifier-constraints)
  (:export
   #:+bpf-helper-map-lookup-elem+ #:+bpf-helper-map-update-elem+ #:+bpf-map-type-array+ #:+bpf-map-type-hash+ #:+ebpf-target-flag+ #:compile-ebpf-program #:ebpf-map-def #:ebpf-map-def-fd
   #:ebpf-map-def-flags #:ebpf-map-def-key-size #:ebpf-map-def-max-entries #:ebpf-map-def-name #:ebpf-map-def-type #:ebpf-map-def-value-size #:ebpf-program-plan #:ebpf-program-plan-hook-point
   #:ebpf-program-plan-instructions #:ebpf-program-plan-maps #:ebpf-program-plan-program-name #:ebpf-program-plan-uses-helpers-p #:ebpf-program-plan-verifier-safe-p #:ebpf-target-flag-p #:emit-ebpf-bytecode #:emit-ebpf-elf-object
   #:make-ebpf-map-def #:make-ebpf-program-plan #:plan-ebpf-program #:validate-ebpf-verifier-constraints)
)
