(in-package :cl-cc/codegen-native/lowering)

;;; Shared support for post-emit native peephole passes. Target-specific
;;; decoders and branch patchers remain in their owning target features.

(defstruct native-peephole-inst
  start
  end
  bytes
  kind
  dst
  src
  branch-size
  target)

(defun native-rewrite-inst (inst &key (bytes nil bytes-p)
                                      (kind nil kind-p)
                                      (dst nil dst-p)
                                      (src nil src-p)
                                      (branch-size nil branch-size-p)
                                      (target nil target-p))
  "Return a copy of INST with supplied slots replaced."
  (let ((copy (copy-native-peephole-inst inst)))
    (when bytes-p (setf (native-peephole-inst-bytes copy) bytes))
    (when kind-p (setf (native-peephole-inst-kind copy) kind))
    (when dst-p (setf (native-peephole-inst-dst copy) dst))
    (when src-p (setf (native-peephole-inst-src copy) src))
    (when branch-size-p (setf (native-peephole-inst-branch-size copy) branch-size))
    (when target-p (setf (native-peephole-inst-target copy) target))
    copy))

(defun peephole-copy-byte-vector (bytes &key (start 0) end)
  "Return a fresh unsigned-byte vector copied from BYTES."
  (let* ((limit (or end (length bytes)))
         (out (make-array (- limit start) :element-type '(unsigned-byte 8))))
    (loop for i from start below limit
          for j from 0
          do (setf (aref out j) (aref bytes i)))
    out))

(defun peephole-byte-list-vector (bytes)
  "Return an unsigned-byte vector containing BYTES."
  (coerce bytes '(simple-array (unsigned-byte 8) (*))))

(defun native-safe-identical-dedup-p (inst)
  "Return true when adjacent duplicate INST is semantically idempotent."
  (member (native-peephole-inst-kind inst) '(:mov-rr :cmp-rr :test-rr :nop)
          :test #'eq))

(defun native-build-offset-map (original-length insts)
  "Map every original byte position to its new byte position after INSTS."
  (let ((map (make-array (1+ original-length) :initial-element 0))
        (new-pos 0)
        (old-pos 0))
    (dolist (inst insts)
      (loop while (< old-pos (native-peephole-inst-start inst))
            do (progn (setf (aref map old-pos) new-pos)
                      (incf old-pos)))
      (loop while (<= old-pos (native-peephole-inst-start inst))
            do (progn (setf (aref map old-pos) new-pos)
                      (incf old-pos)))
      (incf new-pos (length (native-peephole-inst-bytes inst))))
    (loop while (<= old-pos original-length)
          do (progn (setf (aref map old-pos) new-pos)
                    (incf old-pos)))
    map))

(defun native-emit-optimized-insts (insts original-length &key branch-patcher)
  "Emit optimized INSTS to a byte vector, patching relative branches when needed."
  (let* ((offset-map (native-build-offset-map original-length insts))
         (out '())
         (new-pos 0))
    (dolist (inst insts)
      (let* ((bytes (if (and branch-patcher (native-peephole-inst-branch-size inst))
                        (funcall branch-patcher inst offset-map new-pos
                                 (+ new-pos (length (native-peephole-inst-bytes inst))))
                        (native-peephole-inst-bytes inst))))
        (loop for i from 0 below (length bytes)
              do (push (aref bytes i) out))
        (incf new-pos (length bytes))))
    (peephole-byte-list-vector (nreverse out))))
