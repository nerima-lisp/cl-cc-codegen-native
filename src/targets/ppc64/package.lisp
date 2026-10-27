(defpackage #:cl-cc/codegen-native/targets/ppc64
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
   #:%ppc64-branch-disp #:%ppc64-s16 #:%ppc64-spr-field #:%ppc64-u5 #:*ppc64-enabled* #:+ppc64-opcode-nop+ #:ctr #:emit-ppc64-instr
   #:encode-power10-add #:encode-power10-addi #:encode-power10-b #:encode-power10-bc #:encode-power10-bl #:encode-power10-cmp #:encode-power10-ld #:encode-power10-mflr
   #:encode-power10-mtlr #:encode-power10-std #:encode-ppc64-nop #:lr #:ppc64-backend-available-p #:ppc64-elfv2-epilogue #:ppc64-elfv2-prologue #:r0
   #:r1 #:r10 #:r11 #:r12 #:r13 #:r14 #:r15 #:r16
   #:r17 #:r18 #:r19 #:r2 #:r20 #:r21 #:r22 #:r23
   #:r24 #:r25 #:r26 #:r27 #:r28 #:r29 #:r3 #:r30
   #:r31 #:r4 #:r5 #:r6 #:r7 #:r8 #:r9)
  (:export
   #:*ppc64-enabled* #:ctr #:emit-ppc64-instr #:encode-power10-add #:encode-power10-addi #:encode-power10-b #:encode-power10-bc #:encode-power10-bl
   #:encode-power10-cmp #:encode-power10-ld #:encode-power10-mflr #:encode-power10-mtlr #:encode-power10-std #:encode-ppc64-nop #:lr #:ppc64-backend-available-p
   #:ppc64-elfv2-epilogue #:ppc64-elfv2-prologue #:r0 #:r1 #:r10 #:r11 #:r12 #:r13
   #:r14 #:r15 #:r16 #:r17 #:r18 #:r19 #:r2 #:r20
   #:r21 #:r22 #:r23 #:r24 #:r25 #:r26 #:r27 #:r28
   #:r29 #:r3 #:r30 #:r31 #:r4 #:r5 #:r6 #:r7
   #:r8 #:r9)
)
