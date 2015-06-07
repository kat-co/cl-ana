;;;; cl-ana is a Common Lisp data analysis library.
;;;; Copyright 2013, 2014 Gary Hollis
;;;;
;;;; This file is part of cl-ana.
;;;;
;;;; cl-ana is free software: you can redistribute it and/or modify it
;;;; under the terms of the GNU General Public License as published by
;;;; the Free Software Foundation, either version 3 of the License, or
;;;; (at your option) any later version.
;;;;
;;;; cl-ana is distributed in the hope that it will be useful, but
;;;; WITHOUT ANY WARRANTY; without even the implied warranty of
;;;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;;;; General Public License for more details.
;;;;
;;;; You should have received a copy of the GNU General Public License
;;;; along with cl-ana.  If not, see <http://www.gnu.org/licenses/>.
;;;;
;;;; You may contact Gary Hollis (me!) via email at
;;;; ghollisjr@gmail.com

(in-package :cl-ana.serialization)

(defparameter *histogram-data-path* "data")

(defparameter *histogram-bin-spec-path* "bin-specs")

(defun ->double-float (x)
  (float x 0d0))

(defun write-histogram (histogram file hdf-path)
  "Writes histogram to file.  Supports histogram count values with
errors as well as simple numerical values.

Note that this function assumes that either all the dimensions have
names or none of them do."
  (hdf-mkgroup file hdf-path)
  (flet ((subpath (path)
           (concatenate 'string
                        hdf-path
                        "/"
                        path)))
    (let* ((raw-data (hist-bin-values histogram))
           (errors? (typep (first (first raw-data))
                           'err-num))
           (data (if (not errors?)
                     raw-data
                     (mapcar (lambda (datum)
                               (destructuring-bind (count &rest xs) datum
                                 (list* (err-num-value count)
                                        (err-num-error count)
                                        xs)))
                             raw-data)))
           (data-names-specs
            ;; had to change this to double-float to allow for
            ;; normalized histograms etc.
            (append (if errors?
                        (list (cons "count" :double)
                              (cons "count-error" :double))
                        (list (cons "count" :double)))
                    (loop
                       for i from 0
                       for n in (hist-dim-names histogram)
                       collect (cons (if n
                                         n
                                         (with-output-to-string (s)
                                           (format s "x~a" i)))
                                     :double))))
           (data-table-path
            (subpath *histogram-data-path*))
           (data-table (create-hdf-table
                        file data-table-path data-names-specs))
           (data-field-symbols (table-field-symbols data-table))
           (hist-dim-specs
            (let ((result (hist-dim-specs histogram)))
              (loop
                 for plist in result
                 for i from 0
                 do (when (not (getf plist :name))
                      (setf (getf plist :name)
                            (with-output-to-string (s)
                              (format s "x~a" i)))))
              result))
           (bin-spec-table-path (subpath *histogram-bin-spec-path*))
           (max-string-length
            (loop
               for plist in hist-dim-specs
               maximizing (length (getf plist :name))))
           (bin-spec-names-specs
            (list (cons "name" (list :array :char max-string-length))
                  (cons "name-length" :int)
                  (cons "nbins" :int)
                  (cons "low" :double)
                  (cons "high" :double)))
           (bin-spec-table (create-hdf-table
                            file bin-spec-table-path
                            bin-spec-names-specs)))
      ;; write data table
      (loop
         for datum in data
         do (progn
              (loop
                 for i from 0
                 for field in datum
                 for sym in data-field-symbols
                 do (table-set-field data-table sym
                                     (->double-float field)))
              (table-commit-row data-table)))
      (table-close data-table)
      ;; write bin-spec table
      ;; fix plists
      (loop
         for plist in hist-dim-specs
         for i from 0
         do (when (not (getf plist :name))
              (setf (getf plist :name)
                    (with-output-to-string (s)
                      (format s "x~a" i)))))
      (loop
         for plist in hist-dim-specs
         do (progn
              (table-push-fields bin-spec-table
                (|name| (getf plist :name))
                (|name-length| (length (getf plist :name)))
                (|nbins| (getf plist :nbins))
                (|low| (->double-float (getf plist :low)))
                (|high| (->double-float (getf plist :high))))))
      (table-close bin-spec-table))))

;; new version which uses raw HDF5 functions
(defun new-read-histogram (file hdf-path &optional (type :sparse))
  "Reads a histogram from an hdf-table with file and path.

type can be either :contiguous or :sparse for contiguous-histogram and
sparse-histogram respectively."
  (flet ((subpath (path)
           (concatenate 'string
                        hdf-path
                        "/"
                        path)))
    (let* ((binspec-path
            (subpath *histogram-bin-spec-path*))
           (binspec-dataset
            (h5dopen2 file binspec-path +H5P-DEFAULT+))
           (binspec-datatype
            (h5dget-type binspec-dataset))
           (binspec-dataspace
            (h5dget-space binspec-dataset))
           (data-path
            (subpath *histogram-data-path*))
           (data-dataset
            (h5dopen2 file data-path +H5P-DEFAULT+))
           (data-datatype
            (h5dget-type data-dataset))
           (data-dataspace
            (h5dget-space data-dataset))

           binspec-chunk-size
           nrows
           ndims

           binspec-row-size
           binspec-buffer-size
           binspecs

           memspace)
      (with-foreign-objects ((binspec-dataset-dims 'hsize-t)
                             (binspec-chunk-dims 'hsize-t)
                             (binspec-name-dims 'hsize-t)
                             (data-dataset-dims 'hsize-t)
                             (data-chunk-dims 'hsize-t)
                             (memspace-dims 'hsize-t)
                             (memspace-maxdims 'hsize-t))
        (let ((create-plist
               (h5dget-create-plist binspec-dataset)))
          (h5pget-chunk create-plist 1 binspec-chunk-dims))
        (setf binspec-chunk-size
              (mem-aref binspec-chunk-dims 'hsize-t))
        (h5sget-simple-extent-dims binspec-dataspace
                                   binspec-dataset-dims
                                   0)
        (setf ndims
              (mem-aref binspec-dataset-dims 'hsize-t))
        (h5tget-array-dims2 (h5tget-member-type binspec-datatype
                                                0)
                            binspec-name-dims)

        (setf binspec-row-size
              (h5tget-size binspec-datatype))
        (setf binspec-buffer-size
              (* binspec-chunk-size binspec-row-size))
        (with-foreign-object (buffer :char binspec-buffer-size)
          (loop
             for chunk-index from 0
             while (< (* chunk-index binspec-buffer-size)
                      ndims)
             do
               (let ((remaining-rows
                      (- ndims
                         (* chunk-index binspec-chunk-size))))
                 (if (< remaining-rows binspec-chunk-size)
                     (setf (mem-aref memspace-dims 'hsize-t 0)
                           remaining-rows)
                     (setf (mem-aref memspace-dims 'hsize-t 0)
                           binspec-chunk-size)))
               (setf (mem-aref memspace-maxdims 'hsize-t)
                     (mem-aref memspace-dims 'hsize-t))
               (with-foreign-objects ((start 'hsize-t)
                                      (stride 'hsize-t)
                                      (cnt 'hsize-t)
                                      (blck 'hsize-t))
                 (setf (mem-aref start 'hsize-t)
                       (* chunk-index
                          binspec-chunk-size))
                 (setf (mem-aref stride 'hsize-t)
                       1)
                 (setf (mem-aref cnt 'hsize-t)
                       1)
                 (setf (mem-aref blck 'hsize-t)
                       (mem-aref memspace-dims 'hsize-t))
                 (h5sselect-hyperslab binspec-dataspace
                                      :H5S-SELECT-SET
                                      start
                                      stride
                                      cnt
                                      blck)
                 (setf memspace
                       (h5screate-simple 1 memspace-dims memspace-maxdims))
                 (h5dread binspec-dataset
                          binspec-datatype
                          memspace
                          binspec-dataspace
                          +H5P-DEFAULT+
                          buffer)
                 (loop
                    for i from 0 below (mem-aref memspace-dims 'hsize-t)
                    do (let ((buffer-index
                              (+ (* i binspec-row-size)
                                 (* binspec-chunk-size chunk-index))))


                         )))))
                      
          
        ))))

(defun read-histogram (file hdf-path &optional (type :sparse))
  "Reads a histogram from an hdf-table with file and path.

type can be either :contiguous or :sparse for contiguous-histogram and
sparse-histogram respectively."
  (flet ((subpath (path)
           (concatenate 'string
                        hdf-path
                        "/"
                        path)))
    (let* ((bin-spec-table
            (open-hdf-table file
                            (subpath *histogram-bin-spec-path*)))
           (bin-spec-table-field-names
            (list "name" "name-length" "low" "high" "nbins"))
           (hist-dim-specs
            (let ((result ()))
              (table-reduce bin-spec-table
                            bin-spec-table-field-names
                            (lambda (state name name-length low high nbins)
                              (push (list :name (char-vector->string name name-length)
                                          :low low
                                          :high high
                                          :nbins nbins)
                                    result)))
              (nreverse result)))
           (histogram
            (cond
              ((equal type :contiguous)
               (make-contiguous-hist hist-dim-specs))
              ((equal type :sparse)
               (make-sparse-hist hist-dim-specs))
              (t (error "Must specify :contiguous or :sparse for
              type."))))
           (data-table
            (open-hdf-table file
                            (subpath *histogram-data-path*)))
           (data-table-field-names
            (table-field-names data-table)))
      (if (equal (second data-table-field-names)
                 "count-error")
          (table-reduce data-table
                        data-table-field-names
                        (lambda (state count count-error &rest xs)
                          (hist-insert histogram xs
                                       (+- count count-error))))
          (table-reduce data-table
                        data-table-field-names
                        (lambda (state count &rest xs)
                          (hist-insert histogram xs count))))
      (table-close bin-spec-table)
      (table-close data-table)
      histogram)))
