(in-package :cl-cc/codegen-native/targets/aarch64)

(defun encode-a64-dmb-ish () #xD5033BBF)

(defun encode-a64-ldxr (rt rn) (logior #xC85F7C00 (ash (logand rn #x1F) 5) (logand rt #x1F)))

(defun encode-a64-stxr (rs rt rn) (logior #xC8007C00 (logand rs #x1F) (ash (logand rn #x1F) 5) (ash (logand rt #x1F) 16)))

(defun encode-a64-cbnz (rn imm19) (logior #xB5000000 (ash (logand imm19 #x7FFFF) 5) (logand rn #x1F)))

(defun encode-a64-casal (rs rt rn) (logior #xC8E0FC00 (ash (logand rs #x1F) 16) (ash (logand rn #x1F) 5) (logand rt #x1F)))

(defun emit-a64-dmb-for-order (order stream)
  "Emit AArch64 DMB ISH for non-relaxed ordering."
  (unless (eq (codegen-memory-order order) :relaxed)
    (emit-a64-instr (encode-a64-dmb-ish) stream)))

(defun emit-a64-atomic-cas (inst stream)
  "Lower VM CAS to ARMv8.1 CASAL."
  (let ((addr (a64-reg (vm-acas-addr inst)))
        (expected (a64-reg (vm-acas-expected inst)))
        (newval (a64-reg (vm-acas-newval inst)))
        (dst (a64-reg (vm-dst inst)))
        (order (vm-atomic-memory-order* inst)))
    (emit-a64-dmb-for-order order stream)
    (emit-a64-instr (encode-mov-rr dst expected) stream)
    (emit-a64-instr (encode-a64-casal newval dst addr) stream)
    (emit-a64-dmb-for-order order stream)))

(defun emit-a64-atomic-swap (inst stream)
  "Lower VM atomic swap to an LDXR/STXR retry loop."
  (let ((addr (a64-reg (vm-aswap-addr inst)))
        (newval (a64-reg (vm-aswap-newval inst)))
        (dst (a64-reg (vm-dst inst)))
        (order (vm-atomic-memory-order* inst)))
    (emit-a64-dmb-for-order order stream)
    (emit-a64-instr (encode-a64-ldxr dst addr) stream)
    (emit-a64-instr (encode-a64-stxr +a64-stack-probe-scratch+ newval addr) stream)
    (emit-a64-instr (encode-a64-cbnz +a64-stack-probe-scratch+ -2) stream)
    (emit-a64-dmb-for-order order stream)))

(defun emit-a64-atomic-fetch-add (inst stream)
  "Lower VM fetch-add to an LDXR/STXR retry loop."
  (let ((addr (a64-reg (vm-aincf-addr inst)))
        (delta (a64-reg (vm-aincf-delta inst)))
        (dst (a64-reg (vm-dst inst)))
        (order (vm-atomic-memory-order* inst)))
    (emit-a64-dmb-for-order order stream)
    (emit-a64-instr (encode-a64-ldxr dst addr) stream)
    (emit-a64-instr (encode-add +a64-scs-tmp+ dst delta) stream)
    (emit-a64-instr (encode-a64-stxr +a64-stack-probe-scratch+ +a64-scs-tmp+ addr) stream)
    (emit-a64-instr (encode-a64-cbnz +a64-stack-probe-scratch+ -3) stream)
    (emit-a64-dmb-for-order order stream)))

(defun emit-a64-memory-barrier (inst stream)
  "Lower VM memory barrier to DMB ISH except for relaxed barriers."
  (emit-a64-dmb-for-order (vm-atomic-memory-order* inst) stream))

(defun emit-a64-atomic-load (inst stream)
  "Lower VM atomic load to LDXR plus DMB ordering."
  (emit-a64-dmb-for-order (vm-atomic-memory-order* inst) stream)
  (emit-a64-instr (encode-a64-ldxr (a64-reg (vm-dst inst))
                                   (a64-reg (vm-aload-addr inst))) stream)
  (emit-a64-dmb-for-order (vm-atomic-memory-order* inst) stream))

(defun emit-a64-atomic-store (inst stream)
  "Lower VM atomic store to STXR retry loop plus DMB ordering."
  (let ((addr (a64-reg (vm-astore-addr inst)))
        (val (a64-reg (vm-astore-val inst))))
    (emit-a64-dmb-for-order (vm-atomic-memory-order* inst) stream)
    (emit-a64-instr (encode-a64-stxr +a64-stack-probe-scratch+ val addr) stream)
    (emit-a64-instr (encode-a64-cbnz +a64-stack-probe-scratch+ -1) stream)
    (emit-a64-dmb-for-order (vm-atomic-memory-order* inst) stream)))
