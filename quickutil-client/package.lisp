;;;; package.lisp

(defpackage #:quickutil-client
  (:use #:cl)
  (:export #:quickload))

(unless (find-package "QUICKUTIL")
  (defpackage #:quickutil
    (:nicknames #:qtl)
    (:use #:cl)))

