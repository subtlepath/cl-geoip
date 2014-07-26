;;; Copyright (c) 2013, Nicholas E. Walker  All rights reserved.

;;; Redistribution and use in source and binary forms, with or without
;;; modification, are permitted provided that the following conditions
;;; are met:

;;;  * Redistributions of source code must retain the above copyright
;;;    notice, this list of conditions and the following disclaimer.

;;;  * Redistributions in binary form must reproduce the above
;;;    copyright notice, this list of conditions and the following
;;;    disclaimer in the documentation and/or other materials provided
;;;    with the distribution.

;;; THIS SOFTWARE IS PROVIDED BY THE AUTHOR 'AS IS' AND ANY EXPRESSED OR
;;; IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
;;; OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
;;; IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT,
;;; INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
;;; BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS
;;; OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
;;; ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR
;;; TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE
;;; USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

(in-package :geoip)

(defmacro with-xplat-mutex (m &body body)
  #+sbcl
  `(with-mutex ,m ,@body)
  #-sbcl
  `(with-lock-held ,m ,@body)
  )

(defclass geoipdb ()
  ((stream :reader db-stream)

   (type :reader db-type
         :initform +country-edition+)

   (record-length :reader record-length
                  :initform +standard-record-length+)

   (segments :reader segments
             :initform +country-begin+)

   (mutex :reader mutex :initform
          #+sbcl
          (make-mutex)
          #-sbcl
          (make-lock))))

(defstruct record
  (latitude 0.0 :type short-float)
  (longitude 0.0 :type short-float)
  (region-name "" :type string)
  (city "" :type string)
  (postal-code "" :type string)
  (country-code "XX" :type (string 2))
  (country-code-3 "XXX" :type (string 3))
  (country-name "" :type string)
  (continent "" :type string))

(defgeneric setup-segments (db))

(defmethod setup-segments ((db geoipdb))
  (with-slots (mutex stream type record-length segments) db
      (let ((orig-position (file-position stream)))
        (file-position stream (- (file-length stream) 3))
        (iter (for i to (1- +structure-info-max-size+))
              (let ((delim (make-array 3 :element-type '(unsigned-byte 8))))
                (read-sequence delim stream)
                (cond
                  ((equalp delim #(255 255 255))
                   (setf type (read-byte stream))
                   (pprint type) (terpri)
                   (cond

                     ((eql type +region-edition-rev0+)
                      (setf segments +state-begin-rev0+))

                     ((eql type +region-edition-rev1+)
                      (setf segments +state-begin-rev1+))

                     ((or (eql type +city-edition-rev0+)
                          (eql type +city-edition-rev1+)
                          (eql type +org-edition+)
                          (eql type +isp-edition+)
                          (eql type +asnum-edition+))

                      (let ((buf (make-array +segment-record-length+ :element-type '(unsigned-byte 8))))
                        (read-sequence buf stream)
                        (setf segments 0)
                        (iter (for j to (1- +segment-record-length+))
                              (incf segments (ash (elt buf j) (* j 8)))))

                      (when (or (eql type +org-edition+)
                                (eql type +isp-edition+))
                        (setf record-length +org-record-length+))))
                   (leave))
                  (t
                   (file-position stream (- (file-position stream) 4))))))
        
        (file-position stream orig-position))))

(defun load-db (filename)
  (let ((db (make-instance 'geoipdb)))
    (setf (slot-value db 'stream) (open filename
                                        :direction :input
                                        :element-type '(unsigned-byte 8)))
    (setup-segments db)
    db))


(defun ip2long (addr)
  (let ((bytes (mapcar #'parse-integer (split "\\." addr))))
    (+ (ash (first bytes) 24)
       (ash (second bytes) 16)
       (ash (third bytes) 8)
       (fourth bytes))))

(defgeneric country-start (db iplong))

(defmethod country-start ((db geoipdb) iplong)
  (with-slots (record-length mutex stream segments) db
    (let ((offset 0)
          (seek-depth (if (> (length (write-to-string iplong)) 10) 127 31)))
      (iter (for depth from seek-depth downto 0)
            (let ((buf (make-array (* 2 record-length) :element-type '(unsigned-byte 8)))
                  (x (make-array 2 :initial-element 0)))
              (with-xplat-mutex (mutex)
                (file-position stream (* 2 record-length offset))
                (read-sequence buf stream))

              (iter (for i to 1)
                    (iter (for j to (1- record-length))
                          (incf (elt x i)
                                (ash (elt buf (+ (* record-length i) j))
                                     (* j 8)))))
              (cond
                ((> (boole boole-and iplong (ash 1 depth)) 0)
                 (when (>= (elt x 1) segments)
                   (leave (elt x 1)))
                 (setf offset (elt x 1)))
                (t
                 (when (>= (elt x 0) segments)
                   (leave (elt x 0)))
                 (setf offset (elt x 0)))))
            (finally
              (throw 'error "bad database"))))))

(defgeneric get-record (db iplong))

(defmethod get-record ((db geoipdb) ip)
  (with-slots (segments mutex record-length stream) db
    (let ((country-start (country-start db (ip2long ip)))
          (buf (make-array +full-record-length+ :element-type '(unsigned-byte 8)))
          (record (make-record))
          (position 1))

      (when (eql country-start segments)
        (return-from get-record))

      (with-xplat-mutex (mutex)
        (file-position stream (+ country-start (* segments (1- (* record-length 2)))))
        (read-sequence buf stream))

      (let ((byte (elt buf 0)))
        (setf (record-country-code record) (elt +country-codes+ byte))
        (setf (record-country-code-3 record) (elt +country-codes-3+ byte))
        (setf (record-country-name record) (elt +country-names+ byte))
        (setf (record-continent record) (elt +continent-names+ byte)))

      
      (flet ((get-data ()
               (do* ((offset position (incf offset))
                     (byte (elt buf offset) (elt buf offset)))
                 ((eql byte 0)
                  (prog1
                    (octets-to-string (subseq buf position offset) :encoding +encoding+)
                    (setf position (1+ offset))))) ))

        (setf (record-region-name record) (get-data))
        (setf (record-city record) (get-data))
        (setf (record-postal-code record) (get-data)))

      (let ((latitude 0)
            (longitude 0))

        (iter (for i to 16 by 8)
              (incf latitude (ash (elt buf position) i))
              (incf position))

        (iter (for i to 16 by 8)
              (incf longitude (ash (elt buf position) i))
              (incf position))

        (setf (record-latitude record) (coerce (- (/ latitude 10000) 180) 'float))
        (setf (record-longitude record) (coerce (- (/ longitude 10000) 180) 'float)))

      record)))
