;;;; cl-ana is a Common Lisp data analysis library.
;;;; Copyright 2013-2016 Gary Hollis
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


(require 'cl-ana)
(in-package :cl-ana)

(defproject large-example "/home/ghollisjr/dop-large-example/logged-results"
  (list #'macrotrans #'branchtrans #'tabletrans #'progresstrans)
  (fixed-cache 5))

(ensure-table-binding-ops)
(ensure-table-op-expanders)
(setf *print-progress* 10)

(defun project-graph->png ()
  (dot->png (dot-compile "/home/ghollisjr/dop-large-example/graph.dot"
                         :if-exists :supersede)
            "/home/ghollisjr/dop-large-example/graph.dot"))

;;;; Need to add source data