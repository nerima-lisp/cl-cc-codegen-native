(defpackage #:cl-cc/codegen-native/regalloc
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
   #:%allocation-strategy #:%assign-live-range-split-slots #:%boundaries-by-position #:%build-spill-interference-matrix #:%call-crossing-preferred-reg #:%collect-live-range-splits #:%color-assign-spill-slots #:%color-build-interference-graph
   #:%color-ordered-registers-for-interval #:%color-select-register #:%color-simplify #:%color-spill-candidate #:%color-spill-priority #:%compute-live-intervals-raw #:%copy-float-vreg-map-with-splits #:%copy-hash-into
   #:%copy-interference-graph #:%copy-live-interval-segment #:%derive-single-function-policy #:%finalize-split-spill-registers #:%graph-degree #:%graph-nodes #:%graph-remove-node #:%hint-policy-preferred-reg
   #:%interval-map #:%interval-next-use-after #:%intervals-overlap-p #:%lsa-allocate-from-pool #:%lsa-assign #:%lsa-best-spill-candidate #:%lsa-evict-and-assign #:%lsa-expire-old
   #:%lsa-interval-pool #:%lsa-set-interval-pool #:%lsa-spill-current #:%lsa-try-coalesce #:%maybe-color-spill-slots #:%param-preferred-reg #:%preferred-register-for-interval #:%regalloc-map-tree
   #:%regalloc-rematerialize-inst #:%regalloc-reserved-scratch-regs #:%regalloc-rewrite-inst #:%regalloc-rewrite-inst-dst #:%regalloc-scratch-candidates #:%return-value-preferred-reg #:%rewrite-inst-for-split-position #:%spill-intervals-overlap-p
   #:%spill-weight #:%split-live-range-rewrite-map #:%split-vreg-at-position #:%split-vreg-name #:%vreg< #:*current-allocation-policy* #:*current-regalloc* #:*current-regalloc-loop-depths*
   #:*live-range-split-minimum-hole-size* #:*ml-regalloc-enabled* #:*preferred-register-strategies* #:*regalloc-allocation-strategy* #:allocate-registers #:build-label-map #:color-allocate #:color-allocate-for-target
   #:color-spill-slots #:compute-live-intervals #:insert-spill-code #:instruction-defs #:instruction-uses #:interval-end #:interval-phys-reg #:interval-remat-const
   #:interval-remat-inst #:interval-spill-slot #:interval-start #:interval-vreg #:linear-scan-allocate #:live-interval #:live-range-split-boundary #:lsa-active
   #:lsa-assignment #:lsa-free-fp-regs #:lsa-free-regs #:lsa-state #:make-live-interval #:make-live-range-split-boundary #:make-lsa-state #:make-regalloc-result
   #:make-vm-spill-load #:make-vm-spill-store #:regalloc-assignment #:regalloc-build-allocation-policy-from-hints #:regalloc-build-direct-call-graph #:regalloc-collect-linear-functions #:regalloc-color-spill-slots #:regalloc-compute-interprocedural-hints
   #:regalloc-fp-pressure #:regalloc-function-leaf-p #:regalloc-gpr-pressure #:regalloc-instructions #:regalloc-lookup #:regalloc-loop-depths #:regalloc-ml-spill-cost #:regalloc-register-pressure
   #:regalloc-result #:regalloc-spill-count #:regalloc-spill-map #:regalloc-target-fp-registers #:split-boundary-before-position #:split-boundary-slot #:split-live-interval #:split-live-ranges
   #:vm-spill-dst #:vm-spill-load #:vm-spill-slot #:vm-spill-src #:vm-spill-store)
  (:export
   #:*current-regalloc* #:*ml-regalloc-enabled* #:*regalloc-allocation-strategy* #:allocate-registers #:color-allocate #:color-spill-slots #:compute-live-intervals #:instruction-defs
   #:instruction-uses #:interval-end #:interval-phys-reg #:interval-remat-const #:interval-remat-inst #:interval-spill-slot #:interval-start #:interval-vreg
   #:linear-scan-allocate #:live-interval #:make-live-interval #:make-vm-spill-load #:make-vm-spill-store #:regalloc-assignment #:regalloc-fp-pressure #:regalloc-gpr-pressure
   #:regalloc-instructions #:regalloc-lookup #:regalloc-loop-depths #:regalloc-ml-spill-cost #:regalloc-result #:regalloc-spill-count #:regalloc-spill-map #:split-live-interval
   #:vm-spill-dst #:vm-spill-load #:vm-spill-slot #:vm-spill-src #:vm-spill-store)
)
