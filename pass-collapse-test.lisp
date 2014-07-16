(in-package :makeres-tabletrans)

(in-project pass-collapse)

(settrans (pass-collapse pass-merge))

(defres source
  (wrap-for-reuse
   (open-plist-table '((:x 1)
                       (:x 2)
                       (:x 3)))))

(defres filtered
  (ltab (res source)
      ()
    (when (< (field x) 4)
      ;; you only have to add new fields, all source
      ;; fields not shadowed are still available:
      (push-fields
       ;; new field y, x is still accessible, unshadowed
       (y (* 2 (field x)))))))

(defres filtered2
  (ltab (res source)
      ()
    (when (< (field x) 5)
      (push-fields
       ;; shadow field x:
       (x (sqrt (field x)))
       ;; new field y:
       (y (field x))))))

(defres canon
  (tab (res filtered)
      (hdf-opener "/home/ghollisjr/canon.h5"
                  '(("x" . :int)
                    ("y" . :float)
                    ("z" . :float)))
      ()
    (push-fields (x (field x))
                 (y (sqrt (field y)))
                 (z (float
                     (expt (field y)
                           2))))))

(defres (canon (sum x))
  (dotab (res canon)
      ((sum 0))
      sum
    (incf sum (field x))))

(defres (filter canon)
  (ltab (res canon)
      ()
    (when (< (field x)
             (res (canon (sum x))))
      (push-fields
       (x (field x))))))

(defres (filter source)
  (ltab (res source)
      ()
    (when (< (field x)
             (res (canon (sum x))))
      (push-fields
       (x (field x))))))

(defres other
  (tab (res filtered2)
      (hdf-opener "/home/ghollisjr/other.h5"
                  '(("x" . :int)))
      ()
    (push-fields
     (x (field y)))))
