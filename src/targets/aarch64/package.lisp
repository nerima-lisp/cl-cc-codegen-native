(defpackage #:cl-cc/codegen-native/targets/aarch64
  (:use #:cl #:cl-cc/bootstrap #:cl-cc/vm #:cl-cc/mir #:cl-cc/target #:cl-cc/optimize)
  (:import-from #:cl-cc/vm #:vm-aswap-addr #:vm-aswap-newval)
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
   #:%a64-inst-reads-pair-p #:%a64-inst-touches-pair-p #:%a64-libm-resolve #:%aarch64-emit-abi-arg #:%aarch64-emit-runtime-call #:%aarch64-emit-spill-load #:%aarch64-emit-spill-store #:%aarch64-fp-register
   #:%aarch64-register-from-pool #:%aarch64-spill-home-offset #:%aarch64-virtual-register-index #:%aarch64-vm-register-p #:*a64-emitter-table* #:*a64-instruction-sizes* #:*a64-libm-address-table* #:*a64-omit-frame-pointer*
   #:*aarch64-abi-arg-regs* #:*aarch64-atomics-enabled* #:*aarch64-cfi-enabled* #:*aarch64-pac-enabled* #:*aarch64-reg-number* #:*aarch64-register-pool* #:*aarch64-safe-stack-enabled* #:*aarch64-scratch-regs*
   #:*aarch64-shadow-call-stack-enabled* #:*aarch64-stack-clash-protection-enabled* #:*aarch64-stack-protector-enabled* #:*aarch64-sve-enabled* #:*aarch64-sve-p-regs* #:*aarch64-sve-z-regs* #:*aarch64-sve2-enabled* #:*current-a64-epilogue-save-pairs*
   #:*current-a64-literal-pool* #:*current-a64-regalloc* #:*current-a64-spill-base-reg* #:*current-a64-spill-offset-bias* #:*current-aarch64-spill-base* #:*current-aarch64-spill-home* #:*isel-aarch64-rules* #:*sme-enabled*
   #:+a64-fp+ #:+a64-literal-island-threshold+ #:+a64-lr+ #:+a64-ret+ #:+a64-safe-stack-tls-offset+ #:+a64-scs+ #:+a64-scs-tmp+ #:+a64-sp+
   #:+a64-stack-canary-tls-offset+ #:+a64-stack-probe-scratch+ #:+a64-tpidr-el0-reg+ #:+a64-za+ #:+a64-zr+ #:+aarch64-array-data-offset+ #:a64-bcond-word-p #:a64-branch-target
   #:a64-cbz-word-p #:a64-cmp-zr-word-p #:a64-codegen-target #:a64-collect-literal-pool #:a64-compute-labels-and-islands #:a64-constant-island-plan #:a64-decode-instructions #:a64-emit-constant-island
   #:a64-encode-cbz-word #:a64-finalize-literal-pool #:a64-finalize-literal-pool-islands #:a64-imm64-size #:a64-instruction-size #:a64-island-size-at #:a64-libm-address #:a64-libm-function-for-instruction
   #:a64-literal-entry #:a64-literal-entry-index #:a64-literal-offset-for-reference #:a64-literal-pool #:a64-literal-pool-value-p #:a64-mov-rd #:a64-mov-rn #:a64-mov-rr-word-p
   #:a64-page #:a64-page-offset #:a64-patch-branch-displacement #:a64-peephole-rewrite #:a64-phys-num->keyword #:a64-pool-add #:a64-pool-align-offset #:a64-pool-emit
   #:a64-pool-entry-for-value #:a64-program-instruction-bytes #:a64-read-u32 #:a64-reg #:a64-safe-stack-epilogue-size #:a64-safe-stack-pointer-size #:a64-safe-stack-prologue-size #:a64-shrink-restore
   #:a64-shrink-save #:a64-shrink-wrap-instructions #:a64-sign-extend #:a64-spill-slot-offset #:a64-stack-frame-size #:a64-used-callee-saved-pairs #:a64-validate-simd-vector-op #:a64-write-u32
   #:aarch64-atomic-lowering-plan #:aarch64-cfi-plan #:aarch64-emit-literal-pool #:aarch64-emit-literal-reference #:aarch64-peephole-optimize #:aarch64-supports-sme-p #:aarch64-target #:aarch64-tls-base-register
   #:build-a64-label-offsets #:compile-to-aarch64-bytes #:defenc #:define-a64-binary-emitter #:define-a64-boolean-pred-emit-method #:define-a64-checked-add-sub-emit-method #:define-a64-cmp-emitter #:define-a64-csel-emitter
   #:define-a64-float-binary-emitter #:define-a64-float-libm-unary-emitter #:define-a64-unary-emitter #:define-aarch64-float-emit-method #:emit-a64-atomic-cas #:emit-a64-atomic-fetch-add #:emit-a64-atomic-load #:emit-a64-atomic-store
   #:emit-a64-atomic-swap #:emit-a64-boolean-result #:emit-a64-dmb-for-order #:emit-a64-epilogue #:emit-a64-instr #:emit-a64-instruction #:emit-a64-memory-barrier #:emit-a64-mov-imm64
   #:emit-a64-program #:emit-a64-prologue #:emit-a64-safe-stack-load-pointer #:emit-a64-safe-stack-store-pointer #:emit-a64-shrink-pseudo #:emit-a64-simd-address #:emit-a64-stack-allocate #:emit-a64-stack-canary-epilogue
   #:emit-a64-stack-canary-prologue #:emit-a64-stack-deallocate #:emit-a64-stack-probes #:emit-a64-vm-add #:emit-a64-vm-add-checked #:emit-a64-vm-bswap #:emit-a64-vm-const #:emit-a64-vm-const-at
   #:emit-a64-vm-eq #:emit-a64-vm-false-pred #:emit-a64-vm-float-add #:emit-a64-vm-float-div #:emit-a64-vm-float-mul #:emit-a64-vm-float-sub #:emit-a64-vm-fma #:emit-a64-vm-halt
   #:emit-a64-vm-integer-mul-high-s #:emit-a64-vm-integer-mul-high-u #:emit-a64-vm-jump #:emit-a64-vm-jump-zero #:emit-a64-vm-lt #:emit-a64-vm-max #:emit-a64-vm-min #:emit-a64-vm-move
   #:emit-a64-vm-mul #:emit-a64-vm-mul-checked #:emit-a64-vm-null-p #:emit-a64-vm-prefetch #:emit-a64-vm-ret #:emit-a64-vm-rotate #:emit-a64-vm-select #:emit-a64-vm-simd-vector-op
   #:emit-a64-vm-spill-load #:emit-a64-vm-spill-store #:emit-a64-vm-sqrt #:emit-a64-vm-sub #:emit-a64-vm-sub-checked #:emit-a64-vm-true-pred #:emit-a64-vm-truncate #:emit-aarch64-bti-j-entry
   #:emit-aarch64-cfi-entry #:encode-a64-casal #:encode-a64-cbnz #:encode-a64-dmb-ish #:encode-a64-ldxr #:encode-a64-stxr #:encode-adr #:encode-adrp
   #:encode-autiasp #:encode-bti-c #:encode-bti-j #:encode-fmopa #:encode-ldr-literal #:encode-ldr-unsigned64 #:encode-mrs-tpidr-el0 #:encode-msr-tpidr-el0
   #:encode-neon-fadd2d #:encode-neon-fmul2d #:encode-neon-fsub2d #:encode-paciasp #:encode-rdvl #:encode-smstart #:encode-smstop #:encode-sve-add-z
   #:encode-sve2-eor-z #:encode-whilelt-d #:make-a64-shrink-restore #:make-a64-shrink-save)
  (:shadowing-import-from #:cl-cc/codegen-native/lowering
   #:emit-instruction #:target #:target-register)
  (:import-from #:cl-cc/codegen-native/lowering
   #:*current-calling-convention* #:apply-calling-convention-to-target #:calling-convention #:codegen-memory-order #:define-isel-rules #:native-emit-optimized-insts #:native-rewrite-inst
   #:native-safe-identical-dedup-p #:peephole-byte-list-vector #:peephole-copy-byte-vector #:stack-probe-count #:vm-atomic-memory-order* #:vm-const-to-integer
   #:vm-program-calling-convention-object #:with-output-to-vector
   #:calling-convention-omit-frame-pointer-p #:native-peephole-inst #:make-native-peephole-inst
   #:native-peephole-inst-bytes #:native-peephole-inst-branch-size #:native-peephole-inst-end
   #:native-peephole-inst-target #:native-peephole-inst-dst #:native-peephole-inst-kind
   #:native-peephole-inst-src)
  (:import-from #:cl-cc/codegen-native/regalloc
   #:allocate-registers #:regalloc-assignment #:regalloc-instructions #:regalloc-spill-count
   #:vm-spill-dst #:vm-spill-load #:vm-spill-slot #:vm-spill-src #:vm-spill-store)
  (:import-from #:cl-cc/codegen-native/scheduling
   #:%native-block-terminator #:%native-common-dominator #:%native-inst-reads-phys-p #:%native-inst-touches-phys-p #:*shrink-wrap-enabled* #:schedule-post-ra)
  (:export #:*aarch64-atomics-enabled* #:*aarch64-cfi-enabled* #:*aarch64-pac-enabled* #:*aarch64-safe-stack-enabled* #:*aarch64-shadow-call-stack-enabled* #:*aarch64-stack-clash-protection-enabled* #:*aarch64-stack-protector-enabled* #:*aarch64-sve-enabled*
   #:*aarch64-sve2-enabled* #:*isel-aarch64-rules* #:*sme-enabled* #:+a64-za+ #:aarch64-supports-sme-p #:aarch64-target #:compile-to-aarch64-bytes #:encode-fmopa
   #:encode-smstart #:encode-smstop #:*a64-omit-frame-pointer*)
)
