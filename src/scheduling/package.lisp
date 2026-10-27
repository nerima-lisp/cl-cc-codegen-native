(defpackage #:cl-cc/codegen-native/scheduling
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
   #:%native-block-terminator #:%native-common-dominator #:%native-inst-reads-phys-p #:%native-inst-touches-phys-p #:%post-ra-best-ready-node #:%post-ra-build-read-counts #:%post-ra-build-scheduler-graph #:%post-ra-canonical-phys-reg
   #:%post-ra-compute-scheduler-priorities #:%post-ra-decrement-reg-counts #:%post-ra-fixed-type-p #:%post-ra-flatten-cfg-block-order #:%post-ra-increment-reg-counts #:%post-ra-inst-read-regs #:%post-ra-inst-write-regs #:%post-ra-live-before-instruction
   #:%post-ra-live-before-instructions #:%post-ra-physical-reg-p #:%post-ra-pressure-delta #:%post-ra-reg-intersect-p #:%post-ra-resolve-reg #:%post-ra-resolve-regs #:%post-ra-schedule-basic-block #:%post-ra-schedule-run
   #:%post-ra-scheduler-barrier-p #:%post-ra-scheduler-depends-p #:%post-ra-scheduler-segments #:%post-ra-stack-memory-inst-p #:*post-ra-implicit-registers* #:*post-ra-x86-64-aliases* #:*shrink-wrap-enabled* #:codegen-hot-cold-ordered-instructions
   #:schedule-post-ra #:x86-64-macro-fusion-branch-p #:x86-64-macro-fusion-candidate-p #:x86-64-macro-fusion-compare-p #:x86-64-preserve-macro-fusion)
  (:import-from #:cl-cc/codegen-native/regalloc
   #:instruction-defs #:instruction-uses #:regalloc-assignment #:regalloc-lookup #:regalloc-result
   #:vm-spill-load #:vm-spill-store)
  (:export
   #:*shrink-wrap-enabled* #:schedule-post-ra #:x86-64-macro-fusion-branch-p #:x86-64-macro-fusion-candidate-p #:x86-64-macro-fusion-compare-p #:x86-64-preserve-macro-fusion
   #:%native-block-terminator #:%native-common-dominator #:%native-inst-reads-phys-p
   #:%native-inst-touches-phys-p #:codegen-hot-cold-ordered-instructions)
)
