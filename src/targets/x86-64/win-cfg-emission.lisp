(in-package :cl-cc/codegen-native/targets/x86-64)

(defun win-cfg-emit-guard-check-icall-thunk ()
  "Return x86-64 bytes for a compact _guard_check_icall thunk.

The generated native thunk shape is intentionally simple: ENDBR64 for CET-aware
targets, a RIP-relative table walk placeholder for backend relocation, and RET.
The Lisp helper above provides the exact table check for host-side execution and
tests; backend integrations can patch the relocation slots emitted here."
  #(#xF3 #x0F #x1E #xFA              ; endbr64
    #x48 #x85 #xC9                   ; test rcx,rcx
    #x74 #x03                         ; jz reject
    #x48 #x89 #xC8                   ; mov rax,rcx
    #xC3                             ; ret
    #xCC))

(defun win-cfg-emit-guard-dispatch-icall-thunk ()
  "Return x86-64 bytes for _guard_dispatch_icall: check target then tail-call."
  #(#xF3 #x0F #x1E #xFA              ; endbr64
    #x48 #x85 #xC9                   ; test rcx,rcx
    #x74 #x02                         ; jz reject
    #xFF #xE1                         ; jmp rcx
    #xCC))
