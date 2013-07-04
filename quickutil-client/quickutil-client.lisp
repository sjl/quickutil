;;;; quickutil-client.lisp
;;;; Copyright (c) 2012-2013 Robert Smith

(in-package #:quickutil-client)

;;;; Client functions, including the public API, which handles the
;;;; loading of utilities.
;;;;
;;;; Convention in this file: If a function name ends in an asterisk,
;;;; then it takes a list as an argument. The same function without
;;;; the asterisk takes &REST arguments.

(defun qtl-utl (symbol)
  (intern (symbol-name symbol) :quickutil-utilities))

(defmacro funcall-qtl-utl (function &rest args)
  `(funcall (intern (symbol-name ',function) :quickutil-utilities) ,@args))

(defun utils (&rest util-names)
  (prog2
      (quickutil-client-management:load-quickutil-utilities)
      (load
       (compile-file
        (with-temp-file stream file
          (write-string
           (funcall-qtl-utl emit-utility-code :utilities util-names)
           stream))))
    (quickutil-client-management:unload-quickutil-utilities)))

;;; XXX FIXME: This could use improved error handling.
(defun who-provides (symbol)
  "Which utility provides the symbol SYMBOL?"
  (assert (or (symbolp symbol)
              (stringp symbol)))
  (flet ((autoload-lookup (symbol)
           (let* ((autoload-url (reverse-lookup-url symbol))
                  (str (download-url-string autoload-url)))
             (if (string-equal "NIL" str)
                 (error "Could not find originating utility for symbol: ~A"
                        (symbol-name symbol))
                 str))))
    (let ((who (ignore-errors (autoload-lookup (if (symbolp symbol)
                                                   symbol
                                                   (make-symbol symbol))))))
      (nth-value 0 (and who (intern who '#:keyword))))))

(defun category-utilities (category-names)
  "Query for the symbols in the categories CATEGORY-NAMES."
  (flet ((category-syms (category-name)
           (let ((str (ignore-errors (download-url-string (category-url category-name)))))
             (if (null str)
                 nil
                 (nth-value 0 (read-from-string str))))))
    (loop :for category :in category-names
          :append (category-syms category) :into symbols
          :finally (return (remove-duplicates symbols)))))

(defun symbol-utilities (symbols)
  (remove nil (remove-duplicates (mapcar #'who-provides symbols))))

(defun query-needed-utilities (&key utilities categories symbols)
  (remove-duplicates
   (append utilities
           (category-utilities categories)
           (symbol-utilities symbols))))

;;; XXX: Just use SAVE-UTILS-AS to a temp file?
(defun utilize (&key utilities categories symbols (package "QUICKUTIL"))
  (unless (find-package package)
    (error "The package ~S must exist in order to utilize utilities." package))
  
  (let ((file-contents (download-url-string
                        (quickutil-query-url
                         (query-needed-utilities :utilities utilities
                                                 :categories categories
                                                 :symbols symbols)))))
    (load
     (compile-file
      (with-temp-file stream file
        (format stream "(in-package ~S)~%~%" package)
        (write-string file-contents stream))))))

(defun utilize-utilities (utilities &key (package "QUICKUTIL"))
  "Load the utilities UTILITIES and their dependencies into the
package named PACKAGE."
  (utilize :utilities utilities :package package))

(defun utilize-categories (categories &key (package "QUICKUTIL"))
  "Load the utilities in the categories CATEGORIES into the package
named PACKAGE."
  (utilize :categories categories :package package))

(defun utilize-symbols (symbols &key (package "QUICKUTIL"))
  "Load the utilities which provide the symbols SYMBOLS into the
package named PACKAGE."
  (utilize :symbols symbols :package package))

(defun print-lines (stream &rest strings)
  "Print the lines denoted by the strings STRINGS to the stream
STREAM."
  (dolist (string strings)
    (when string
      (write-string string stream)
      (terpri stream))))

(defun ensure-keyword-list (list)
  "Ensure that LIST is a list of keywords."
  (if (listp list)
      (mapcar #'(lambda (symb)
                  (intern (symbol-name symb) '#:keyword))
              list)
      (ensure-keyword-list (list list))))

(defun save-utils-as (filename &key utilities categories symbols
                                    (package "QUICKUTIL" package-given-p)
                                    (package-nickname nil)
                                    (ensure-package t))
  "Save all of the utilities specified by the lists UTILITIES,
CATEGORIES, and SYMBOLS to the file named FILENAME.

The utilities will be put in the package named PACKAGE. If
ENSURE-PACKAGE is true, then the package will be created if it has not
already. If it has not been created, the package will be given the
nickname PACKAGE-NICKNAME. If the nickname is NIL, then no nickname
will be created."
  (with-open-file (file filename :direction :output
                                 :if-exists :supersede
                                 :if-does-not-exist :create)
    (let ((file-contents (download-url-string
                          (quickutil-query-url
                           (query-needed-utilities :utilities utilities
                                                   :categories categories
                                                   :symbols symbols)))))
      ;; Header
      (print-lines file
                   ";;;; This file was automatically generated by Quickutil."
                   ";;;; See http://quickutil.org for details."
                   ""
                   ";;;; To regenerate:")
      (let ((*print-pretty* nil))
        (format file
                ";;;; (qtlc:save-utils-as ~S~@[ :utilities '~S~]~@[ :categories '~S~]~@[ :symbols '~S~] :ensure-package ~S :package ~S~@[ :package-nickname ~S~])~%~%"
                filename
                (ensure-keyword-list utilities)
                (ensure-keyword-list categories)
                (ensure-keyword-list symbols)
                ensure-package
                package
                (cond
                  (package-nickname package-nickname)
                  (package-given-p nil)
                  (t "QTL"))))
      
      ;; Package definition
      (when ensure-package
        (print-lines file
                     ;; Package Definition
                     "(eval-when (:compile-toplevel :load-toplevel :execute)"
                     (format nil "  (unless (find-package ~S)" package)
                     (format nil "    (defpackage ~S" package)
                     "      (:documentation \"Package that contains Quickutil utility functions.\")"
                     (when (or package-nickname (not package-given-p))
                       (format nil "      (:nicknames ~S)"
                               (cond
                                 (package-nickname package-nickname)
                                 (package-given-p nil)
                                 (t "QTL"))))
                     "      (:use #:cl))))"
                     ""))
      
      (print-lines file
                   ;; IN-PACKAGE form
                   (format nil "(in-package ~S)" package)
                   ""
                   
                   ;; Code
                   file-contents
                   ""
                   
                   ;; End of file
                   (format nil ";;;; END OF ~A ;;;;" filename))

      ;; Return the pathname
      (pathname filename))))
