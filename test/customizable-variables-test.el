;;; customizable-variables-test.el --- Tests for the user options of arduino2-mode -*- lexical-binding: t -*-
;;
;; Copyright © 2025
;;
;; Author: Tim Wilson
;; Time-stamp: <2025-05-23 19:13:01 tdw>
;; Created: 2025-04-16


;; This file is NOT part of GNU Emacs.

;;; License:

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 3, or (at your option)
;; any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; For a full copy of the GNU General Public License
;; see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; Test that the customizable variables accept their documented values
;; (quietly) but generate a warning if set to an illegal value.

;;; Code:

(require 'ert)

(require 'arduino2-mode)

;;;; Internal functions

;; The `with-warn-as-error' macro
;;
;; This macro is a bit like an opposite of `with-demoted-errors', but
;; instead of turning errors into messages, it turns warnings into
;; errors, and thus makes `warn' a function that never returns.

(define-error 'warn-error "A warning")

(defun warn-to-error (message &rest args)
  "Like `warn', but signals a `warn-error' instead of displaying a warning."
  (signal 'warn-error (apply #'format-message message args)))

(defmacro with-stub (original-function replacement-function &rest body)
  "Replace ORIGINAL-FUNCTION with REPLACEMENT-FUNCTION, then execute BODY.

Like the arguments to `advice-add', ORIGINAL-FUNCTION should be quoted,
and REPLACEMENT-FUNCTION should be function-quoted (eg with #')."
  (declare (indent defun))
  `(progn (advice-add ,original-function :override ,replacement-function)
	  ;; Call the code.
	  (unwind-protect
	      (progn ,@body)
	    ;; Clean up by restoring `warn'.
	    (advice-remove ,original-function ,replacement-function))))

(defmacro with-warn-as-error (&rest body)
  "Like `progn', but any call to `warn' signals a warn-error."
  `(with-stub 'warn #'warn-to-error ,@body))

(defmacro customizable-variable-test (name option values &optional bad-values)
  "Define test NAME of customizable variable OPTION which takes VALUES.

Define a test that assigns to user OPTION (with `setopt') in turn:
1. Its default value.
2. Each value from the list VALUES.
3. Each value from the list BAD-VALUES, 
   which should cause a type-check warning."
  
  (declare (indent defun))
  `(ert-deftest ,name ()
     ;; TODO: Would be nice to make docstring include ,name or ,option,
     ;; but I'm not sure if that's possible.
     "Test values accepted by a customizable variable."

     (let (,option)
       ;; Sanity check
       (should (custom-variable-p ',option))
       (with-warn-as-error

	;; Check default value.

	(let ((default-value (default-value ',option)))
	  (should (eq (setopt ,option default-value)
		      default-value)))
     
	;; Check example(s) of documented values.

	(mapc (lambda (value)
		(should (eq (setopt ,option value)
			    ,option)))
	      ,values)
	  
	;; Check n example(s) outwith documented values.

	(unless (null ,bad-values)
	  (mapc (lambda (bad-value)
		  (should-error (eq (setopt ,option bad-value)
				    ,option)
				:type 'warn-error))
		,bad-values))))))


;;;; The tests

;;;;; arduino2-mode-keymap-prefix - no tests

;;;;; Test arduino2-default-fqbn

;; Simple FQBNs have the format <vendor>:<architecture>:<board-id> but
;; the full syntax is more complicated, and arduino2-mode simply
;; passes the value to arduino2.

(customizable-variable-test
  arduino2-default-fqbn-test arduino2-default-fqbn 
  '("vendor:architecture:board_id") '(1))

;;;;; Test arduino2-default-port

;; This is a string that is an "Upload port address, e.g.: COM3 or
;; /dev/ttyACM2" (according to arduino2 help message).

(customizable-variable-test
  arduino2-default-port-test arduino2-default-port 
  '("/dev/ttyACM2" "COM3") '(1))

;;;;; Test arduino2-verify (a boolean)

(customizable-variable-test
  arduino2-verify-test arduino2-verify '(nil t))

;;;;; Test arduino2-warnings (one of a number of documented symbols)

(customizable-variable-test
 arduino2-warnings-test arduino2-warnings '(nil default more all) '(1))

;;;;; Test arduino2-verbosity (one of a number of documented symbols)

(customizable-variable-test
 arduino2-verbosity-test arduino2-verbosity '(nil quiet verbose) '(1))

;;;;; Test arduino2-compile-only-verbosity (a boolean)

(customizable-variable-test
  arduino2-compile-only-verbosity-test arduino2-compile-only-verbosity 
  '(nil t))

;;;;; Test arduino-compile-colour (a boolean)

(customizable-variable-test
  arduino2-compile-color-test arduino2-compile-color '(nil t))

;; customizable-variables-test.el ends here
