(defpackage #:cl-cc/codegen-native/lowering
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
   #:%burs-pattern-frontier #:%cg-bitmask-for-indexes #:%cg-mir-register-root-p #:%cg-mir-stack-root-p #:%cg-plist-value #:%cg-register-index #:%cg-root-keyword-p #:%cg-root-type-p
   #:%const-mir-type #:%emit-pass-through-mir #:%emit-selected-vm-inst #:%isel-best-rule #:%isel-better-rule-p #:%isel-bind-pattern #:%isel-rule-match #:%isel-tree-children
   #:%isel-tree-op #:%isel-variable-pattern-p #:%lower-phis-to-vm-moves #:%lower-vm-inst-to-mir #:%make-burs-terminal-rule #:%mir-constant-fold-value #:%mir-dst-name #:%mir-inst-tree
   #:%mir-meta-get #:%mir-operand-tree #:%operand-constant-value #:%vm-label-name-string #:%vm-reg-value #:*%vm-arith-class->mir-op* #:*burs-rules* #:*current-calling-convention*
   #:*external-calling-convention* #:*internal-calling-convention* #:*isel-rule-table* #:*precise-gc-stack-maps-enabled* #:+burs-terminal-cost+ #:+stack-probe-page-size+ #:apply-calling-convention-to-target #:burs-rule
   #:burs-rule-cost #:burs-rule-pattern #:burs-rule-replacement #:burs-select-instructions #:calling-convention #:calling-convention-arg-regs #:calling-convention-callee-saved #:calling-convention-for-name
   #:calling-convention-internal-p #:calling-convention-name #:calling-convention-omit-frame-pointer-p #:calling-convention-target-value #:cg-embed-stack-maps-after-safepoints #:cg-generate-safepoint-stack-map #:cg-safepoint-instruction-p #:cg-sm-frame-size
   #:cg-sm-pc-offset #:cg-sm-register-bitmask #:cg-sm-register-roots #:cg-sm-safepoint-id #:cg-sm-stack-bitmask #:cg-sm-stack-slot-roots #:cg-sme-index #:cg-sme-kind
   #:cg-sme-location #:cg-stack-map #:cg-stack-map->section-record #:cg-stack-map-entry #:cg-stack-map-entry-p #:cg-stack-map-p #:codegen-memory-order #:compile-file-to-native
   #:compile-to-native #:define-isel-rules #:emit-instruction #:isel-diagnostic #:isel-diagnostic-message #:isel-maximal-munch #:isel-rule #:isel-rule-cost
   #:isel-rule-emitter #:isel-rule-name #:isel-rule-pattern #:isel-rule-result-op #:isel-rule-size #:isel-rule-target #:isel-rules-for-target #:isel-vm-program
   #:make-burs-rule #:make-cg-stack-map #:make-cg-stack-map-entry #:make-isel-rule #:make-native-peephole-inst #:mir-module->vm-program #:native-build-offset-map #:native-emit-optimized-insts
   #:native-peephole-inst #:native-peephole-inst-dst #:native-peephole-inst-kind #:native-peephole-inst-src #:native-rewrite-inst #:native-safe-identical-dedup-p #:optimize-mir-module-for-isel #:peephole-byte-list-vector
   #:peephole-copy-byte-vector #:register-burs-rule #:register-isel-rule #:stack-probe-count #:target #:target-regalloc #:target-register #:target-spill-base-reg
   #:vm-atomic-memory-order* #:vm-const-to-integer #:vm-program->mir-module #:vm-program-calling-convention-object #:with-output-to-vector)
  (:export
   #:*burs-rules* #:*external-calling-convention* #:*internal-calling-convention* #:*precise-gc-stack-maps-enabled* #:burs-rule #:burs-select-instructions #:calling-convention #:calling-convention-arg-regs
   #:calling-convention-callee-saved #:calling-convention-name #:calling-convention-omit-frame-pointer-p #:cg-embed-stack-maps-after-safepoints #:cg-generate-safepoint-stack-map #:cg-safepoint-instruction-p #:cg-sm-frame-size #:cg-sm-pc-offset
   #:cg-sm-register-bitmask #:cg-sm-register-roots #:cg-sm-safepoint-id #:cg-sm-stack-bitmask #:cg-sm-stack-slot-roots #:cg-sme-index #:cg-sme-kind #:cg-sme-location
   #:cg-stack-map #:cg-stack-map->section-record #:cg-stack-map-entry #:cg-stack-map-entry-p #:cg-stack-map-p #:compile-file-to-native #:compile-to-native #:emit-instruction
   #:isel-diagnostic #:isel-diagnostic-message #:isel-maximal-munch #:isel-rule #:isel-rule-cost #:isel-rule-emitter #:isel-rule-name #:isel-rule-pattern
   #:isel-rule-result-op #:isel-rule-size #:isel-rule-target #:isel-rules-for-target #:isel-vm-program #:make-burs-rule #:make-cg-stack-map #:make-cg-stack-map-entry
   #:mir-module->vm-program #:optimize-mir-module-for-isel #:register-burs-rule #:register-isel-rule #:target-regalloc #:target-spill-base-reg #:vm-program->mir-module
   #:*current-calling-convention* #:+stack-probe-page-size+ #:apply-calling-convention-to-target
   #:codegen-memory-order #:define-isel-rules #:make-native-peephole-inst #:native-emit-optimized-insts
   #:native-peephole-inst #:native-peephole-inst-bytes #:native-peephole-inst-branch-size
   #:native-peephole-inst-dst #:native-peephole-inst-end #:native-peephole-inst-kind
   #:native-peephole-inst-src #:native-peephole-inst-target #:native-rewrite-inst
   #:native-safe-identical-dedup-p #:peephole-byte-list-vector #:peephole-copy-byte-vector
   #:stack-probe-count #:target #:target-register #:vm-atomic-memory-order* #:vm-const-to-integer
   #:vm-program-calling-convention-object #:with-output-to-vector)
)
