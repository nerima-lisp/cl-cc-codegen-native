(defpackage #:cl-cc/codegen-native/targets/wasm
  (:use #:cl #:cl-cc/bootstrap #:cl-cc/vm #:cl-cc/mir #:cl-cc/target #:cl-cc/optimize)
  (:import-from #:cl-cc/vm #:vm-element-regs)
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
   #:%emit-wasm-custom-bytes #:%emit-wasm-custom-string #:%emit-wasm-dispatch-catch #:%emit-wasm-dispatch-catch-v2 #:%make-eq-hash-table #:%maybe-emit-wasm-case-dispatch-pattern #:%scan-instructions #:%wasm-aot-mode-active-p
   #:%wasm-build-case-dispatch-env #:%wasm-build-dwarf-section-alist #:%wasm-build-name-section-bytes #:%wasm-byte-vector-wat-string #:%wasm-call-string-mentions-p #:%wasm-captured-value-reg #:%wasm-case-target-pc #:%wasm-clean-debug-name
   #:%wasm-const-value-to-wat #:%wasm-dense-case-entry-labels #:%wasm-devtools-js #:%wasm-direct-call #:%wasm-dwarf-lines-for-module #:%wasm-dwarf-subprogram-for-func #:%wasm-dynamic-eh-entries #:%wasm-effective-eh-entries
   #:%wasm-eh-entry->block-entry #:%wasm-eh-pc-range-test #:%wasm-emit-atomic-op #:%wasm-emit-byte #:%wasm-emit-bytes #:%wasm-emit-fence-method #:%wasm-emit-i32-const #:%wasm-emit-i64-const
   #:%wasm-emit-memarg #:%wasm-emit-u32 #:%wasm-empty-symbol-eqref #:%wasm-encode-s32-leb128 #:%wasm-encode-s64-leb128 #:%wasm-encode-u32-leb128 #:%wasm-float-literal-eqref #:%wasm-function-index-for-label
   #:%wasm-function-local-exception-table #:%wasm-function-name-assocs #:%wasm-function-source-offset #:%wasm-human-local-name #:%wasm-i32x4-store-to-array-wat #:%wasm-if-eqref #:%wasm-import-needed-p #:%wasm-indirect-name-map
   #:%wasm-instruction-pc-index #:%wasm-json-string #:%wasm-label-at-pc #:%wasm-label-name-assocs #:%wasm-local-name-assocs #:%wasm-local-pc-block-map #:%wasm-main-function-type-index #:%wasm-memory-args
   #:%wasm-name-assoc-vector #:%wasm-name-section-subsection #:%wasm-next-label-after #:%wasm-normalize-integer-case-targets #:%wasm-normalize-wat-name #:%wasm-note-case-value #:%wasm-register-method-value-eqref #:%wasm-registers-in-function
   #:%wasm-reject-float-arithmetic #:%wasm-require-relaxed-simd #:%wasm-require-simd #:%wasm-symbol-literal-eqref #:%wasm-symbol-name-string-t-eqref #:%wasm-type-reflection-json #:%wasm-u8 #:%wasm-unsupported-vm-make-array-options
   #:%wasm-wat-string #:*wasm-abi-mangling* #:*wasm-abstract-types-enabled* #:*wasm-any-extern-convert-enabled* #:*wasm-aot-current-used-imports* #:*wasm-aot-mode* #:*wasm-aot-mode-enabled* #:*wasm-array-new-elem-enabled*
   #:*wasm-array-type-names* #:*wasm-atomic-fence-enabled* #:*wasm-atomic-wait-timeout-enabled* #:*wasm-binary-tool-integration-enabled* #:*wasm-binary-tools-path* #:*wasm-binop-dispatch* #:*wasm-branch-hinting* #:*wasm-branch-hinting-enabled*
   #:*wasm-branch-hints-enabled* #:*wasm-bulk-memory-enabled* #:*wasm-bulk-table-enabled* #:*wasm-c-api-enabled* #:*wasm-call-ctors* #:*wasm-call-indirect-table64-integration-enabled* #:*wasm-call-ref-enabled* #:*wasm-call-stack-inspection-enabled*
   #:*wasm-catch-all-ref-enabled* #:*wasm-cfi-enabled* #:*wasm-cl-abi-mangling-enabled* #:*wasm-cli-feature-flags* #:*wasm-cli-target-flags* #:*wasm-coep-enabled* #:*wasm-compact-import-section-enabled* #:*wasm-component-model*
   #:*wasm-component-model-enabled* #:*wasm-component-model-tests-enabled* #:*wasm-constant-time* #:*wasm-constant-time-enabled* #:*wasm-cont-throw-enabled* #:*wasm-coop-coep-headers* #:*wasm-coop-coep-headers-enabled* #:*wasm-coop-enabled*
   #:*wasm-copysign-enabled* #:*wasm-csp-compliant-enabled* #:*wasm-custom-annotations-enabled* #:*wasm-custom-descriptors-enabled* #:*wasm-custom-page-size* #:*wasm-custom-page-sizes-enabled* #:*wasm-dead-import-elimination* #:*wasm-dead-import-elimination-enabled*
   #:*wasm-decimal-enabled* #:*wasm-deterministic-build* #:*wasm-deterministic-builds-enabled* #:*wasm-dwarf-debug-info-enabled* #:*wasm-dwarf-enabled* #:*wasm-dynamic-linking-enabled* #:*wasm-effect-handlers-enabled* #:*wasm-eh-enabled*
   #:*wasm-element-init-enabled* #:*wasm-emit-debug-info* #:*wasm-emit-source-maps* #:*wasm-emit-sri-hash* #:*wasm-esm-integration* #:*wasm-esm-integration-enabled* #:*wasm-exception-handling-enabled* #:*wasm-exception-handling-v2-enabled*
   #:*wasm-exception-js-api-enabled* #:*wasm-exception-tag-import-export-enabled* #:*wasm-exnref-enabled* #:*wasm-extended-const-exprs* #:*wasm-extended-const-exprs-enabled* #:*wasm-extended-const-ref-func-enabled* #:*wasm-extended-names-enabled* #:*wasm-extern-to-any-enabled*
   #:*wasm-externref-enabled* #:*wasm-fixnum-unboxed-regs* #:*wasm-flexible-vectors-enabled* #:*wasm-float-to-int-table* #:*wasm-func-bind-enabled* #:*wasm-gc-array-types-enabled* #:*wasm-gc-bulk-array-ops-enabled* #:*wasm-gc-enabled*
   #:*wasm-gc-finalization-enabled* #:*wasm-gc-frozen-values-enabled* #:*wasm-gc-full-hierarchy-enabled* #:*wasm-gc-more-array-constructors-enabled* #:*wasm-gc-multibyte-array-access-enabled* #:*wasm-gc-null-safety-enabled* #:*wasm-gc-packed-fields-enabled* #:*wasm-gc-rec-types-enabled*
   #:*wasm-gc-struct-types-enabled* #:*wasm-gc-write-barriers-enabled* #:*wasm-global-atomic-enabled* #:*wasm-half-precision-enabled* #:*wasm-hot-code-reload-enabled* #:*wasm-hot-reload* #:*wasm-i31ref-enabled* #:*wasm-i31ref-optimize-enabled*
   #:*wasm-i64-binop-table* #:*wasm-i64-cmp-table* #:*wasm-i8x16-swizzle-enabled* #:*wasm-import-maps* #:*wasm-import-maps-enabled* #:*wasm-incremental-repl* #:*wasm-integer-range-annotation-enabled* #:*wasm-jit-interface-enabled*
   #:*wasm-js-bigint-i64-enabled* #:*wasm-js-primitive-builtins-enabled* #:*wasm-js-promise-enabled* #:*wasm-js-promise-integration-enabled* #:*wasm-label-to-table-idx* #:*wasm-lazy-function-bodies* #:*wasm-lazy-function-bodies-enabled* #:*wasm-lto-enabled*
   #:*wasm-memory-control-enabled* #:*wasm-memory-grow-oom-check-enabled* #:*wasm-memory-profiler-enabled* #:*wasm-memory64-enabled* #:*wasm-minmax-table* #:*wasm-module-init-order-enabled* #:*wasm-module-postmessage-enabled* #:*wasm-multi-memory-atomics-enabled*
   #:*wasm-multi-memory-bulk-copy-enabled* #:*wasm-multibyte-array-access* #:*wasm-multiple-memories* #:*wasm-multiple-memories-enabled* #:*wasm-mvp-bit-ops-enabled* #:*wasm-non-trapping-float-to-int-enabled* #:*wasm-oom-detection* #:*wasm-passive-element-data-segments-enabled*
   #:*wasm-passive-segments* #:*wasm-pgo-enabled* #:*wasm-pgo-mode* #:*wasm-profile* #:*wasm-profiles-enabled* #:*wasm-ref-cast-elimination-enabled* #:*wasm-ref-eq-enabled* #:*wasm-ref-types-externref-enabled*
   #:*wasm-reference-typed-strings-enabled* #:*wasm-relaxed-dead-code-validation* #:*wasm-relaxed-dead-code-validation-enabled* #:*wasm-relaxed-simd-enabled* #:*wasm-relaxed-simd-integer-ops-enabled* #:*wasm-relaxed-simd-nan-warning-issued* #:*wasm-repl-incremental-compilation-enabled* #:*wasm-return-call-ref-enabled*
   #:*wasm-rounding-variants-enabled* #:*wasm-runtime-feature-detect* #:*wasm-runtime-feature-detection-enabled* #:*wasm-service-worker* #:*wasm-service-worker-enabled* #:*wasm-shared-everything-enabled* #:*wasm-shared-everything-threads-enabled* #:*wasm-sign-extend-table*
   #:*wasm-sign-extension-enabled* #:*wasm-simd-boolean-reduction-enabled* #:*wasm-simd-complete-enabled* #:*wasm-simd-lane-load-store-enabled* #:*wasm-simd-load32-load64-zero-enabled* #:*wasm-simd-nan-semantics-documented* #:*wasm-simd-strict-nan* #:*wasm-simd128-enabled*
   #:*wasm-source-map-enabled* #:*wasm-source-map-url* #:*wasm-sri-hashes-enabled* #:*wasm-stack-switching-enabled* #:*wasm-startup-snapshots-enabled* #:*wasm-streaming-compilation* #:*wasm-streaming-compilation-enabled* #:*wasm-strict-nan*
   #:*wasm-string-iterator-views-enabled* #:*wasm-string-transcoding-complete-enabled* #:*wasm-struct-atomic-enabled* #:*wasm-struct-exception-payload-enabled* #:*wasm-struct-get-table* #:*wasm-sub-word-atomics-enabled* #:*wasm-table64-enabled* #:*wasm-tail-call-enabled*
   #:*wasm-threads-enabled* #:*wasm-threads-worker-count* #:*wasm-tiered-compilation-enabled* #:*wasm-tiered-compilation-hints* #:*wasm-tiered-compilation-hints-enabled* #:*wasm-type-imports-enabled* #:*wasm-type-reflection-js-api-enabled* #:*wasm-typed-closure-env-enabled*
   #:*wasm-typed-func-refs-enabled* #:*wasm-typed-select-enabled* #:*wasm-unary-fixnum-table* #:*wasm-validate-api-enabled* #:*wasm-validate-output* #:*wasm-value-type-byte-table* #:*wasm-wasi-02-enabled* #:*wasm-wasi-extended-worlds-enabled*
   #:*wasm-wasi-p2-enabled* #:*wasm-wasi-p3-enabled* #:*wasm-wasi-preview1-compat-shim-enabled* #:*wasm-wasi-random-crypto-enabled* #:*wasm-wasi-worlds-full-enabled* #:*wasm-wide-arithmetic-enabled* #:*wasm-worker-module-transfer* #:+heap-any+
   #:+heap-array+ #:+heap-eq+ #:+heap-extern+ #:+heap-func+ #:+heap-i31+ #:+heap-noextern+ #:+heap-nofunc+ #:+heap-none+
   #:+heap-struct+ #:+num-predefined-types+ #:+tag-idx-cl-condition+ #:+type-idx-bytes-array+ #:+type-idx-char+ #:+type-idx-char-array+ #:+type-idx-class-meta+ #:+type-idx-closure+
   #:+type-idx-cons+ #:+type-idx-env+ #:+type-idx-eqref-array+ #:+type-idx-fixnum-array+ #:+type-idx-float+ #:+type-idx-float-array+ #:+type-idx-htable+ #:+type-idx-instance+
   #:+type-idx-main-func+ #:+type-idx-string+ #:+type-idx-symbol+ #:+wasm-anyref+ #:+wasm-arrayref+ #:+wasm-atomic-fence+ #:+wasm-atomic-i32-load-wat+ #:+wasm-atomic-i32-load16-u-wat+
   #:+wasm-atomic-i32-load8-u-wat+ #:+wasm-atomic-i32-rmw-add+ #:+wasm-atomic-i32-rmw-add-wat+ #:+wasm-atomic-i32-rmw-cmpxchg+ #:+wasm-atomic-i32-rmw-cmpxchg-wat+ #:+wasm-atomic-i32-rmw16-add-u-wat+ #:+wasm-atomic-i32-rmw16-cmpxchg-u-wat+ #:+wasm-atomic-i32-rmw8-add-u-wat+
   #:+wasm-atomic-i32-rmw8-cmpxchg-u-wat+ #:+wasm-atomic-i32-store-wat+ #:+wasm-atomic-i32-store16-wat+ #:+wasm-atomic-i32-store8-wat+ #:+wasm-atomic-i64-load-wat+ #:+wasm-atomic-i64-rmw-add+ #:+wasm-atomic-i64-rmw-add-wat+ #:+wasm-atomic-i64-rmw-cmpxchg+
   #:+wasm-atomic-i64-rmw-cmpxchg-wat+ #:+wasm-atomic-i64-store-wat+ #:+wasm-atomic-memory-notify+ #:+wasm-atomic-memory-wait32+ #:+wasm-atomic-memory-wait64+ #:+wasm-atomic-notify+ #:+wasm-atomic-prefix+ #:+wasm-atomic-wait32+
   #:+wasm-atomic-wait64+ #:+wasm-block+ #:+wasm-br+ #:+wasm-br-if+ #:+wasm-br-on-non-null+ #:+wasm-br-on-null+ #:+wasm-br-table+ #:+wasm-call+
   #:+wasm-call-indirect+ #:+wasm-call-ref+ #:+wasm-case-br-table-max-density-ratio+ #:+wasm-case-br-table-min-arms+ #:+wasm-catch+ #:+wasm-catch-all-ref+ #:+wasm-catch-ref+ #:+wasm-cont-bind+
   #:+wasm-cont-new+ #:+wasm-cont-throw+ #:+wasm-data-drop+ #:+wasm-default-memory-offset+ #:+wasm-drop+ #:+wasm-effect-declare+ #:+wasm-effect-perform+ #:+wasm-effect-resume+
   #:+wasm-elem-drop+ #:+wasm-else+ #:+wasm-end+ #:+wasm-eqref+ #:+wasm-exnref+ #:+wasm-export-func+ #:+wasm-export-global+ #:+wasm-export-memory+
   #:+wasm-export-table+ #:+wasm-export-tag+ #:+wasm-externref+ #:+wasm-f16+ #:+wasm-f16-add+ #:+wasm-f16-convert-f32+ #:+wasm-f16-div+ #:+wasm-f16-load+
   #:+wasm-f16-max+ #:+wasm-f16-min+ #:+wasm-f16-mul+ #:+wasm-f16-store+ #:+wasm-f16-sub+ #:+wasm-f32+ #:+wasm-f32-abs+ #:+wasm-f32-add+
   #:+wasm-f32-ceil+ #:+wasm-f32-convert-f16+ #:+wasm-f32-copysign+ #:+wasm-f32-div+ #:+wasm-f32-floor+ #:+wasm-f32-max+ #:+wasm-f32-min+ #:+wasm-f32-mul+
   #:+wasm-f32-nearest+ #:+wasm-f32-neg+ #:+wasm-f32-sqrt+ #:+wasm-f32-sub+ #:+wasm-f32-trunc+ #:+wasm-f32x4-relaxed-madd+ #:+wasm-f32x4-relaxed-max+ #:+wasm-f32x4-relaxed-min+
   #:+wasm-f32x4-relaxed-nmadd+ #:+wasm-f64+ #:+wasm-f64-abs+ #:+wasm-f64-add+ #:+wasm-f64-ceil+ #:+wasm-f64-const+ #:+wasm-f64-convert-i64-s+ #:+wasm-f64-copysign+
   #:+wasm-f64-div+ #:+wasm-f64-floor+ #:+wasm-f64-max+ #:+wasm-f64-min+ #:+wasm-f64-mul+ #:+wasm-f64-nearest+ #:+wasm-f64-neg+ #:+wasm-f64-sqrt+
   #:+wasm-f64-sub+ #:+wasm-f64-trunc+ #:+wasm-f64x2-relaxed-madd+ #:+wasm-f64x2-relaxed-max+ #:+wasm-f64x2-relaxed-min+ #:+wasm-f64x2-relaxed-nmadd+ #:+wasm-field-i16+ #:+wasm-field-i8+
   #:+wasm-func-bind+ #:+wasm-funcref+ #:+wasm-gc-any-convert-extern+ #:+wasm-gc-array-fill+ #:+wasm-gc-array-get+ #:+wasm-gc-array-get-s+ #:+wasm-gc-array-get-u+ #:+wasm-gc-array-init-data+
   #:+wasm-gc-array-init-elem+ #:+wasm-gc-array-len+ #:+wasm-gc-array-load2-u+ #:+wasm-gc-array-load4-u+ #:+wasm-gc-array-new+ #:+wasm-gc-array-new-data+ #:+wasm-gc-array-new-default+ #:+wasm-gc-array-new-elem+
   #:+wasm-gc-array-new-fixed+ #:+wasm-gc-array-new-immutable+ #:+wasm-gc-array-set+ #:+wasm-gc-array-store2+ #:+wasm-gc-array-store4+ #:+wasm-gc-br-on-cast+ #:+wasm-gc-br-on-cast-fail+ #:+wasm-gc-extern-convert-any+
   #:+wasm-gc-i31-get-s+ #:+wasm-gc-i31-get-u+ #:+wasm-gc-prefix+ #:+wasm-gc-ref-cast+ #:+wasm-gc-ref-i31+ #:+wasm-gc-ref-test+ #:+wasm-gc-struct-get+ #:+wasm-gc-struct-get-s+
   #:+wasm-gc-struct-get-s-packed+ #:+wasm-gc-struct-get-u+ #:+wasm-gc-struct-get-u-packed+ #:+wasm-gc-struct-new+ #:+wasm-gc-struct-new-default+ #:+wasm-gc-struct-new-immutable+ #:+wasm-gc-struct-set+ #:+wasm-gc-struct-set-packed+
   #:+wasm-global-get+ #:+wasm-global-set+ #:+wasm-i16x8-add+ #:+wasm-i16x8-relaxed-lane-select+ #:+wasm-i16x8-relaxed-q15mulr-s+ #:+wasm-i31-max+ #:+wasm-i31-min+ #:+wasm-i31ref+
   #:+wasm-i32+ #:+wasm-i32-atomic-align+ #:+wasm-i32-atomic-load+ #:+wasm-i32-atomic-rmw-add+ #:+wasm-i32-atomic-rmw-cmpxchg+ #:+wasm-i32-atomic-rmw16-add-u+ #:+wasm-i32-atomic-rmw16-and-u+ #:+wasm-i32-atomic-rmw16-cmpxchg-u+
   #:+wasm-i32-atomic-rmw16-or-u+ #:+wasm-i32-atomic-rmw16-sub-u+ #:+wasm-i32-atomic-rmw16-xchg-u+ #:+wasm-i32-atomic-rmw16-xor-u+ #:+wasm-i32-atomic-rmw8-add-u+ #:+wasm-i32-atomic-rmw8-and-u+ #:+wasm-i32-atomic-rmw8-cmpxchg-u+ #:+wasm-i32-atomic-rmw8-or-u+
   #:+wasm-i32-atomic-rmw8-sub-u+ #:+wasm-i32-atomic-rmw8-xchg-u+ #:+wasm-i32-atomic-rmw8-xor-u+ #:+wasm-i32-atomic-store+ #:+wasm-i32-clz+ #:+wasm-i32-const+ #:+wasm-i32-ctz+ #:+wasm-i32-eq+
   #:+wasm-i32-eqz+ #:+wasm-i32-extend16-s+ #:+wasm-i32-extend8-s+ #:+wasm-i32-ge-s+ #:+wasm-i32-gt-s+ #:+wasm-i32-le-s+ #:+wasm-i32-lt-s+ #:+wasm-i32-ne+
   #:+wasm-i32-popcnt+ #:+wasm-i32-trunc-sat-f32-s+ #:+wasm-i32-trunc-sat-f32-u+ #:+wasm-i32-trunc-sat-f64-s+ #:+wasm-i32-trunc-sat-f64-u+ #:+wasm-i32-wrap-i64+ #:+wasm-i32x4-add+ #:+wasm-i32x4-relaxed-lane-select+
   #:+wasm-i32x4-relaxed-trunc-f32x4-s+ #:+wasm-i32x4-relaxed-trunc-f32x4-u+ #:+wasm-i32x4-relaxed-trunc-f64x2-s-zero+ #:+wasm-i32x4-relaxed-trunc-f64x2-u-zero+ #:+wasm-i64+ #:+wasm-i64-add+ #:+wasm-i64-add-carry+ #:+wasm-i64-add128+
   #:+wasm-i64-and+ #:+wasm-i64-atomic-align+ #:+wasm-i64-atomic-load+ #:+wasm-i64-atomic-rmw-add+ #:+wasm-i64-atomic-rmw-cmpxchg+ #:+wasm-i64-atomic-store+ #:+wasm-i64-clz+ #:+wasm-i64-const+
   #:+wasm-i64-ctz+ #:+wasm-i64-div-s+ #:+wasm-i64-div-u+ #:+wasm-i64-eq+ #:+wasm-i64-eqz+ #:+wasm-i64-extend-i32-s+ #:+wasm-i64-extend16-s+ #:+wasm-i64-extend32-s+
   #:+wasm-i64-extend8-s+ #:+wasm-i64-ge-s+ #:+wasm-i64-gt-s+ #:+wasm-i64-le-s+ #:+wasm-i64-lt-s+ #:+wasm-i64-mul+ #:+wasm-i64-mul-wide-s+ #:+wasm-i64-mul-wide-u+
   #:+wasm-i64-ne+ #:+wasm-i64-or+ #:+wasm-i64-popcnt+ #:+wasm-i64-rem-s+ #:+wasm-i64-rem-u+ #:+wasm-i64-rotl+ #:+wasm-i64-rotr+ #:+wasm-i64-shl+
   #:+wasm-i64-shr-s+ #:+wasm-i64-shr-u+ #:+wasm-i64-sub+ #:+wasm-i64-sub-borrow+ #:+wasm-i64-sub128+ #:+wasm-i64-trunc-f64-s+ #:+wasm-i64-trunc-sat-f32-s+ #:+wasm-i64-trunc-sat-f32-u+
   #:+wasm-i64-trunc-sat-f64-s+ #:+wasm-i64-trunc-sat-f64-u+ #:+wasm-i64-xor+ #:+wasm-i64x2-add+ #:+wasm-i64x2-relaxed-lane-select+ #:+wasm-i8x16-add+ #:+wasm-i8x16-relaxed-lane-select+ #:+wasm-i8x16-relaxed-swizzle+
   #:+wasm-if+ #:+wasm-immutable+ #:+wasm-import-func+ #:+wasm-import-global+ #:+wasm-import-memory+ #:+wasm-import-table+ #:+wasm-import-tag+ #:+wasm-import-type+
   #:+wasm-local-get+ #:+wasm-local-set+ #:+wasm-local-tee+ #:+wasm-loop+ #:+wasm-max-call-args+ #:+wasm-memory-copy+ #:+wasm-memory-discard+ #:+wasm-memory-fill+
   #:+wasm-memory-gc-heap+ #:+wasm-memory-grow64+ #:+wasm-memory-init+ #:+wasm-memory-limits-shared+ #:+wasm-memory-size64+ #:+wasm-memory-stack+ #:+wasm-memory-strings+ #:+wasm-misc-prefix+
   #:+wasm-mutable+ #:+wasm-nop+ #:+wasm-nullexternref+ #:+wasm-nullfuncref+ #:+wasm-nullref+ #:+wasm-ref-as-non-null+ #:+wasm-ref-eq+ #:+wasm-ref-func+
   #:+wasm-ref-is-null+ #:+wasm-ref-null+ #:+wasm-resume+ #:+wasm-resume-throw+ #:+wasm-return+ #:+wasm-return-call+ #:+wasm-return-call-indirect+ #:+wasm-section-code+
   #:+wasm-section-custom+ #:+wasm-section-data+ #:+wasm-section-data-count+ #:+wasm-section-element+ #:+wasm-section-export+ #:+wasm-section-function+ #:+wasm-section-global+ #:+wasm-section-import+
   #:+wasm-section-memory+ #:+wasm-section-start+ #:+wasm-section-table+ #:+wasm-section-tag+ #:+wasm-section-type+ #:+wasm-select+ #:+wasm-select-typed+ #:+wasm-simd-f64x2-add+
   #:+wasm-simd-f64x2-div+ #:+wasm-simd-f64x2-mul+ #:+wasm-simd-i32x4-add+ #:+wasm-simd-i32x4-all-true+ #:+wasm-simd-i8x16-shuffle+ #:+wasm-simd-i8x16-swizzle+ #:+wasm-simd-prefix+ #:+wasm-simd-v128-and+
   #:+wasm-simd-v128-any-true+ #:+wasm-simd-v128-load+ #:+wasm-simd-v128-load16-splat+ #:+wasm-simd-v128-load32-splat+ #:+wasm-simd-v128-load32-zero+ #:+wasm-simd-v128-load64-splat+ #:+wasm-simd-v128-load64-zero+ #:+wasm-simd-v128-load8-lane+
   #:+wasm-simd-v128-load8-splat+ #:+wasm-simd-v128-not+ #:+wasm-simd-v128-or+ #:+wasm-simd-v128-store+ #:+wasm-simd-v128-store8-lane+ #:+wasm-simd-v128-xor+ #:+wasm-string-builtins-encodings+ #:+wasm-string-compare+
   #:+wasm-string-concat+ #:+wasm-string-encode-utf8+ #:+wasm-string-encode-wtf16+ #:+wasm-string-encode-wtf8+ #:+wasm-string-from-code-point+ #:+wasm-string-get-codeunit+ #:+wasm-string-length+ #:+wasm-string-measure-utf8+
   #:+wasm-string-measure-wtf16+ #:+wasm-string-measure-wtf8+ #:+wasm-string-new-lossy-utf8+ #:+wasm-string-new-utf8+ #:+wasm-string-new-wtf8+ #:+wasm-stringref+ #:+wasm-structref+ #:+wasm-suspend+
   #:+wasm-table-copy+ #:+wasm-table-fill+ #:+wasm-table-init+ #:+wasm-thread-spawn+ #:+wasm-throw+ #:+wasm-throw-ref+ #:+wasm-try+ #:+wasm-try-table+
   #:+wasm-type-array+ #:+wasm-type-func+ #:+wasm-type-rec+ #:+wasm-type-struct+ #:+wasm-type-sub+ #:+wasm-type-sub-final+ #:+wasm-unreachable+ #:+wasm-v128+
   #:+wasm-v128-and+ #:+wasm-v128-const+ #:+wasm-v128-load+ #:+wasm-v128-or+ #:+wasm-v128-store+ #:+wasm-v128-xor+ #:+wasm-void+ #:build-all-wasm-functions
   #:build-label-pc-map #:build-trampoline-body #:build-wasm-function-wat #:call-wasm-threads-backend #:codegen-emit-wasm-atomic-load #:codegen-emit-wasm-atomic-notify #:codegen-emit-wasm-atomic-rmw-add #:codegen-emit-wasm-atomic-rmw-cmpxchg
   #:codegen-emit-wasm-atomic-store #:codegen-emit-wasm-atomic-wait #:codegen-emit-wasm-fence #:codegen-wasm-shared-memory-wat #:codegen-wasm-threads-flag-enabled-p #:codegen-wasm-worker-runtime-initialization #:collect-entry-labels #:collect-function-params
   #:collect-registers-from-instructions #:compile-to-wasm-binary #:compile-to-wasm-wat #:define-escaped-string-writer #:define-wasm-binary-arith-alias-emit-method #:define-wasm-binary-arith-emit-method #:define-wasm-fence-emitters #:define-wasm-simd-emitter
   #:define-wasm-string-emit-method #:define-wasm-unsupported-float-arith-emit-method #:emit-trampoline-instruction #:emit-trampoline-jump-to-label #:emit-wasm-annotation-custom-section #:emit-wasm-atomic-load #:emit-wasm-atomic-notify #:emit-wasm-atomic-rmw-add
   #:emit-wasm-atomic-rmw-cmpxchg #:emit-wasm-atomic-store #:emit-wasm-atomic-wait #:emit-wasm-binary-module #:emit-wasm-boxed-closure-alloc #:emit-wasm-branch-hints-section #:emit-wasm-closure-allocation #:emit-wasm-developer-tooling-sections
   #:emit-wasm-dwarf-sections #:emit-wasm-elem-drop-wat #:emit-wasm-fence #:emit-wasm-i64-atomic-rmw-cmpxchg #:emit-wasm-i8x16-shuffle #:emit-wasm-module #:emit-wasm-name-section #:emit-wasm-profiles-section
   #:emit-wasm-shared-memory #:emit-wasm-shared-memory-init #:emit-wasm-simd-expr #:emit-wasm-source-map-reference #:emit-wasm-string-as-iter-wat #:emit-wasm-string-as-wtf16-wat #:emit-wasm-string-compare-wat #:emit-wasm-string-concat-wat
   #:emit-wasm-string-decode-wat #:emit-wasm-string-encode-wat #:emit-wasm-string-eq-wat #:emit-wasm-string-from-code-point-wat #:emit-wasm-string-measure-wat #:emit-wasm-string-new-lossy-utf8-wat #:emit-wasm-string-new-utf8-wat #:emit-wasm-string-new-wat
   #:emit-wasm-string-new-wtf8-wat #:emit-wasm-string-utf8-roundtrip-wat #:emit-wasm-stringview-iter-next-wat #:emit-wasm-stringview-wtf16-get-codeunit-wat #:emit-wasm-table-copy-wat #:emit-wasm-table-fill-wat #:emit-wasm-table-init-wat #:emit-wasm-thread-spawn
   #:emit-wasm-try-table-wat #:emit-wasm-typed-closure-alloc #:emit-wasm-typed-select-wat #:emit-wasm-v128-load #:emit-wasm-v128-load-lane #:emit-wasm-v128-load-splat #:emit-wasm-v128-load-zero #:emit-wasm-v128-load16-lane
   #:emit-wasm-v128-load16-splat #:emit-wasm-v128-load32-lane #:emit-wasm-v128-load32-splat #:emit-wasm-v128-load32-zero #:emit-wasm-v128-load64-lane #:emit-wasm-v128-load64-splat #:emit-wasm-v128-load64-zero #:emit-wasm-v128-load8-lane
   #:emit-wasm-v128-load8-splat #:emit-wasm-v128-store #:emit-wasm-v128-store-lane #:emit-wasm-v128-store16-lane #:emit-wasm-v128-store32-lane #:emit-wasm-v128-store64-lane #:emit-wasm-v128-store8-lane #:emit-wasm-vm-simd-vector-op
   #:emit-wat-bigint-js-wrapper-code #:emit-wat-bigint-wrapper #:emit-wat-bigint-wrappers #:emit-wat-call-globals #:emit-wat-deployment-js-glue #:emit-wat-eh-v2-helper #:emit-wat-elem #:emit-wat-exception-helper
   #:emit-wat-function #:emit-wat-function-locals #:emit-wat-globals #:emit-wat-imports #:emit-wat-js-conversion-functions #:emit-wat-js-conversion-helpers #:emit-wat-js-exception-bridge-glue #:emit-wat-js-ffi-helpers
   #:emit-wat-js-primitive-builtins #:emit-wat-js-promise-glue #:emit-wat-linear-memory-helpers #:emit-wat-low-priority-proposal-helpers #:emit-wat-memories #:emit-wat-shared-memory #:emit-wat-string-builtin-helpers #:emit-wat-table
   #:emit-wat-table64-helpers #:emit-wat-tags #:emit-wat-type-section #:emit-wat-worker-bootstrap #:ensure-wasm-condition-tag! #:entry-label-to-wat-name #:extract-wasm-functions #:group-into-basic-blocks
   #:initialize-wasm-param-locals #:js-ref-get #:js-ref-p #:make-empty-wasm-module #:make-wasm-basic-block #:make-wasm-func-from-segment #:make-wasm-function-def #:make-wasm-global-def
   #:make-wasm-reg-map #:make-wasm-reg-map-for-function #:make-wasm-tag-def #:maybe-emit-wasm-dense-case-br-table #:maybe-emit-wasm-string-instruction #:reg-clear-type #:reg-known-fixnum-range #:reg-known-type
   #:reg-local-ref #:reg-local-set #:reg-record-fixnum-range #:reg-record-type #:reject-unimplemented-aot-host-bridges #:segment-instructions #:vm-global-wat-name #:wasm-any-convert-extern-wat
   #:wasm-array-cast-wat #:wasm-array-copy-wat #:wasm-array-default-wat #:wasm-array-element-to-eqref-wat #:wasm-array-fill-wat #:wasm-array-get-eqref-wat #:wasm-array-init-data-wat #:wasm-array-init-elem-wat
   #:wasm-array-len-wat #:wasm-array-load2-u-wat #:wasm-array-load4-u-wat #:wasm-array-new-data-wat #:wasm-array-new-elem-wat #:wasm-array-new-immutable-wat #:wasm-array-new-wat #:wasm-array-reg-copy-kind
   #:wasm-array-reg-kind #:wasm-array-reg-record-kind #:wasm-array-set-wat #:wasm-array-store2-wat #:wasm-array-store4-wat #:wasm-array-type #:wasm-array-type-name #:wasm-array-type-ref
   #:wasm-atomic-add-opcode #:wasm-atomic-address-wat #:wasm-atomic-align-for-width #:wasm-atomic-cmpxchg-opcode #:wasm-atomic-load-opcode #:wasm-atomic-load-wat #:wasm-atomic-memarg-wat #:wasm-atomic-memory-index
   #:wasm-atomic-notify-wat #:wasm-atomic-result-box-wat #:wasm-atomic-rmw-add-wat #:wasm-atomic-rmw-cmpxchg-wat #:wasm-atomic-store-opcode #:wasm-atomic-store-wat #:wasm-atomic-value-wat #:wasm-atomic-wait-wat
   #:wasm-atomic-wat #:wasm-atomic-width-for-inst #:wasm-basic-block #:wasm-basic-block-p #:wasm-bb-instructions #:wasm-bb-label #:wasm-bb-pc-index #:wasm-bigint-feature-enabled-p
   #:wasm-bigint-wrapper-name #:wasm-binary-export-name-for-function #:wasm-binary-function-body-bytes #:wasm-binary-module-functions #:wasm-binary-section-buffer #:wasm-binary-section-bytes #:wasm-binary-value-type-byte #:wasm-binary-write-bytes
   #:wasm-binary-write-code-section #:wasm-binary-write-export-section #:wasm-binary-write-func-type #:wasm-binary-write-function-section #:wasm-binary-write-local-decls #:wasm-binary-write-name #:wasm-binary-write-section #:wasm-binary-write-type-section
   #:wasm-binary-write-u8 #:wasm-binary-write-uleb128 #:wasm-binary-write-valtype-vector #:wasm-block-result-types-wat #:wasm-bool-to-eqref-wat #:wasm-bool-to-i31 #:wasm-branch-hints-feature-enabled-p #:wasm-build-effective-slot-order
   #:wasm-bulk-table-feature-enabled-p #:wasm-call-indirect-wat #:wasm-case-dispatch-env #:wasm-catch-all-ref-feature-enabled-p #:wasm-cfi-feature-enabled-p #:wasm-cl-thread-semantic-mapping #:wasm-clear-reg-unboxed-fixnum #:wasm-closure-ref-wat
   #:wasm-cont-bind-wat #:wasm-cont-new-wat #:wasm-cont-throw-wat #:wasm-continuation-exceptions-feature-enabled-p #:wasm-coop-coep-feature-enabled-p #:wasm-copysign-wat #:wasm-custom-page-sizes-feature-enabled-p #:wasm-dense-integer-case-targets-p
   #:wasm-dwarf-feature-enabled-p #:wasm-effect-perform-wat #:wasm-eh-feature-enabled-p #:wasm-eh-v2-feature-enabled-p #:wasm-element-init-feature-enabled-p #:wasm-encode-array-new #:wasm-encode-call #:wasm-encode-call-indirect
   #:wasm-encode-catch #:wasm-encode-gc-op-u32 #:wasm-encode-global-get #:wasm-encode-global-set #:wasm-encode-op-u32 #:wasm-encode-signed-leb128 #:wasm-encode-simd-op #:wasm-encode-struct-new
   #:wasm-encode-throw #:wasm-encode-try #:wasm-encode-u32-leb128 #:wasm-encode-unsigned-leb128 #:wasm-encode-vm-instruction-opcode #:wasm-env-false-p #:wasm-env-true-p #:wasm-eq-wat
   #:wasm-exception-tag-linking-feature-enabled-p #:wasm-exnref-feature-enabled-p #:wasm-export #:wasm-extended-const-ref-func-feature-enabled-p #:wasm-extended-names-feature-enabled-p #:wasm-extern-convert-any-wat #:wasm-extern-to-any-feature-enabled-p #:wasm-f16-binop-wat
   #:wasm-f16-convert-f32-wat #:wasm-f16-load-wat #:wasm-f16-store-wat #:wasm-f32-convert-f16-wat #:wasm-feature-enabled-p #:wasm-field #:wasm-fixnum-box #:wasm-fixnum-unbox
   #:wasm-fixnum-unboxed-reg-p #:wasm-flexible-vector-op-wat #:wasm-func-bind-feature-enabled-p #:wasm-func-bind-wat #:wasm-func-index #:wasm-func-type #:wasm-function-def #:wasm-function-param-regs
   #:wasm-gc-bulk-array-ops-feature-enabled-p #:wasm-gc-exception-payload-feature-enabled-p #:wasm-gc-null-safety-feature-enabled-p #:wasm-gc-packed-fields-feature-enabled-p #:wasm-gc-recursive-types-feature-enabled-p #:wasm-global-def #:wasm-global-def-index #:wasm-half-precision-feature-enabled-p
   #:wasm-i31-range-p #:wasm-i32-atomic-rmw16-cmpxchg-u-wat #:wasm-i32-atomic-rmw16-op-u-wat #:wasm-i32-atomic-rmw8-cmpxchg-u-wat #:wasm-i32-atomic-rmw8-op-u-wat #:wasm-i32x4-splat-from-array #:wasm-i32x4-vector-op-wat #:wasm-i64-add128-wat
   #:wasm-i64-binop #:wasm-i64-clz-wat #:wasm-i64-cmp #:wasm-i64-const-wat-value #:wasm-i64-ctz-wat #:wasm-i64-extended-i31-source #:wasm-i64-mul-wide-s-wat #:wasm-i64-mul-wide-u-wat
   #:wasm-i64-popcnt-wat #:wasm-i64-sub128-wat #:wasm-import #:wasm-import-cl-condition-tag-enabled-p #:wasm-import-maps-feature-enabled-p #:wasm-js-exception-bridge-feature-enabled-p #:wasm-js-promise-feature-enabled-p #:wasm-js-ref-box-wat
   #:wasm-js-ref-unbox-wat #:wasm-linear-load-wat #:wasm-linear-store-wat #:wasm-lisp-name-to-wat-id #:wasm-local #:wasm-mark-reg-unboxed-fixnum #:wasm-memory-const-wat #:wasm-memory-copy-wat
   #:wasm-memory-copy-wat* #:wasm-memory-declaration-wat #:wasm-memory-discard-wat #:wasm-memory-fill-wat #:wasm-memory-grow-checked-wat #:wasm-memory-grow-wat #:wasm-memory-index-type-wat #:wasm-memory-load-opcode-wat
   #:wasm-memory-memarg-wat #:wasm-memory-size-wat #:wasm-memory-store-opcode-wat #:wasm-memory64-feature-enabled-p #:wasm-module-add-function #:wasm-module-add-global #:wasm-module-add-tag #:wasm-module-function-index-for-label
   #:wasm-module-function-label-table #:wasm-module-functions #:wasm-module-global-index-for-name #:wasm-module-global-name-table #:wasm-module-ir #:wasm-module-record-function-label! #:wasm-module-table-size #:wasm-module-tag-name-table
   #:wasm-module-tags #:wasm-module-type-signature-table #:wasm-module-used-host-imports #:wasm-multi-memory-atomics-feature-enabled-p #:wasm-multi-memory-bulk-copy-feature-enabled-p #:wasm-multiple-memories-feature-enabled-p #:wasm-normalize-array-element-kind #:wasm-pgo-feature-enabled-p
   #:wasm-profiles-feature-enabled-p #:wasm-range-binop #:wasm-range-i31-or-unknown #:wasm-range-unary #:wasm-record-class-slot-layout! #:wasm-record-class-slot-layout-for-class! #:wasm-ref-as-non-null-wat #:wasm-ref-cast-maybe
   #:wasm-ref-eq-feature-enabled-p #:wasm-ref-eq-wat #:wasm-ref-test-wat #:wasm-reference-typed-strings-feature-enabled-p #:wasm-reg-map #:wasm-reg-map-eh-tag-index #:wasm-reg-map-exnref-index #:wasm-reg-map-next-index
   #:wasm-reg-map-pc-index #:wasm-reg-map-tmp-index #:wasm-reg-to-array-element-wat #:wasm-reg-to-local #:wasm-relaxed-simd-emission-enabled-p #:wasm-relaxed-simd-feature-enabled-p #:wasm-require-threads-for-atomic #:wasm-resume-wat
   #:wasm-shared-everything-feature-enabled-p #:wasm-shared-memory-wat #:wasm-sign-extend-32-16-wat #:wasm-sign-extend-32-8-wat #:wasm-sign-extend-64-16-wat #:wasm-sign-extend-64-32-wat #:wasm-sign-extend-64-8-wat #:wasm-simd-expr
   #:wasm-simd-feature-enabled-p #:wasm-simd128-emission-enabled-p #:wasm-slot-index-for #:wasm-slot-index-for-object-slot #:wasm-source-map-enabled-p #:wasm-startup-snapshot-comment-wat #:wasm-storage-condition-wat #:wasm-strict-nan-emission-enabled-p
   #:wasm-strict-nan-enabled-p #:wasm-string-builtin-encoding-name #:wasm-string-builtins-feature-enabled-p #:wasm-string-char-wat #:wasm-string-compare-predicate-wat #:wasm-string-literal-wat #:wasm-stringref-from-eqref-wat #:wasm-stringref-get-codeunit-wat
   #:wasm-stringref-length-wat #:wasm-struct-get-packed-wat #:wasm-struct-new-immutable-wat #:wasm-struct-type #:wasm-suspend-wat #:wasm-table-const-wat #:wasm-table-index-from-eqref-wat #:wasm-table-index-type-wat
   #:wasm-table64-feature-enabled-p #:wasm-tag-def #:wasm-tag-def-index #:wasm-tag-def-params #:wasm-tag-def-wat-name #:wasm-tail-call-feature-enabled-p #:wasm-target #:wasm-target-class-slot-layouts
   #:wasm-target-class-slot-orders #:wasm-target-known-class-by-reg #:wasm-target-known-func-labels #:wasm-target-known-object-class-by-reg #:wasm-target-known-slot-indexes #:wasm-target-module #:wasm-target-reg-map #:wasm-target-try-depth
   #:wasm-target-try-stack #:wasm-threads-backend-function #:wasm-threads-feature-enabled-p #:wasm-threads-flag-enabled-p #:wasm-tiered-compilation-feature-enabled-p #:wasm-trunc-sat-f32-i32-wat #:wasm-trunc-sat-f32-i64-wat #:wasm-trunc-sat-f64-i32-wat
   #:wasm-trunc-sat-f64-i64-wat #:wasm-type-entry #:wasm-typed-refs-feature-enabled-p #:wasm-typed-select-feature-enabled-p #:wasm-unsupported-atomic-swap #:wasm-v128-const #:wasm-value-to-array-element-wat #:wasm-values-multi-value-block-wat
   #:wasm-values-wat #:wasm-vector-literal-kind #:wasm-vector-literal-wat #:wasm-vm-slot-value #:wasm-wide-arithmetic-feature-enabled-p #:wasm-worker-runtime-initialization #:with-wasm-atomic-threads)
  (:shadowing-import-from #:cl-cc/codegen-native/lowering
   #:emit-instruction #:target #:target-register)
  (:export #:*wasm-bulk-memory-enabled* #:*wasm-label-to-table-idx* #:*wasm-memory-grow-oom-check-enabled* #:*wasm-threads-enabled* #:*wasm-threads-worker-count* #:+wasm-anyref+ #:+wasm-arrayref+ #:+wasm-block+
   #:+wasm-br+ #:+wasm-br-if+ #:+wasm-br-on-non-null+ #:+wasm-br-on-null+ #:+wasm-br-table+ #:+wasm-call+ #:+wasm-call-indirect+ #:+wasm-call-ref+
   #:+wasm-catch+ #:+wasm-cont-bind+ #:+wasm-cont-new+ #:+wasm-cont-throw+ #:+wasm-data-drop+ #:+wasm-drop+ #:+wasm-elem-drop+ #:+wasm-else+
   #:+wasm-end+ #:+wasm-eqref+ #:+wasm-export-func+ #:+wasm-export-global+ #:+wasm-export-memory+ #:+wasm-export-table+ #:+wasm-externref+ #:+wasm-f16-add+
   #:+wasm-f16-div+ #:+wasm-f16-load+ #:+wasm-f16-max+ #:+wasm-f16-min+ #:+wasm-f16-mul+ #:+wasm-f16-store+ #:+wasm-f16-sub+ #:+wasm-f32+
   #:+wasm-f32-abs+ #:+wasm-f32-add+ #:+wasm-f32-ceil+ #:+wasm-f32-copysign+ #:+wasm-f32-div+ #:+wasm-f32-floor+ #:+wasm-f32-max+ #:+wasm-f32-min+
   #:+wasm-f32-mul+ #:+wasm-f32-nearest+ #:+wasm-f32-neg+ #:+wasm-f32-sqrt+ #:+wasm-f32-sub+ #:+wasm-f32-trunc+ #:+wasm-f32x4-relaxed-madd+ #:+wasm-f32x4-relaxed-max+
   #:+wasm-f32x4-relaxed-min+ #:+wasm-f32x4-relaxed-nmadd+ #:+wasm-f64+ #:+wasm-f64-abs+ #:+wasm-f64-add+ #:+wasm-f64-ceil+ #:+wasm-f64-const+ #:+wasm-f64-convert-i64-s+
   #:+wasm-f64-copysign+ #:+wasm-f64-div+ #:+wasm-f64-floor+ #:+wasm-f64-max+ #:+wasm-f64-min+ #:+wasm-f64-mul+ #:+wasm-f64-nearest+ #:+wasm-f64-neg+
   #:+wasm-f64-sqrt+ #:+wasm-f64-sub+ #:+wasm-f64-trunc+ #:+wasm-f64x2-relaxed-madd+ #:+wasm-f64x2-relaxed-max+ #:+wasm-f64x2-relaxed-min+ #:+wasm-f64x2-relaxed-nmadd+ #:+wasm-field-i16+
   #:+wasm-field-i8+ #:+wasm-func-bind+ #:+wasm-funcref+ #:+wasm-gc-any-convert-extern+ #:+wasm-gc-array-fill+ #:+wasm-gc-array-get+ #:+wasm-gc-array-get-s+ #:+wasm-gc-array-get-u+
   #:+wasm-gc-array-len+ #:+wasm-gc-array-load2-u+ #:+wasm-gc-array-load4-u+ #:+wasm-gc-array-new+ #:+wasm-gc-array-new-data+ #:+wasm-gc-array-new-default+ #:+wasm-gc-array-new-elem+ #:+wasm-gc-array-new-fixed+
   #:+wasm-gc-array-new-immutable+ #:+wasm-gc-array-set+ #:+wasm-gc-array-store2+ #:+wasm-gc-array-store4+ #:+wasm-gc-br-on-cast+ #:+wasm-gc-br-on-cast-fail+ #:+wasm-gc-extern-convert-any+ #:+wasm-gc-i31-get-s+
   #:+wasm-gc-i31-get-u+ #:+wasm-gc-prefix+ #:+wasm-gc-ref-cast+ #:+wasm-gc-ref-i31+ #:+wasm-gc-ref-test+ #:+wasm-gc-struct-get+ #:+wasm-gc-struct-get-s+ #:+wasm-gc-struct-get-s-packed+
   #:+wasm-gc-struct-get-u+ #:+wasm-gc-struct-get-u-packed+ #:+wasm-gc-struct-new+ #:+wasm-gc-struct-new-default+ #:+wasm-gc-struct-new-immutable+ #:+wasm-gc-struct-set+ #:+wasm-gc-struct-set-packed+ #:+wasm-global-get+
   #:+wasm-global-set+ #:+wasm-i16x8-add+ #:+wasm-i16x8-relaxed-lane-select+ #:+wasm-i16x8-relaxed-q15mulr-s+ #:+wasm-i31-max+ #:+wasm-i31-min+ #:+wasm-i31ref+ #:+wasm-i32+
   #:+wasm-i32-clz+ #:+wasm-i32-const+ #:+wasm-i32-ctz+ #:+wasm-i32-eq+ #:+wasm-i32-eqz+ #:+wasm-i32-extend16-s+ #:+wasm-i32-extend8-s+ #:+wasm-i32-ge-s+
   #:+wasm-i32-gt-s+ #:+wasm-i32-le-s+ #:+wasm-i32-lt-s+ #:+wasm-i32-ne+ #:+wasm-i32-popcnt+ #:+wasm-i32-trunc-sat-f32-s+ #:+wasm-i32-trunc-sat-f32-u+ #:+wasm-i32-trunc-sat-f64-s+
   #:+wasm-i32-trunc-sat-f64-u+ #:+wasm-i32-wrap-i64+ #:+wasm-i32x4-add+ #:+wasm-i32x4-relaxed-lane-select+ #:+wasm-i32x4-relaxed-trunc-f32x4-s+ #:+wasm-i32x4-relaxed-trunc-f32x4-u+ #:+wasm-i32x4-relaxed-trunc-f64x2-s-zero+ #:+wasm-i32x4-relaxed-trunc-f64x2-u-zero+
   #:+wasm-i64+ #:+wasm-i64-add+ #:+wasm-i64-add128+ #:+wasm-i64-and+ #:+wasm-i64-clz+ #:+wasm-i64-const+ #:+wasm-i64-ctz+ #:+wasm-i64-div-s+
   #:+wasm-i64-div-u+ #:+wasm-i64-eq+ #:+wasm-i64-eqz+ #:+wasm-i64-extend-i32-s+ #:+wasm-i64-extend16-s+ #:+wasm-i64-extend32-s+ #:+wasm-i64-extend8-s+ #:+wasm-i64-ge-s+
   #:+wasm-i64-gt-s+ #:+wasm-i64-le-s+ #:+wasm-i64-lt-s+ #:+wasm-i64-mul+ #:+wasm-i64-mul-wide-s+ #:+wasm-i64-mul-wide-u+ #:+wasm-i64-ne+ #:+wasm-i64-or+
   #:+wasm-i64-popcnt+ #:+wasm-i64-rem-s+ #:+wasm-i64-rem-u+ #:+wasm-i64-rotl+ #:+wasm-i64-rotr+ #:+wasm-i64-shl+ #:+wasm-i64-shr-s+ #:+wasm-i64-shr-u+
   #:+wasm-i64-sub+ #:+wasm-i64-sub128+ #:+wasm-i64-trunc-f64-s+ #:+wasm-i64-trunc-sat-f32-s+ #:+wasm-i64-trunc-sat-f32-u+ #:+wasm-i64-trunc-sat-f64-s+ #:+wasm-i64-trunc-sat-f64-u+ #:+wasm-i64-xor+
   #:+wasm-i64x2-add+ #:+wasm-i64x2-relaxed-lane-select+ #:+wasm-i8x16-add+ #:+wasm-i8x16-relaxed-lane-select+ #:+wasm-i8x16-relaxed-swizzle+ #:+wasm-if+ #:+wasm-immutable+ #:+wasm-import-func+
   #:+wasm-import-global+ #:+wasm-import-memory+ #:+wasm-import-table+ #:+wasm-local-get+ #:+wasm-local-set+ #:+wasm-local-tee+ #:+wasm-loop+ #:+wasm-max-call-args+
   #:+wasm-memory-copy+ #:+wasm-memory-fill+ #:+wasm-memory-grow64+ #:+wasm-memory-init+ #:+wasm-memory-size64+ #:+wasm-misc-prefix+ #:+wasm-mutable+ #:+wasm-nop+
   #:+wasm-nullexternref+ #:+wasm-nullfuncref+ #:+wasm-nullref+ #:+wasm-ref-as-non-null+ #:+wasm-ref-eq+ #:+wasm-ref-func+ #:+wasm-ref-is-null+ #:+wasm-ref-null+
   #:+wasm-resume+ #:+wasm-resume-throw+ #:+wasm-return+ #:+wasm-return-call+ #:+wasm-return-call-indirect+ #:+wasm-section-code+ #:+wasm-section-custom+ #:+wasm-section-data+
   #:+wasm-section-data-count+ #:+wasm-section-element+ #:+wasm-section-export+ #:+wasm-section-function+ #:+wasm-section-global+ #:+wasm-section-import+ #:+wasm-section-memory+ #:+wasm-section-start+
   #:+wasm-section-table+ #:+wasm-section-tag+ #:+wasm-section-type+ #:+wasm-select+ #:+wasm-select-typed+ #:+wasm-simd-prefix+ #:+wasm-string-compare+ #:+wasm-string-concat+
   #:+wasm-string-encode-utf8+ #:+wasm-string-encode-wtf16+ #:+wasm-string-encode-wtf8+ #:+wasm-string-from-code-point+ #:+wasm-string-measure-utf8+ #:+wasm-string-measure-wtf16+ #:+wasm-string-measure-wtf8+ #:+wasm-string-new-lossy-utf8+
   #:+wasm-string-new-utf8+ #:+wasm-string-new-wtf8+ #:+wasm-structref+ #:+wasm-suspend+ #:+wasm-table-copy+ #:+wasm-table-fill+ #:+wasm-table-init+ #:+wasm-throw+
   #:+wasm-throw-ref+ #:+wasm-try+ #:+wasm-try-table+ #:+wasm-type-array+ #:+wasm-type-func+ #:+wasm-type-rec+ #:+wasm-type-struct+ #:+wasm-type-sub+
   #:+wasm-type-sub-final+ #:+wasm-unreachable+ #:+wasm-v128-and+ #:+wasm-v128-const+ #:+wasm-v128-load+ #:+wasm-v128-or+ #:+wasm-v128-store+ #:+wasm-v128-xor+
   #:+wasm-void+ #:build-all-wasm-functions #:build-label-pc-map #:build-wasm-function-wat #:compile-to-wasm-binary #:compile-to-wasm-wat #:emit-trampoline-instruction #:emit-trampoline-jump-to-label
   #:emit-wasm-atomic-notify #:emit-wasm-atomic-rmw-add #:emit-wasm-atomic-rmw-cmpxchg #:emit-wasm-atomic-wait #:emit-wasm-binary-module #:emit-wasm-branch-hints-section #:emit-wasm-closure-allocation #:emit-wasm-dwarf-sections
   #:emit-wasm-fence #:emit-wasm-i64-atomic-rmw-cmpxchg #:emit-wasm-module #:emit-wasm-profiles-section #:emit-wasm-shared-memory #:emit-wasm-shared-memory-init #:emit-wasm-source-map-reference #:emit-wat-call-globals
   #:emit-wat-elem #:emit-wat-exception-helper #:emit-wat-function #:emit-wat-function-locals #:emit-wat-globals #:emit-wat-imports #:emit-wat-table #:emit-wat-tags
   #:emit-wat-type-section #:ensure-wasm-condition-tag! #:group-into-basic-blocks #:make-wasm-basic-block #:reg-clear-type #:reg-known-fixnum-range #:reg-known-type #:reg-local-ref
   #:reg-local-set #:reg-record-fixnum-range #:reg-record-type #:wasm-array-cast-wat #:wasm-array-copy-wat #:wasm-array-default-wat #:wasm-array-element-to-eqref-wat #:wasm-array-get-eqref-wat
   #:wasm-array-len-wat #:wasm-array-new-wat #:wasm-array-reg-copy-kind #:wasm-array-reg-kind #:wasm-array-reg-record-kind #:wasm-array-set-wat #:wasm-array-type-name #:wasm-array-type-ref
   #:wasm-atomic-wat #:wasm-basic-block #:wasm-basic-block-p #:wasm-bb-instructions #:wasm-bb-label #:wasm-bb-pc-index #:wasm-binary-export-name-for-function #:wasm-binary-function-body-bytes
   #:wasm-binary-module-functions #:wasm-binary-section-buffer #:wasm-binary-section-bytes #:wasm-binary-value-type-byte #:wasm-binary-write-bytes #:wasm-binary-write-code-section #:wasm-binary-write-export-section #:wasm-binary-write-func-type
   #:wasm-binary-write-function-section #:wasm-binary-write-local-decls #:wasm-binary-write-name #:wasm-binary-write-section #:wasm-binary-write-type-section #:wasm-binary-write-u8 #:wasm-binary-write-uleb128 #:wasm-binary-write-valtype-vector
   #:wasm-bool-to-i31 #:wasm-cl-thread-semantic-mapping #:wasm-closure-ref-wat #:wasm-copysign-wat #:wasm-encode-array-new #:wasm-encode-call #:wasm-encode-call-indirect #:wasm-encode-catch
   #:wasm-encode-gc-op-u32 #:wasm-encode-global-get #:wasm-encode-global-set #:wasm-encode-op-u32 #:wasm-encode-signed-leb128 #:wasm-encode-simd-op #:wasm-encode-struct-new #:wasm-encode-throw
   #:wasm-encode-try #:wasm-encode-u32-leb128 #:wasm-encode-unsigned-leb128 #:wasm-encode-vm-instruction-opcode #:wasm-fixnum-box #:wasm-fixnum-unbox #:wasm-i31-range-p #:wasm-i64-binop
   #:wasm-i64-clz-wat #:wasm-i64-cmp #:wasm-i64-const-wat-value #:wasm-i64-ctz-wat #:wasm-i64-extended-i31-source #:wasm-memory-copy-wat #:wasm-memory-fill-wat #:wasm-memory-grow-checked-wat
   #:wasm-normalize-array-element-kind #:wasm-profiles-feature-enabled-p #:wasm-range-binop #:wasm-range-i31-or-unknown #:wasm-range-unary #:wasm-ref-cast-maybe #:wasm-reg-to-array-element-wat #:wasm-shared-memory-wat
   #:wasm-sign-extend-32-16-wat #:wasm-sign-extend-32-8-wat #:wasm-sign-extend-64-32-wat #:wasm-source-map-enabled-p #:wasm-target #:wasm-target-class-slot-layouts #:wasm-target-class-slot-orders #:wasm-target-known-class-by-reg
   #:wasm-target-known-func-labels #:wasm-target-known-object-class-by-reg #:wasm-target-known-slot-indexes #:wasm-target-module #:wasm-target-reg-map #:wasm-target-try-depth #:wasm-target-try-stack #:wasm-threads-flag-enabled-p
   #:wasm-trunc-sat-f64-i32-wat #:wasm-trunc-sat-f64-i64-wat #:wasm-value-to-array-element-wat #:wasm-vector-literal-kind #:wasm-vector-literal-wat #:wasm-worker-runtime-initialization
   #:*wasm-aot-mode-enabled* #:*wasm-dead-import-elimination-enabled* #:extract-wasm-functions
   #:wasm-func-export-name #:wasm-func-exported-p #:wasm-func-index #:wasm-func-wat-name
   #:wasm-global-def-wat-name #:wasm-module-functions #:wasm-module-globals #:*wasm-call-stack-inspection-enabled* #:*wasm-dwarf-debug-info-enabled* #:*wasm-extended-names-enabled* #:*wasm-hot-code-reload-enabled* #:*wasm-js-bigint-i64-enabled* #:*wasm-memory-profiler-enabled* #:*wasm-memory64-enabled* #:*wasm-repl-incremental-compilation-enabled* #:*wasm-source-map-enabled* #:*wasm-source-map-url* #:*wasm-table64-enabled* #:*wasm-type-reflection-js-api-enabled*)
)

(defpackage #:cl-cc/codegen-native/targets/wasm/infra
  (:use #:cl)
  (:shadow
   #:%source-map-json-string #:%source-map-json-string-array #:%source-map-normalize-entry #:%source-map-result-assembly #:%source-map-result-ast #:%source-map-result-program #:%source-map-result-vm-instructions #:%source-map-source-index
   #:%source-map-symbol-call #:%source-map-vlq-signed #:%wasm-base64-encode #:%wasm-byte-vector-hex-digest #:%wasm-hex-digest-file #:%wasm-hex-to-bytes #:%wasm-read-bytes-file #:%wasm-source-map-entries-from-asts
   #:%wasm-temp-path #:%wasm-write-bytes-file #:*wasm-tool-timeout-seconds* #:+source-map-base64-digits+ #:+wasm-base64-alphabet+ #:build-wasm-source-map-v3 #:compile-to-aot-wasm #:source-map-encode-mappings
   #:source-map-encode-vlq #:wasm-aot-result #:wasm-aot-result-bytes #:wasm-aot-result-metadata #:wasm-aot-result-wat #:wasm-append-build-hash-section #:wasm-binary-write-custom-section #:wasm-determinize-module!
   #:wasm-eliminate-dead-exports! #:wasm-file-content-hash #:wasm-file-sri-hash #:wasm-run-tool-to-string #:wasm-run-wasm-opt-passes #:wasm-run-wasm2wat #:wasm-source-map-entries-for-result #:wasm-source-map-path
   #:wasm-tool-available-p #:wasm-wat-to-binary-if-available #:write-wasm-source-map #:write-wasm-with-source-map)
  (:import-from #:cl-cc/codegen-native/targets/wasm
   #:*wasm-aot-mode-enabled* #:*wasm-dead-import-elimination-enabled* #:+wasm-section-custom+ #:build-all-wasm-functions #:emit-wasm-binary-module #:emit-wasm-module #:extract-wasm-functions #:wasm-binary-write-bytes
   #:wasm-binary-write-name #:wasm-binary-write-section #:wasm-func-export-name #:wasm-func-exported-p #:wasm-func-index #:wasm-func-wat-name #:wasm-global-def-wat-name #:wasm-module-functions
   #:wasm-module-globals)
  (:export
   #:build-wasm-source-map-v3 #:compile-to-aot-wasm #:source-map-encode-vlq #:wasm-aot-result #:wasm-aot-result-bytes #:wasm-aot-result-metadata #:wasm-aot-result-wat #:wasm-file-content-hash
   #:wasm-file-sri-hash #:wasm-run-tool-to-string #:wasm-tool-available-p #:write-wasm-source-map #:write-wasm-with-source-map)
)
