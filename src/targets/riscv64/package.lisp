(defpackage #:cl-cc/codegen-native/targets/riscv64
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
   #:%check-halfword-offset #:%check-signed #:%check-unsigned #:%encode-rvc-b #:%freg #:%mask #:%push-byte #:%reg
   #:%riscv64-u8 #:%rvc-reg3 #:*current-riscv64-float-vregs* #:*current-riscv64-regalloc* #:*current-riscv64-spill-base-reg* #:*current-riscv64-spill-offset-bias* #:*riscv64-b-encoders* #:*riscv64-emitter-table*
   #:*riscv64-fp-reg-number* #:*riscv64-fp-registers* #:*riscv64-i-encoders* #:*riscv64-omit-frame-pointer* #:*riscv64-r-encoders* #:*riscv64-reg-number* #:*riscv64-registers* #:*riscv64-s-encoders*
   #:*riscv64-zicond-enabled* #:+rv-a0+ #:+rv-a1+ #:+rv-a2+ #:+rv-a3+ #:+rv-a4+ #:+rv-a5+ #:+rv-a6+
   #:+rv-a7+ #:+rv-amo+ #:+rv-auipc+ #:+rv-branch+ #:+rv-fp+ #:+rv-gp+ #:+rv-jal+ #:+rv-jalr+
   #:+rv-load+ #:+rv-load-fp+ #:+rv-lui+ #:+rv-misc-mem+ #:+rv-op+ #:+rv-op-fp+ #:+rv-op-imm+ #:+rv-ra+
   #:+rv-s0+ #:+rv-s1+ #:+rv-s10+ #:+rv-s11+ #:+rv-s2+ #:+rv-s3+ #:+rv-s4+ #:+rv-s5+
   #:+rv-s6+ #:+rv-s7+ #:+rv-s8+ #:+rv-s9+ #:+rv-sp+ #:+rv-store+ #:+rv-store-fp+ #:+rv-t0+
   #:+rv-t1+ #:+rv-t2+ #:+rv-t3+ #:+rv-t4+ #:+rv-t5+ #:+rv-t6+ #:+rv-tp+ #:+rv-zero+
   #:+rv-zicond-funct7+ #:build-riscv64-label-offsets #:compile-to-riscv64-bytes #:define-riscv64-binary-emitter #:define-riscv64-fp-binary-emitter #:define-rv-encoders #:emit-riscv16 #:emit-riscv32
   #:emit-riscv64-epilogue #:emit-riscv64-instruction #:emit-riscv64-li #:emit-riscv64-program #:emit-riscv64-prologue #:emit-riscv64-vm-add #:emit-riscv64-vm-const #:emit-riscv64-vm-div
   #:emit-riscv64-vm-float-add #:emit-riscv64-vm-float-div #:emit-riscv64-vm-float-mul #:emit-riscv64-vm-float-sub #:emit-riscv64-vm-halt #:emit-riscv64-vm-jump #:emit-riscv64-vm-jump-zero #:emit-riscv64-vm-move
   #:emit-riscv64-vm-mul #:emit-riscv64-vm-rem #:emit-riscv64-vm-ret #:emit-riscv64-vm-select #:emit-riscv64-vm-spill-load #:emit-riscv64-vm-spill-store #:emit-riscv64-vm-sub #:encode-rv-add
   #:encode-rv-addi #:encode-rv-amo #:encode-rv-amoadd-d #:encode-rv-amoand-d #:encode-rv-amoor-d #:encode-rv-amoswap-d #:encode-rv-auipc #:encode-rv-b
   #:encode-rv-beq #:encode-rv-bge #:encode-rv-blt #:encode-rv-bne #:encode-rv-czero-eqz #:encode-rv-czero-nez #:encode-rv-div #:encode-rv-fadd-d
   #:encode-rv-fadd-s #:encode-rv-fcvt-d-l #:encode-rv-fcvt-d-s #:encode-rv-fcvt-l-d #:encode-rv-fcvt-s-d #:encode-rv-fdiv-d #:encode-rv-fdiv-s #:encode-rv-fence
   #:encode-rv-fld #:encode-rv-fmul-d #:encode-rv-fmul-s #:encode-rv-fmv-d-x #:encode-rv-fmv-x-d #:encode-rv-fsd #:encode-rv-fsub-d #:encode-rv-fsub-s
   #:encode-rv-i #:encode-rv-j #:encode-rv-jal #:encode-rv-jalr #:encode-rv-ld #:encode-rv-lr-d #:encode-rv-lui #:encode-rv-mul
   #:encode-rv-or #:encode-rv-r #:encode-rv-rem #:encode-rv-ret #:encode-rv-s #:encode-rv-sc-d #:encode-rv-sd #:encode-rv-shift-i
   #:encode-rv-slli #:encode-rv-slt #:encode-rv-slti #:encode-rv-sub #:encode-rv-u #:encode-rvc-addi #:encode-rvc-beqz #:encode-rvc-bnez
   #:encode-rvc-j #:encode-rvc-jr #:encode-rvc-ld #:encode-rvc-ldsp #:encode-rvc-li #:encode-rvc-nop #:encode-rvc-sd #:encode-rvc-sdsp
   #:make-riscv64-assembler #:riscv-check-branch-aligned #:riscv-check-signed #:riscv-compressed-reg-p #:riscv-compressed-reg3 #:riscv-signed-field #:riscv64-assembler #:riscv64-codegen-target
   #:riscv64-compute-float-vregs #:riscv64-emit-bytes #:riscv64-emit-epilogue #:riscv64-emit-function #:riscv64-emit-instruction #:riscv64-emit-load-immediate #:riscv64-emit-pic-call #:riscv64-emit-prologue
   #:riscv64-emit-u16 #:riscv64-emit-u32 #:riscv64-fp-reg-number #:riscv64-freg #:riscv64-instruction-size #:riscv64-reg #:riscv64-reg-number #:riscv64-small-immediate-p
   #:riscv64-spill-slot-offset #:riscv64-target #:riscv64-used-callee-saved-regs)
  (:shadowing-import-from #:cl-cc/codegen-native/lowering
   #:target)
  (:import-from #:cl-cc/codegen-native/lowering
    #:vm-const-to-integer #:with-output-to-vector)
  (:import-from #:cl-cc/codegen-native/regalloc
   #:allocate-registers #:regalloc-assignment #:regalloc-instructions #:regalloc-spill-count
   #:vm-spill-dst #:vm-spill-load #:vm-spill-slot #:vm-spill-src #:vm-spill-store)
  (:import-from #:cl-cc/codegen-native/scheduling
   #:codegen-hot-cold-ordered-instructions #:schedule-post-ra)
  (:export
   #:*riscv64-zicond-enabled* #:compile-to-riscv64-bytes #:make-riscv64-assembler #:riscv64-emit-bytes #:riscv64-emit-epilogue #:riscv64-emit-function #:riscv64-emit-instruction #:riscv64-emit-load-immediate
   #:riscv64-emit-pic-call #:riscv64-emit-prologue #:riscv64-target)
)
