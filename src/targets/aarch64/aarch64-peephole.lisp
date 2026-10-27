(in-package :cl-cc/codegen-native/targets/aarch64)

;;; AArch64 post-emit peephole.  Fixed-width instructions make boundary handling
;;; simple, but branch displacement remapping is still required after removals.

(defun a64-read-u32 (bytes pos)
  (logior (aref bytes pos)
          (ash (aref bytes (+ pos 1)) 8)
          (ash (aref bytes (+ pos 2)) 16)
          (ash (aref bytes (+ pos 3)) 24)))

(defun a64-write-u32 (bytes pos word)
  (setf (aref bytes pos) (logand word #xFF)
        (aref bytes (+ pos 1)) (logand (ash word -8) #xFF)
        (aref bytes (+ pos 2)) (logand (ash word -16) #xFF)
        (aref bytes (+ pos 3)) (logand (ash word -24) #xFF)))

(defun a64-sign-extend (value bits)
  (let ((sign (ash 1 (1- bits))))
    (if (logtest value sign)
        (- value (ash 1 bits))
        value)))

(defun a64-mov-rr-word-p (word)
  (= (logand word #xFFE0FFE0) #xAA0003E0))

(defun a64-mov-rd (word) (ldb (byte 5 0) word))

(defun a64-mov-rn (word) (ldb (byte 5 16) word))

(defun a64-cmp-zr-word-p (word)
  (and (= (logand word #xFFE0FC1F) #xEB00001F)
       (= (ldb (byte 5 16) word) 31)))

(defun a64-bcond-word-p (word)
  (= (logand word #xFF000010) #x54000000))

(defun a64-cbz-word-p (word)
  (= (logand word #xFF000000) #xB4000000))

(defun a64-branch-target (word end-pos)
  (cond
    ((or (a64-bcond-word-p word) (a64-cbz-word-p word))
     (+ (- end-pos 4)
        (* 4 (a64-sign-extend (ldb (byte 19 5) word) 19))))
    ((= (logand word #xFC000000) #x14000000)
     (+ (- end-pos 4)
        (* 4 (a64-sign-extend (ldb (byte 26 0) word) 26))))
    (t nil)))

(defun a64-decode-instructions (bytes)
  "Decode fixed-width AArch64 BYTES into instruction records."
  (let ((result '()))
    (loop for pos from 0 below (length bytes) by 4
          for end = (min (+ pos 4) (length bytes))
          for word = (and (= (- end pos) 4) (a64-read-u32 bytes pos))
          do (push (make-native-peephole-inst
                    :start pos
                    :end end
                    :bytes (peephole-copy-byte-vector bytes :start pos :end end)
                    :kind (cond
                            ((and word (a64-mov-rr-word-p word)) :mov-rr)
                            ((and word (a64-cmp-zr-word-p word)) :cmp-zero)
                            ((and word (or (a64-bcond-word-p word)
                                           (a64-cbz-word-p word)
                                           (= (logand word #xFC000000) #x14000000)))
                             :branch)
                            (t nil))
                    :dst (and word (a64-mov-rr-word-p word) (a64-mov-rd word))
                    :src (and word (a64-mov-rr-word-p word) (a64-mov-rn word))
                    :branch-size (and word (a64-branch-target word end) 4)
                    :target (and word (a64-branch-target word end)))
                   result))
    (nreverse result)))

(defun a64-encode-cbz-word (rn target-pos inst-pos)
  (let ((imm19 (logand (ash (- target-pos inst-pos) -2) #x7FFFF)))
    (logior #xB4000000
            (ash imm19 5)
            (logand rn #x1F))))

(defun a64-peephole-rewrite (insts)
  "Return optimized AArch64 instruction records."
  (let ((out '())
        (rest insts))
    (loop while rest
          do (let* ((a (first rest))
                    (b (second rest)))
               (cond
                 ((and (eq (native-peephole-inst-kind a) :mov-rr)
                       (= (native-peephole-inst-dst a) (native-peephole-inst-src a)))
                  (setf rest (rest rest)))
                 ((and b
                       (eq (native-peephole-inst-kind a) :mov-rr)
                       (eq (native-peephole-inst-kind b) :mov-rr)
                       (= (native-peephole-inst-dst a) (native-peephole-inst-src b))
                       (= (native-peephole-inst-src a) (native-peephole-inst-dst b)))
                  (push a out)
                  (setf rest (cddr rest)))
                 ((and b
                       (eq (native-peephole-inst-kind a) :cmp-zero)
                       (eq (native-peephole-inst-kind b) :branch)
                       (a64-bcond-word-p (a64-read-u32 (native-peephole-inst-bytes b) 0))
                       (= (ldb (byte 4 0) (a64-read-u32 (native-peephole-inst-bytes b) 0)) 0))
                  (let* ((word (a64-read-u32 (native-peephole-inst-bytes a) 0))
                         (rn (ldb (byte 5 5) word))
                         (placeholder (peephole-byte-list-vector '(0 0 0 0))))
                    (push (native-rewrite-inst a
                                               :bytes placeholder
                                               :kind :branch
                                               :dst rn
                                               :branch-size 4
                                               :target (native-peephole-inst-target b))
                          out)
                    (setf rest (cddr rest))))
                 ((and b
                       (native-safe-identical-dedup-p a)
                       (equalp (native-peephole-inst-bytes a)
                               (native-peephole-inst-bytes b)))
                  (push a out)
                  (setf rest (cddr rest)))
                 (t
                  (push a out)
                  (setf rest (rest rest))))))
    (nreverse out)))

(defun a64-patch-branch-displacement (inst offset-map new-start new-end)
  "Patch AArch64 branch displacement in INST for its remapped target."
  (declare (ignore new-end))
  (let* ((bytes (peephole-copy-byte-vector (native-peephole-inst-bytes inst)))
         (word (a64-read-u32 bytes 0))
         (target (native-peephole-inst-target inst))
         (mapped-target (and target (<= 0 target (1- (length offset-map)))
                             (aref offset-map target))))
    (when mapped-target
      (cond
        ((and (eq (native-peephole-inst-kind inst) :branch)
              (native-peephole-inst-dst inst)
              (zerop word))
         (a64-write-u32 bytes 0
                        (a64-encode-cbz-word (native-peephole-inst-dst inst)
                                             mapped-target new-start)))
        ((or (a64-bcond-word-p word) (a64-cbz-word-p word))
         (let ((imm19 (logand (ash (- mapped-target new-start) -2) #x7FFFF)))
           (setf word (logior (logand word (lognot (ash #x7FFFF 5)))
                              (ash imm19 5)))
           (a64-write-u32 bytes 0 word)))
        ((= (logand word #xFC000000) #x14000000)
         (let ((imm26 (logand (ash (- mapped-target new-start) -2) #x3FFFFFF)))
           (setf word (logior (logand word #xFC000000) imm26))
           (a64-write-u32 bytes 0 word)))))
    bytes))

(defun aarch64-peephole-optimize (bytes)
  "Optimize emitted AArch64 machine-code BYTES and return a fresh byte vector."
  (let* ((decoded (a64-decode-instructions bytes))
         (optimized (a64-peephole-rewrite decoded)))
    (native-emit-optimized-insts optimized (length bytes)
                                :branch-patcher #'a64-patch-branch-displacement)))
