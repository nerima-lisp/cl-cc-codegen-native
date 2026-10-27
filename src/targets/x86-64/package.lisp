(defpackage #:cl-cc/codegen-native/targets/x86-64
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
   #:%bignum-bridge-address #:%emit-modrm-address #:%emit-modrm-indexed-address #:%emit-modrm-rip-relative #:%emit-shr-ri8 #:%emit-ubsan-trap-if-zero #:%libm-function-address #:%native-shrink-wrap-plan
   #:%native-unsafe-restore-before-terminator-p #:%native-weave-shrink-wrap-pseudos #:%runtime-function-address #:%sanitizer-memory-access-p #:%sanitizer-overflow-op-p #:%x86-64-align-up #:%x86-64-amx-check-tmm #:%x86-64-array-data-ref
   #:%x86-64-emit-abi-arg #:%x86-64-emit-runtime-call #:%x86-64-normalize-frame-local #:%x86-64-vm-register-p #:*amx-enabled* #:*current-float-vregs* #:*current-regalloc* #:*current-spill-base-reg*
   #:*current-spill-offset-bias* #:*eh-model* #:*fallback-fp-register-pool* #:*fallback-register-pool* #:*isel-x86-64-rules* #:*phys-fp-reg-to-asm-string* #:*phys-fp-reg-to-x86-code* #:*phys-reg-to-asm-string*
   #:*phys-reg-to-x86-code* #:*phys-vector-reg-to-x86-code* #:*sib-scale-table* #:*vm-fp-reg-map* #:*vm-reg-map* #:*x86-64-abi-arg-regs* #:*x86-64-apx-enabled* #:*x86-64-atomics-enabled*
   #:*x86-64-avx512-enabled* #:*x86-64-bignum-calls-enabled* #:*x86-64-branch-encodings* #:*x86-64-cfi-enabled* #:*x86-64-emitter-entries* #:*x86-64-emitter-table* #:*x86-64-host-probe-timeout-seconds* #:*x86-64-instruction-size-specs*
   #:*x86-64-instruction-sizes* #:*x86-64-omit-frame-pointer* #:*x86-64-personality-descriptor* #:*x86-64-safe-stack-enabled* #:*x86-64-shadow-stack-enabled* #:*x86-64-spectre-mitigations-enabled* #:*x86-64-stack-clash-protection-enabled* #:*x86-64-stack-protector-enabled*
   #:*x86-64-use-retpoline* #:*zero-cost-eh-enabled* #:+clcc-exception-class+ #:+evex-map-0f+ #:+evex-map-0f38+ #:+evex-map-0f3a+ #:+k0+ #:+k1+
   #:+k2+ #:+k3+ #:+k4+ #:+k5+ #:+k6+ #:+k7+ #:+r10+ #:+r11+
   #:+r12+ #:+r13+ #:+r14+ #:+r15+ #:+r16+ #:+r17+ #:+r18+ #:+r19+
   #:+r20+ #:+r21+ #:+r22+ #:+r23+ #:+r24+ #:+r25+ #:+r26+ #:+r27+
   #:+r28+ #:+r29+ #:+r30+ #:+r31+ #:+r8+ #:+r9+ #:+rax+ #:+rbp+
   #:+rbx+ #:+rcx+ #:+rdi+ #:+rdx+ #:+rsi+ #:+rsp+ #:+tmm0+ #:+tmm1+
   #:+tmm2+ #:+tmm3+ #:+tmm4+ #:+tmm5+ #:+tmm6+ #:+tmm7+ #:+vex-map-0f+ #:+vex-map-0f38+
   #:+vex-pp-66+ #:+vex-pp-f2+ #:+vex-pp-f3+ #:+vex-pp-none+ #:+x86-64-array-data-offset+ #:+x86-64-landing-pad-size+ #:+x86-64-landing-pad-stub-size+ #:+x86-64-safe-stack-tls-disp32+
   #:+x86-64-stack-probe-size+ #:+x86-64-tls-canary-disp32+ #:+xmm0+ #:+xmm1+ #:+xmm10+ #:+xmm11+ #:+xmm12+ #:+xmm13+
   #:+xmm14+ #:+xmm15+ #:+xmm2+ #:+xmm3+ #:+xmm4+ #:+xmm5+ #:+xmm6+ #:+xmm7+
   #:+xmm8+ #:+xmm9+ #:+ymm0+ #:+ymm1+ #:+ymm10+ #:+ymm11+ #:+ymm12+ #:+ymm13+
   #:+ymm14+ #:+ymm15+ #:+ymm2+ #:+ymm3+ #:+ymm4+ #:+ymm5+ #:+ymm6+ #:+ymm7+
   #:+ymm8+ #:+ymm9+ #:+zmm0+ #:+zmm1+ #:+zmm10+ #:+zmm11+ #:+zmm12+ #:+zmm13+
   #:+zmm14+ #:+zmm15+ #:+zmm16+ #:+zmm17+ #:+zmm18+ #:+zmm19+ #:+zmm2+ #:+zmm20+
   #:+zmm21+ #:+zmm22+ #:+zmm23+ #:+zmm24+ #:+zmm25+ #:+zmm26+ #:+zmm27+ #:+zmm28+
   #:+zmm29+ #:+zmm3+ #:+zmm30+ #:+zmm31+ #:+zmm4+ #:+zmm5+ #:+zmm6+ #:+zmm7+
   #:+zmm8+ #:+zmm9+ #:+_ua-cleanup-phase+ #:+_ua-force-unwind+ #:+_ua-handler-frame+ #:+_ua-search-phase+ #:+_urc-continue-unwind+ #:+_urc-end-of-stack+
   #:+_urc-fatal-phase1-error+ #:+_urc-fatal-phase2-error+ #:+_urc-foreign-exception-caught+ #:+_urc-handler-found+ #:+_urc-install-context+ #:+_urc-no-reason+ #:+_urc-normal-stop+ #:build-label-offsets
   #:compile-to-x86-64-bytes #:define-alu-ri32 #:define-alu-rr64 #:define-bignum-aware-wrapper #:define-bignum-bridge-emitter #:define-binary-alu-emitter #:define-checked-binary-alu-emitter #:define-cmov-emitter
   #:define-cmp-emitter #:define-f7-unary-rm64 #:define-float-binary-emitter #:define-float-libm-unary-emitter #:define-float-unary-emitter #:define-r11-result-binop-emitter #:define-sd-xx-op #:define-short-circuit-logical-emitter
   #:define-ss-xx-op #:define-sse66-0f-xmm-op #:define-sse66-0f38-xmm-op #:define-unary-mov-emitter #:emit-add-ri32 #:emit-add-ri8 #:emit-add-rr64 #:emit-and-ri8
   #:emit-apx-add-ndd-rrr64 #:emit-apx-imul-ndd-rrr64 #:emit-apx-sub-ndd-rrr64 #:emit-avx2-vex-yym #:emit-avx2-vex-yyy #:emit-avx512-evex-zzz #:emit-bextr-rrr64 #:emit-branch-relaxed
   #:emit-branch-short #:emit-bsr-rr64 #:emit-bswap-r32 #:emit-byte #:emit-call-r64 #:emit-cdq #:emit-cmovg-rr64 #:emit-cmovl-rr64
   #:emit-cmovne-rr64 #:emit-cmp-ri32 #:emit-cmp-ri64 #:emit-cmp-rm64-fs-disp32 #:emit-cmp-rr64 #:emit-cqo #:emit-dec-r64 #:emit-div-rm64
   #:emit-dword #:emit-evex-prefix #:emit-idiv-r11 #:emit-idiv-rm64 #:emit-idiv-sequence #:emit-imul-rm64 #:emit-imul-rr64 #:emit-je-rel32
   #:emit-je-short #:emit-jge-rel8 #:emit-jge-short #:emit-jmp-r64 #:emit-jmp-rel32 #:emit-jmp-rel8 #:emit-jne-rel8 #:emit-jno-rel32
   #:emit-jns-rel8 #:emit-jo-rel32 #:emit-lea #:emit-lea-indexed #:emit-lea-rip-relative #:emit-lea-rr64 #:emit-lea-rr64-offset #:emit-leave
   #:emit-lzcnt-rr64 #:emit-mov-m64-imm32 #:emit-mov-mr64 #:emit-mov-mr64-indexed #:emit-mov-mr64-rip #:emit-mov-ri64 #:emit-mov-rm64 #:emit-mov-rm64-fs-disp32
   #:emit-mov-rm64-indexed #:emit-mov-rm64-rip #:emit-mov-rr64 #:emit-movdqa-mx #:emit-movdqa-xm #:emit-movdqa-xx #:emit-movdqu-mx #:emit-movdqu-xm
   #:emit-movq-xmm-r64 #:emit-movsd-mx #:emit-movsd-xm #:emit-movzx-r64-r8 #:emit-mul-high-sequence #:emit-mul-rm64 #:emit-neg-r64 #:emit-not-r64
   #:emit-or-mem-rsp-disp32-imm8 #:emit-paddd-xx #:emit-pdep-rrr64 #:emit-pext-rrr64 #:emit-pmulld-xm #:emit-pmulld-xx #:emit-pop-r64 #:emit-popcnt-rr64
   #:emit-prefetch-mem #:emit-prefetch-mem-indexed #:emit-push-r64 #:emit-pxor-xx #:emit-qword #:emit-ret #:emit-ror-r64-cl #:emit-sal-r64-cl
   #:emit-sanitized-vm-instruction-with-labels #:emit-sar-r64-cl #:emit-setcc #:emit-sse-prefix-rex-if-needed #:emit-sse66-0f-mx #:emit-sse66-0f-xm #:emit-sse66-0f-xx #:emit-sse66-0f38-xm
   #:emit-sse66-0f38-xx #:emit-ssef3-0f-mx #:emit-ssef3-0f-xm #:emit-sub-ri32 #:emit-sub-ri8 #:emit-sub-rr64 #:emit-tdpbssd #:emit-test-rr64
   #:emit-tileloadd #:emit-tilestored #:emit-vex-0f38-rvm64 #:emit-vex-prefix #:emit-vfmadd132sd-xxx #:emit-vfmadd132ss-xxx #:emit-vm-abs #:emit-vm-add
   #:emit-vm-add-bignum #:emit-vm-add-checked #:emit-vm-and #:emit-vm-aref #:emit-vm-array-bounds-check-if-needed #:emit-vm-aset #:emit-vm-ash #:emit-vm-bswap
   #:emit-vm-call-like-inst #:emit-vm-const #:emit-vm-dec #:emit-vm-div #:emit-vm-eq #:emit-vm-false-pred #:emit-vm-float-add #:emit-vm-float-div
   #:emit-vm-float-mul #:emit-vm-float-sub #:emit-vm-fma #:emit-vm-func-ref-inst #:emit-vm-ge #:emit-vm-get-global #:emit-vm-gt #:emit-vm-halt-inst
   #:emit-vm-inc #:emit-vm-instruction-with-labels #:emit-vm-integer-add #:emit-vm-integer-length #:emit-vm-integer-mul-high-s #:emit-vm-integer-mul-high-u #:emit-vm-jump-inst #:emit-vm-jump-zero-inst
   #:emit-vm-le #:emit-vm-logbitp #:emit-vm-logcount #:emit-vm-logeqv #:emit-vm-lognot #:emit-vm-logtest #:emit-vm-lt #:emit-vm-max
   #:emit-vm-min #:emit-vm-mod #:emit-vm-move #:emit-vm-mul-checked #:emit-vm-mv-bind-regs #:emit-vm-native-noop-inst #:emit-vm-neg #:emit-vm-not
   #:emit-vm-null-p #:emit-vm-num-eq #:emit-vm-or #:emit-vm-prefetch #:emit-vm-print #:emit-vm-program #:emit-vm-rem #:emit-vm-ret-inst
   #:emit-vm-rotate #:emit-vm-select #:emit-vm-shadow-stack-control-inst #:emit-vm-simd-vector-op #:emit-vm-sin #:emit-vm-spill-load-inst #:emit-vm-spill-store-inst #:emit-vm-sqrt
   #:emit-vm-sub-checked #:emit-vm-tail-call-inst #:emit-vm-true-pred #:emit-vm-truncate #:emit-vm-values-regs #:emit-vmovdqu-my #:emit-vmovdqu-ym #:emit-vmovdqu64-zmm-load
   #:emit-vmovdqu64-zmm-store #:emit-vpaddb-zmm #:emit-vpaddd-yym #:emit-vpaddd-yyy #:emit-vpaddd-zmm #:emit-vpaddw-zmm #:emit-vpand-yyy #:emit-vpbroadcastd-zmm-r32
   #:emit-vpermd-yym #:emit-vpermd-yyy #:emit-vpmulld-yym #:emit-vpmulld-yyy #:emit-vpor-yyy #:emit-vpsubd-yyy #:emit-vpxor-yyy #:emit-vpxord-zmm
   #:emit-x86-64-address-rex-if-needed #:emit-x86-64-atomic-cas #:emit-x86-64-atomic-fetch-add #:emit-x86-64-atomic-load #:emit-x86-64-atomic-store #:emit-x86-64-atomic-swap #:emit-x86-64-bextr-field-inst #:emit-x86-64-cfi-entry
   #:emit-x86-64-cfi-indirect-target-guard #:emit-x86-64-fence-for-order #:emit-x86-64-function-epilogue #:emit-x86-64-function-prologue #:emit-x86-64-landing-pad-stub #:emit-x86-64-landing-pads #:emit-x86-64-lea-address-inst #:emit-x86-64-lfence
   #:emit-x86-64-lock-cmpxchg-m64-r64 #:emit-x86-64-lock-xadd-m64-r64 #:emit-x86-64-memory-barrier #:emit-x86-64-mfence #:emit-x86-64-personality-function #:emit-x86-64-safe-stack-load-pointer #:emit-x86-64-safe-stack-store-pointer #:emit-x86-64-sfence
   #:emit-x86-64-shrink-pseudo #:emit-x86-64-simd-address #:emit-x86-64-speculation-barrier #:emit-x86-64-stack-canary-epilogue #:emit-x86-64-stack-canary-prologue #:emit-x86-64-stack-probes #:emit-x86-64-unlikely-branch-prefix #:emit-x86-64-xchg-m64-r64
   #:encode-sib #:fits-in-rel8-p #:instruction-size #:make-x86-64-landing-pad #:modrm #:normalize-x86-64-eh-model #:pop-r64-byte-size #:populate-size-table
   #:push-r64-byte-size #:rex-prefix #:sanitize-integer-overflow-after-op #:sanitize-memory-access-before-load-store #:sanitize-null-pointer-before-access #:sanitizer-instrumentation-size #:scale->sib-bits #:sib
   #:target-fp-register #:vm-reg-to-x86 #:vm-reg-to-x86-with-alloc #:vm-reg-to-xmm #:vm-reg-to-ymm #:win-cfg-emit-guard-check-icall-thunk #:win-cfg-emit-guard-dispatch-icall-thunk #:x86-64-align-up
   #:x86-64-array-element-scale #:x86-64-atomic-fence-byte-size #:x86-64-atomic-lowering-plan #:x86-64-atomic-op-byte-size #:x86-64-bce-eliminable-inst-p #:x86-64-bextr-field #:x86-64-branch-byte-size #:x86-64-branch-displacement
   #:x86-64-branch-encoding #:x86-64-branch-target-offset #:x86-64-build-landing-pad-table #:x86-64-cfi-plan #:x86-64-codegen-target #:x86-64-commutative-add-with-reg-p #:x86-64-compute-float-vregs #:x86-64-conditional-branch-size
   #:x86-64-contiguous-low-mask-width #:x86-64-count-register-uses #:x86-64-cpu-token-present-p #:x86-64-double-float-bits #:x86-64-dynamic-instruction-size #:x86-64-eh-condition-matches-p #:x86-64-eh-dispatch #:x86-64-eh-site-handler-label
   #:x86-64-eh-site-handler-type #:x86-64-eh-site-instruction-p #:x86-64-eh-site-kind #:x86-64-eh-site-result-register #:x86-64-env-true-p #:x86-64-find-landing-pad #:x86-64-float-vreg-p #:x86-64-host-cpu-feature-text
   #:x86-64-host-supports-cpu-feature-p #:x86-64-host-supports-ibrs-p #:x86-64-host-x86-p #:x86-64-ibrs-token-present-p #:x86-64-landing-pad #:x86-64-landing-pad-table->dwarf-fdes #:x86-64-lea-address #:x86-64-lea-address-byte-size
   #:x86-64-lea-internal #:x86-64-lea-scale-p #:x86-64-lea-valid-index-p #:x86-64-lsda-bytes #:x86-64-match-bextr-pattern #:x86-64-match-lea-pattern #:x86-64-memory-address-byte-size #:x86-64-memory-mod
   #:x86-64-pack-stack-frame-locals #:x86-64-pack-stack-slots #:x86-64-peephole-lea-addresses #:x86-64-peephole-optimize #:x86-64-peephole-rewrite #:x86-64-personality-descriptor #:x86-64-personality-dispatch #:x86-64-phys-code->keyword
   #:x86-64-power-of-two-scale-from-shift #:x86-64-program-has-nonlocal-control-p #:x86-64-program-has-stack-buffer-p #:x86-64-red-zone-spill-p #:x86-64-relax-branch-encodings #:x86-64-relaxable-branch-p #:x86-64-rip-relative-address-byte-size #:x86-64-safe-stack-epilogue-size
   #:x86-64-safe-stack-pointer-size #:x86-64-safe-stack-prologue-size #:x86-64-shrink-restore #:x86-64-shrink-save #:x86-64-shrink-wrap-instructions #:x86-64-sib-index-register #:x86-64-simd-element-scale #:x86-64-single-use-const-p
   #:x86-64-speculative-execution-mitigation-enabled-p #:x86-64-spill-slot-offset #:x86-64-stack-buffer-inst-p #:x86-64-stack-canary-plan #:x86-64-stack-frame-size #:x86-64-stack-slot-alignment #:x86-64-stack-slot-name #:x86-64-stack-slot-size
   #:x86-64-supports-amx-p #:x86-64-supports-avx512-p #:x86-64-supports-bmi1-p #:x86-64-supports-bmi2-p #:x86-64-supports-cet-ss-p #:x86-64-supports-ibrs-p #:x86-64-supports-popcnt-p #:x86-64-table-eh-enabled-p
   #:x86-64-target #:x86-64-tls-base-register #:x86-64-unlikely-branch-prefix-p #:x86-64-used-callee-saved-regs #:x86-64-validate-simd-vector-op #:x86-64-vm-const-reg-value #:x86-64-vm-int-const-p #:x86-decode-instructions
   #:x86-decode-one #:x86-encode-test-rr64 #:x86-encode-xor-rr64 #:x86-legacy-prefix-byte-p #:x86-modrm-instruction-end #:x86-modrm-mod #:x86-modrm-reg #:x86-modrm-reg-full
   #:x86-modrm-rm #:x86-modrm-rm-full #:x86-patch-branch-displacement #:x86-read-s32 #:x86-read-s8 #:x86-rex-bit #:x86-rex-byte-p #:x86-write-s32
   #:x86-write-s8)
  (:shadowing-import-from #:cl-cc/codegen-native/lowering
   #:emit-instruction #:target #:target-register)
  (:import-from #:cl-cc/codegen-native/lowering
   #:*current-calling-convention* #:+stack-probe-page-size+ #:apply-calling-convention-to-target #:calling-convention #:codegen-memory-order #:define-isel-rules #:native-emit-optimized-insts
   #:native-rewrite-inst #:native-safe-identical-dedup-p #:peephole-byte-list-vector #:peephole-copy-byte-vector #:stack-probe-count #:vm-atomic-memory-order*
   #:vm-const-to-integer #:vm-program-calling-convention-object #:with-output-to-vector
   #:calling-convention-omit-frame-pointer-p #:native-peephole-inst #:make-native-peephole-inst
   #:native-peephole-inst-bytes #:native-peephole-inst-branch-size #:native-peephole-inst-end
   #:native-peephole-inst-target #:native-peephole-inst-dst #:native-peephole-inst-kind
   #:native-peephole-inst-src)
  (:import-from #:cl-cc/codegen-native/regalloc
   #:allocate-registers #:instruction-uses #:regalloc-assignment #:regalloc-instructions #:regalloc-spill-count
   #:vm-spill-dst #:vm-spill-load #:vm-spill-slot #:vm-spill-src #:vm-spill-store)
  (:import-from #:cl-cc/codegen-native/sanitizer
   #:*asan-instrumentation-enabled* #:*asan-shadow-base* #:*ubsan-instrumentation-enabled* #:sanitizer-enabled-p)
  (:import-from #:cl-cc/codegen-native/scheduling
   #:%native-block-terminator #:%native-common-dominator #:%native-inst-reads-phys-p #:%native-inst-touches-phys-p #:*shrink-wrap-enabled* #:codegen-hot-cold-ordered-instructions #:schedule-post-ra)
  (:export #:*amx-enabled* #:*eh-model* #:*isel-x86-64-rules* #:*phys-reg-to-asm-string* #:*phys-reg-to-x86-code* #:*x86-64-apx-enabled* #:*x86-64-atomics-enabled* #:*x86-64-avx512-enabled*
   #:*x86-64-cfi-enabled* #:*x86-64-safe-stack-enabled* #:*x86-64-shadow-stack-enabled* #:*x86-64-spectre-mitigations-enabled* #:*x86-64-stack-clash-protection-enabled* #:*x86-64-stack-protector-enabled* #:*x86-64-use-retpoline* #:*zero-cost-eh-enabled*
   #:+tmm0+ #:+tmm1+ #:+tmm2+ #:+tmm3+ #:+tmm4+ #:+tmm5+ #:+tmm6+ #:+tmm7+
   #:compile-to-x86-64-bytes #:emit-tdpbssd #:emit-tileloadd #:emit-tilestored #:emit-x86-64-speculation-barrier #:normalize-x86-64-eh-model #:vm-reg-to-x86-with-alloc #:win-cfg-emit-guard-check-icall-thunk
   #:win-cfg-emit-guard-dispatch-icall-thunk #:x86-64-eh-condition-matches-p #:x86-64-lsda-bytes #:x86-64-personality-dispatch #:x86-64-red-zone-spill-p #:x86-64-speculative-execution-mitigation-enabled-p #:x86-64-supports-amx-p #:x86-64-table-eh-enabled-p #:x86-64-target #:*x86-64-omit-frame-pointer*)
)
