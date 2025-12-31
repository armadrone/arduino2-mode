;;; arduino2-mode.el --- Major mode for editing Arduino code -*- lexical-binding: t -*-

;; Copyright © 2008  Christopher Grim, 2019  Love Lagerkvist, 2026  Armadrone LLC

;; Authors: Christopher Grim <christopher.grim@gmail.com>, Love Lagerkvist, Armadrone Software Development Team <info@armadrone.com>
;; URL: https://github.com/armadrone/arduino2-mode
;; Version: 202601
;; Package-Requires: ((emacs "29.1"))
;; Created: 2026-01-11
;; Keywords: processes tools

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

;; arduino2-mode is an Emacs major mode for using Arduino IDE v.2.X.X
;; features, like the excellent new Arduino command line interface
;; in an Emacs-native fashion.  The mode is integrated with
;; Arduino IDE v.2.X.X and arduino-cli command line interface
;; covers the full range of arduino-ide and arduino-cli features
;; in an Emacs native fashion.  The mode leverages the infinite power
;; the GNU to provide fussy-finding of libraries and much improved
;; support for handling multiple boards.  The commands that originally
;; require multiple steps (such as first searching for a library
;; and then separately installing it) have been folded into one.
;;
;; For more information on the package and default board behavior,
;; see the README at https://github.com/armadrone/arduino2-mode
;;
;; For more information on arduino v.2.X.X itself,
;; see https://github.com/arduino/arduino-ide
;; and https://github.com/arduino/arduino-cli
;;
;; Tested against arduino-2.3.6 and arduino-cli = 1.3.1

;;; Code:

(require 'compile)
(require 'spinner)
(require 'json)
(require 'map)
(require 'seq)
(require 'subr-x)

(eval-when-compile
  (require 'cl-lib)
  (require 'cc-langs)
  (require 'cc-fonts)
  (require 'cc-menus)
  ;; (require 'term)
  )

(eval-and-compile
  ;; fall back on c-mode
  (c-add-language 'arduino2-mode 'c-mode))

;;;
;;; Customization
;;;
(defgroup arduino2 nil
  "Functions and settings for arduino2-mode."
  :group  'tools
  :prefix "arduino2-"
  :link   '(url-link https://github.com/armadrone/arduino2-mode))

(defcustom arduino2-mode-keymap-prefix (kbd "C-c C-a")
  "Keymap prefix for arduino2-mode."
  :group 'arduino2
  :type  'string)

(defcustom arduino2-message-display-method 'window
  "Method of messags display."
  :group 'arduino2
  :type '(choice
          (const :tag "Tooltip" tooltip)
          (const :tag "Bottom window" window)
          (const :tag "Minibuffer" minibuffer)))

(defcustom arduino2-mode-home "~/Arduino"
  "The path of ARDUINO_HOME."
  :group 'arduino2
  :type 'directory)

(defcustom arduino2-default-bin "~/bin"
  "The path of default bin directory for Arduino IDE and CLI."
  :group 'arduino2
  :type 'directory)

;; arduino2-default-fqbn and arduino2-default-port may be useful
;; as file local variables but are not ":safe" because (if used) their
;; values are passed to the shell as part of an arduino2 command
;; line.

;; Simple FQBNs have the format <vendor>:<architecture>:<board-id> but
;; the full syntax is more complicated, and arduino2-mode simply
;; passes the value to arduino2 without parsing it in any way.

(defcustom arduino2-default-fqbn nil
  "Default fqbn to use if board selection fails."
  :group 'arduino2
  :type  '(choice
           (const :tag "No default (error message if board selection fails)"
                  nil)
           (string :tag "Fully qualified board name")))

(defvar arduino2-current-port nil
  "Currently used port to connect to arduino board.
This variable used as a key reference to arduino2-existing-boards hash")

(defcustom arduino2-verify nil
  "Non-nil means verify uploaded binary after the upload."
  :group 'arduino2
  :type  'boolean)

(defcustom arduino2-warnings nil
  "Set GCC warning level, can be nil (none), `default', `more' or `all'."
  :group 'arduino2
  :type  '(choice (const :tag "--warnings default" default)
		              (const :tag "--warnings more" more)
		              (const :tag "--warnings all" all)
		              (const :tag "No warnings flag; default level is \"none\"" nil)))

(defcustom arduino2-verbosity nil
  "The verbosity flags (if any) to pass to arduino2 commands.

`quiet' passes --quiet to applicable arduino2 commands
(otherwise ignored).

`verbose' passes --verbose to arduino2 compile commands,
or all commands if arduino2-compile-only-verbosity is set to nil."
  :group 'arduino2
  :type  '(choice (const :tag "Quiet" quiet)
		              (const :tag "Verbose" verbose)
		              (const :tag "None" nil)))

(defcustom arduino2-compile-only-verbosity t
  "Non-nil (default) means only apply verbosity setting to compilation."
  :group 'arduino2
  :type 'boolean)

(defcustom arduino2-compile-color t
  "Non-nil (default) means apply ANSI colors from compilation output."
  :group 'arduino2
  :type 'boolean)

(defcustom arduino2-ide-executable "arduino-ide"
  "The Arduino IDE program executable name."
  :group 'arduino2
  :type 'string)

(defcustom arduino2-ide-download-url "https://downloads.arduino.cc/arduino-ide/arduino-ide_2.3.7_Linux_64bit.AppImage"
  "The Arduino IDE download URL."
  :group 'arduino2
  :type 'string)

(defcustom arduino2-cli-executable "arduino-cli"
  "The Arduino CLI program executable name."
  :group 'arduino2
  :type 'string)

(defcustom arduino2-cli-download-url "https://raw.githubusercontent.com/arduino/arduino-cli/master/install.sh"
  "The Arduino CLI download URL."
  :group 'arduino2
  :type 'string)

(defcustom arduino2-spinner-type 'progress-bar
  "The spinner type for arduino2 processes.

Value is a symbol.  The possible values are the symbols in the
`spinner-types' variable."
  :group 'arduino2
  :type 'symbol
  :safe #'symbolp)

(defcustom arduino2-font-lock-extra-types nil
  "List of extra types (aside from type keywords) to recognize in Arduino2 mode.
Each list item should be a regexp matching a single identifier."
  :group 'arduino2
  :type 'list)

;;;
;;; Language-Specific Definitions
;;;
(c-lang-defconst c-primitive-type-kwds
  arduino2 (append '(;; Data Types
                     "boolean" "byte"
                     "int" "long" "short" "double" "float"
                     "char" "string"
                     "unsigned char" "unsigned int" "unsigned long"
                     "void" "word"
                     ;; Variable Scope & Qualifiers
                     "const" "scope" "static" "volatile"
                     ;; Structure
                     ;; Sketch
                     "loop" "setup"
                     ;; Control Structure
                     "break" "continue" "do" "while" "else" "for" "goto" "if"
                     "return" "switch" "case"
                     ;; Utilities
                     "PROGMEM")
                   (c-lang-const c-primitive-type-kwds)))

(c-lang-defconst c-constant-kwds
  arduino2 (append
            '("HIGH" "LOW"
              "INPUT" "OUTPUT" "INPUT_PULLUP"
              "LED_BUILTIN"
              "true" "false")
            (c-lang-const c-constant-kwds)))

(c-lang-defconst c-simple-stmt-kwds
  arduino2 (append
            '(;; Operator Utilities
              "sizeof"
              ;; Functions
              "pinMode" "digitalWrite" "digitalRead"                              ; Digital I/O
              "analogReference" "analogRead" "analogWrite"                        ; Analog I/O
              "analogReadResolution" "analogWriteResolution"                      ; Zero, Due & MKR Family
              "tone" "noTone" "shiftIn" "shiftOut" "pulseIn" "pulseInLong"        ; Advanced I/O
              "millis" "micros" "delay" "delayMicroseconds"                       ; Time
              "min" "max" "abs" "constrain" "map" "pow" "sq" "sqrt"               ; Math
              "sin" "cos" "tan"                                                   ; Trigonometry
              "randomSeed" "random"                                               ; Random Numbers
              "bit" "bitRead" "bitWrite" "bitSet" "bitClear" "lowByte" "highByte" ; Bits and Bytes
              "attachInterrupt" "detachInterrupt"                                 ; External Interrupts
              "interrupts" "noInterrupts"                                         ; Interrupts
              "serial" "stream"                                                   ; Serial Communication
              ;; Characters
              "isAlpha" "isAlphaNumeric"
              "isAscii" "isControl" "isDigit" "isGraph" "isHexadecimalDigit"
              "isLowerCase" "isUpperCase"
              "isPrintable" "isPunct" "isSpace" "isWhitespace"
              ;; USB Devices like Keyboard functions
              "print" "println"
              ;; Serial
              "begin" "end" "available" "read" "flush"  "peek"
              ;; Keyboard
              "write" "press" "release" "releaseAll"
              ;; Mouse
              "click" "move" "isPressed")
            (c-lang-const c-simple-stmt-kwds)))

(c-lang-defconst c-primary-expr-kwds
  arduino2 (append
            '(;; Communication
              "Serial"
              ;; USB (Leonoardo based boards and Due only)
              "Keyboard"
              "Mouse")
            (c-lang-const c-primary-expr-kwds)))

;;;
;;; Internal constants and C-syntax tables
;;;
(defconst arduino2-font-lock-keywords-1 (c-lang-const c-matchers-1 arduino2)
  "Minimal highlighting for Arduino mode.")

(defconst arduino2-font-lock-keywords-2 (c-lang-const c-matchers-2 arduino2)
  "Fast normal highlighting for Arduino mode.")

(defconst arduino2-font-lock-keywords-3 (c-lang-const c-matchers-3 arduino2)
  "Accurate normal highlighting for Arduino mode.")

(defvar arduino2-font-lock-keywords arduino2-font-lock-keywords-3
  "Default expressions to highlight in ARDUINO mode.")

(defvar arduino2-mode-syntax-table nil
  "Syntax table used in arduino-mode buffers.")

(or arduino2-mode-syntax-table
    (setq arduino2-mode-syntax-table (make-syntax-table c-mode-syntax-table)))

(defvar arduino2-mode-abbrev-table nil
  "Abbreviation table used in arduino-mode buffers.")

(c-define-abbrev-table 'arduino2-mode-abbrev-table
  ;; Keywords that if they occur first on a line might alter the
  ;; syntactic context, and which therefore should trigger
  ;; reindentation when they are completed.
  '(("else" "else" c-electric-continued-statement 0)
    ("while" "while" c-electric-continued-statement 0)))

(defvar arduino2-existing-boards (make-hash-table :test 'equal)
  "Hash of detected or manually defined arduino boards in format:
`board-port -> (list \"board-fqbn\" \"board-name\" \"board-protocol\")'")

;;;
;;; Internal functions
;;;
(defun arduino2--compilation-filter ()
  "Filter function for applying ANSI colors in compilation output."
  (when arduino2-compile-color
    (ansi-color-apply-on-region compilation-filter-start (point-max))))

(define-compilation-mode arduino2-compilation-mode "arduino2-compilation"
  "arduino2 specific `compilation-mode' derivative."
  (setq-local compilation-scroll-output t)
  (require 'ansi-color)
  (add-hook 'compilation-filter-hook #'arduino2--compilation-filter))

(defun arduino2--?map-put (m v k)
  "Puts V in M under K when V, else return M."
  (if v (setf (map-elt m k) v)) m)

(defun arduino2--verify ()
  "Get verify bool."
  (when arduino2-verify " -t"))

(defun arduino2--verbosity ()
  "Get the current verbosity level."
  (pcase arduino2-verbosity
    ('quiet   " --quiet")
    ('verbose " --verbose")))

(defun arduino2--warnings ()
  "Get the current warnings level."
  (when arduino2-warnings
    (concat " --warnings " (symbol-name arduino2-warnings))))

(defun arduino2--compile-color ()
  "Get the current compilation color setting."
  (when (not arduino2-compile-color)
    " --no-color"))

(defun arduino2--general-flags ()
  "Add flags to CMD, if set."
  (concat (unless arduino2-compile-only-verbosity
            (arduino2--verbosity))))

(defun arduino2--compile-flags ()
  "Add flags to CMD, if set."
  (concat (arduino2--verify)
          (arduino2--warnings)
          (arduino2--verbosity)
          (arduino2--compile-color)))

(defun arduino2--add-flags (mode cmd)
  "Add general and MODE flags to CMD, if set."
  (concat cmd (pcase mode
                ('compile (arduino2--compile-flags))
                (_        (arduino2--general-flags)))))

(defun arduino2--compile (cmd)
  "Run arduino2 CMD in 'arduino2-compilation-mode."
  (let* ((arduino2-exec-path (expand-file-name arduino2-cli-executable arduino2-default-bin))
         (cmd2 (concat arduino2-exec-path " " cmd " " (shell-quote-argument (expand-file-name default-directory))))
         (cmd* (arduino2--add-flags 'compile cmd2)))
    (save-some-buffers (not compilation-ask-about-save) (lambda () default-directory))
    (setf arduino2--compilation-buffer
          (compilation-start cmd* 'arduino2-compilation-mode))))

(defun arduino2--ide-open (sketch)
  "Open SKETCH with Arduino IDE in 'arduino2-compilation-mode."
  (let* ((arduino2-exec-path (expand-file-name arduino2-ide-executable arduino2-default-bin))
         (cmd  (concat arduino2-exec-path " " sketch)))
    (save-some-buffers (not compilation-ask-about-save) (lambda () default-directory))
    (setf arduino2--compilation-buffer
          (compilation-start cmd 'arduino2-compilation-mode))))

(defun arduino2--temp-buffer-show (msg)
  "Display MSG message in separate temporary buffer."
  (let ((buf (get-buffer-create "*arduino2-popup*")))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (concat msg "\n\nPress q to close"))
        (special-mode)))
    (display-buffer
     buf
     '((display-buffer-at-bottom)
       (window-height . fit-window-to-buffer)))))

(defun arduino2--display-message (msg)
  "Display message MSG with selected method."
  (pcase arduino2-message-display-method
    ('tooltip (tooltip-show msg))
    ('window
     (arduino2--temp-buffer-show msg))
    ('minibuffer
     (message "%s" msg))))

(defun arduino2--message (cmd &rest path)
  "Run arduino2 CMD in PATH (if provided) and print as message.
If PATH is not provided, `default-directory' is used.
PATH should be an absolute directory name."
  (let* ((default-directory (if path (car path) default-directory))
         (arduino2-exec-path (expand-file-name arduino2-cli-executable arduino2-default-bin))
         (cmd2  (concat arduino2-exec-path " " cmd))
         (cmd* (arduino2--add-flags 'message cmd2))
         (out  (shell-command-to-string cmd*)))
    (arduino2--display-message (string-trim out))))

(defun arduino2--arduino? (usb-device)
  "Return USB-DEVICE if it is an Arduino, nil otherwise."
  (assoc 'matching_boards usb-device))

(defun arduino2--selected-board? (board selected-board)
  "Return BOARD if it is the SELECTED-BOARD."
  (string= (arduino2--board-address board)
           selected-board))

(defun arduino2--cmd-json (cmd)
  "Get the result of CMD as JSON-style alist."
  (let* ((arduino2-exec-path (expand-file-name arduino2-cli-executable arduino2-default-bin))
         (cmmd (concat arduino2-exec-path " " cmd " --format json")))
    (thread-first cmmd shell-command-to-string json-read-from-string)))

(defun arduino2--default-board ()
  "Get the default Arduino board, if available."
  (thread-first '()
                (arduino2--?map-put arduino2-default-fqbn 'fqbn)
                (arduino2--?map-put (arduino2--?map-put '() arduino2-default-port 'address) 'port)))

(defun arduino2--board (&optional refreshed)
  "Get connected Arduino board."
  (cond ((not arduino2-current-port)
         (error "ERROR: No board selected"))
        ((not arduino2-existing-boards)
         ;; try to refresh board list
         (if (not refreshed)
             (progn
               (arduino2--fill-detected-boards)
               (arduino2--board t))
           (error "ERROR: No board selected")))
        (t (gethash arduino2-current-port arduino2-existing-boards))))

(defun arduino2--board-fqbn ()
  "Get FQBN of BOARD.
If BOARD has multiple matching_boards, the first one is used."
  ;; NOTE: board format is: '(fqbn name protocol)
  (car (arduino2--board)))

;; (defun arduino2--board-address (board)
;;   "Get port address of BOARD."
;;   (cdr (assoc 'address (cdr (assoc 'port board)))))

(defun arduino2--board-name (board)
  "Get name of BOARD in (name @ port) format."
  (cadr board))
;; (concat (cdr (assoc 'name board))
;;         " @ "
;;         (arduino2--board-address board)))

;; (defun arduino2--select-board (boards)
;;   "Prompt user to select an Arduino from BOARDS."
;;   (let* ((board-names (cl-mapcar #'arduino2--board-name boards))
;;          (selection   (thread-first board-names
;;                                     (arduino2--select "Board ")
;;                                     (split-string "@")
;;                                     cadr
;;                                     string-trim)))
;;     (car (seq-filter (lambda (m) (arduino2--selected-board? m selection)) boards))))

(defun arduino2--cores ()
  "Get installed Arduino cores."
  (let* ((output   (arduino2--cmd-json "core list"))
         (cores    (alist-get 'platforms output))
         (id-pairs (seq-map (lambda (m) (assoc 'id m)) cores))
         (ids      (seq-map #'cdr id-pairs)))
    (if ids ids
      (error "ERROR: No cores installed"))))

(defun arduino2--search-cores ()
  "Search from list of cores."
  (let* ((output    (arduino2--cmd-json "core search")) ; search without parameters gets all cores
         (cores    (alist-get 'platforms output))
         (id-pairs (seq-map (lambda (m) (assoc 'id m)) cores))
         (ids      (seq-map #'cdr id-pairs)))
    (arduino2--select ids "Core ")))

(defun arduino2--libs (&optional full)
  "Get installed Arduino libraries.  If FULL is non-nil, return the full data objects, else return only library names."
  (let* ((output    (arduino2--cmd-json "lib list"))
         (libs      (alist-get 'installed_libraries output)))
    (if libs
        (if full
            libs
          (seq-map (lambda (lib) (cdr (assoc 'name (assoc 'library lib)))) libs))
      (error "ERROR: No libraries installed"))))

(defun arduino2--search-libs ()
  "Get installed Arduino libraries."
  (let* ((libs      (cdr (assoc 'libraries (arduino2--cmd-json "lib search")))))
    (if libs libs
      (error "ERROR: Unable to find libraries"))))

(defun arduino2--select (xs msg)
  "Select option from XS, prompted by MSG."
  (completing-read msg xs))

(defun arduino2--download-and-exec (url)
  "Download URL to temporary buffer and execute it with unix shell."
  (let ((download-buffer (url-retrieve-synchronously url)))
    ;; (shell-command  (buffer-substring-no-properties start end)))
    (save-excursion
      (set-buffer download-buffer)
      ;; we may have to trim the http response
      (goto-char (point-min))
      (re-search-forward "^$" nil 'move)
      (forward-char)
      (delete-region (point-min) (point))
      (shell-command (buffer-substring-no-properties (point-min) (point-max))))
    (kill-buffer download-buffer)))

(defun arduino2--download-and-install (url download-path &optional modes)
  "Download URL to temporary buffer and save it to DOWNLOAD-PATH with optional chmod to MODES (e.g. #o755)."
  (let ((download-buffer (url-retrieve-synchronously url))
        (download-path-modes (or modes #o644)))
    (save-excursion
      (set-buffer download-buffer)
      ;; we may have to trim the http response
      (goto-char (point-min))
      (re-search-forward "^$" nil 'move)
      (forward-char)
      (delete-region (point-min) (point))
      (write-file download-path))
    (kill-buffer download-buffer)
    (set-file-modes download-path download-path-modes)))

(defun arduino2--fill-detected-boards ()
  "Detect currently connected boards and (re)fill `arduino2-existing-boards' with fresh board values."
  (let* ((board-item-list '())
         (arduino2-exec-path (expand-file-name arduino2-cli-executable arduino2-default-bin))
         (cmd (concat arduino2-exec-path " board list --json"))
         (raw-out (shell-command-to-string cmd))
         (out (gethash "detected_ports" (json-parse-string raw-out :array-type 'list))))
    ;; convert `out' variable that is the list of detected boards
    ;; to board-item-list
    (dolist (board out)
      (let* ((matching-boards (gethash "matching_boards" board))
             (port (gethash "port" board))
             (port-address (gethash "address" port))
             (port-proto (gethash "protocol" port))
             board-name
             board-fqbn)
        ;; fill board name and fqbn
        (if (null matching-boards)
            (progn
              (setq board-name "unknown")
              (setq board-fqbn "unknown"))
          (let ((mb (car matching-boards)))
            (setq board-name (gethash "name" mb))
            (setq board-fqbn (gethash "fqbn" mb))))
        ;; append board item to board item list
        (push (list port-address board-fqbn board-name port-proto) board-item-list)))
    ;; refill hash table arduino2-existing-boards
    (clrhash arduino2-existing-boards)
    (dolist (b board-item-list)
      (puthash (car b) (cdr b) arduino2-existing-boards))))

(defun arduino2--supported-boards ()
  "Get list of all supported boards by Arduino.
Output format is alist `(\"Board Name\" . \"board fqbn)'
useful for various selections"
  (let* ((board-items '())
         (arduino2-exec-path (expand-file-name arduino2-cli-executable arduino2-default-bin))
         (cmd  (concat arduino2-exec-path " board listall --json"))
         (raw-out  (shell-command-to-string cmd))
         (out (gethash "boards" (json-parse-string raw-out :array-type 'list))))
    (dolist (board-type out)
      (let* ((bp (gethash "platform" board-type))
             (bp-compatible (gethash "compatible" (gethash "release" bp)))
             (bp-boards (gethash "boards" (gethash "release" bp))))
        (dolist (b bp-boards)
          (if bp-compatible
              (push `(,(gethash "name" b) . ,(gethash "fqbn" b)) board-items)))))
    board-items))

;;;
;;; User commands
;;;
(defun arduino2-refresh-connected-board-list()
  "Refresh board list connected to the system."
  (interactive)
  (arduino2--fill-detected-boards))

(defun arduino2-set-board-fqbn ()
  "Select manually and set board fqbn, connected to port.
Useful if board is not detected correctly."
  (interactive)
  (let (connected-board-ports)
    (maphash
     (lambda (key value)
       (push `(,(concat key " (" (cadr value) ")") . ,key) connected-board-ports))
     arduino2-existing-boards)

    (let* ((port-choice (completing-read "Port: " (mapcar #'car connected-board-ports) nil t))
           (current-board-port (cdr (assoc port-choice connected-board-ports)))
           (supported-board-items (arduino2--supported-boards))
           (board-choice (completing-read
                          "Board Name: "
                          (mapcar #'car supported-board-items)
                          nil t))
           (current-board-fqdn (cdr (assoc board-choice supported-board-items)))

           (current-board-item (gethash current-board-port arduino2-existing-boards))
           ;; fill new board item in format: (list \"board-fqbn\" \"board-name\" \"board-protocol\")'"
           (new-board-item `(,current-board-fqdn ,board-choice ,(caddr current-board-item))))
      ;; update current board item
      (puthash current-board-port new-board-item arduino2-existing-boards)
      (message "Selected symbol: %S %S" current-board-item new-board-item))))

(defun arduino2-select-port ()
  "Вибір мови з аліста."
  (interactive)
  (let (boards)
    (maphash
     (lambda (key value)
       (push `(,(concat key " (" (cadr value) ")") . ,key) boards))
     arduino2-existing-boards)
    (let* ((choice (completing-read "Board: " (mapcar #'car boards) nil t))
           (the-list (cdr (assoc choice boards))))
      (message "Selected board: %S" the-list)
      (setq arduino2-current-port the-list))))

(defun arduino2-install-cli()
  "Install arduino-cli automatically."
  (interactive)
  (spinner-start arduino2-spinner-type)
  (arduino2--download-and-exec arduino2-cli-download-url)
  (spinner-stop))

(defun arduino2-install-ide()
  "Install arduino-ide automatically."
  (interactive)
  (spinner-start arduino2-spinner-type)
  (arduino2--download-and-install arduino2-ide-download-url (expand-file-name arduino2-ide-executable arduino2-default-bin))
  (spinner-stop))

(defun arduino2-compile ()
  "Compile Arduino project."
  (interactive)
  (let* ((fqbn (if-let (fqbn (arduino2--board-fqbn)) fqbn
                 (error "ERROR: No fqbn specified")))
         (cmd (concat "compile --fqbn " fqbn)))
    (arduino2--compile cmd)))

(defun arduino2-compile-and-upload ()
  "Compile and upload Arduino project."
  (interactive)
  (when (arduino2--serial-monitor-is-active)
    (arduino2-stop-serial-monitor "to upload a sketch")
    (add-hook 'compilation-finish-functions
              #'arduino2--start-serial-monitor-callback))
  (let* ((fqbn (if-let (fqbn (arduino2--board-fqbn))
                   fqbn
                 (error "ERROR: No fqbn specified")))
         (port (if-let (port arduino2-current-port)
                   port
                 (error "ERROR: No port specified")))
         (cmd (concat "compile --fqbn " fqbn " --port " port " --upload")))
    (arduino2--compile cmd)))

(defun arduino2-upload ()
  "Upload Arduino project."
  (interactive)
  (when (arduino2--serial-monitor-is-active)
    (arduino2-stop-serial-monitor "to upload a sketch")
    (add-hook 'compilation-finish-functions
              #'arduino2--start-serial-monitor-callback))
  (let* ((board (arduino2--board))
         (fqbn  (if-let (fqbn (arduino2--board-fqbn board))
                    fqbn
                  (error "ERROR: No fqbn specified")))
         (port  (if-let (port (arduino2--board-address board))
                    port
                  (error "ERROR: No port specified")))
         (cmd (concat "upload --fqbn " fqbn " --port " port)))
    (arduino2--compile cmd)))

(defun arduino2-board-list ()
  "Show list of connected Arduino boards."
  (interactive)
  ;; (arduino2-refresh-connected-board-list)
  (let ((boards "Connected boards:\n-----------------\n"))
    (maphash
     (lambda (key value)
       (setq boards (concat boards (cadr value) " @ " key "\n")))
     arduino2-existing-boards)
    (arduino2--display-message boards)))

(defun arduino2-core-list ()
  "Show list of installed Arduino cores."
  (interactive)
  (arduino2--message "core list"))

(defun arduino2-core-upgrade ()
  "Update-index and upgrade all installed Arduino cores."
  (interactive)
  (let* ((cores     (arduino2--cores))
         (selection (arduino2--select cores "Core "))
         (cmd       (concat "core upgrade " selection))
         (arduino2-exec-path (expand-file-name arduino2-cli-executable arduino2-default-bin)))
    (shell-command-to-string (concat arduino2-exec-path " core update-index"))
    (arduino2--message cmd)))

(defun arduino2-core-upgrade-all ()
  "Update-index and upgrade all installed Arduino cores."
  (interactive)
  (shell-command-to-string (concat (expand-file-name arduino2-cli-executable arduino2-default-bin) " core update-index"))
  (arduino2--message "core upgrade"))

(defun arduino2-kill-arduino-connection ()
  "Kill any existing connection to an arduino."
  (interactive)
  (let ((comp-proc (get-buffer-process arduino2--compilation-buffer)))
    (if comp-proc
        (condition-case ()
            (progn
              (interrupt-process comp-proc)
              (sit-for 1)
              (delete-process comp-proc))
          (error nil))
      (message "No Arduino connection running!"))))

;; TODO change from compilation mode into other, non blocking mini-buffer display
(defun arduino2-core-install ()
  "Find and install Arduino cores."
  (interactive)
  (let* ((core (arduino2--search-cores))
         (arduino2-exec-path (expand-file-name arduino2-cli-executable arduino2-default-bin))
         (cmd  (concat arduino2-exec-path " core install " core)))
    (shell-command-to-string (concat arduino2-exec-path " core update-index"))
    (setf arduino2--compilation-buffer
          (compilation-start cmd 'arduino2-compilation-mode))))

(defun arduino2-core-uninstall ()
  "Find and uninstall Arduino cores."
  (interactive)
  (let* ((cores     (arduino2--cores))
         (selection (arduino2--select cores "Core "))
         (cmd       (concat " core uninstall " selection)))
    (arduino2--message cmd)))

(defun arduino2-lib-list ()
  "Show list of installed Arduino libraries."
  (interactive)
  (arduino2--message "lib list"))

(defun arduino2-lib-upgrade ()
  "Upgrade Arduino libraries."
  (interactive)
  (shell-command-to-string (concat (expand-file-name arduino2-cli-executable arduino2-default-bin) " lib update-index"))
  (arduino2--message "lib upgrade"))

;; TODO change from compilation mode into other, non blocking mini-buffer display
(defun arduino2-lib-install (select-version-p)
  "Find and install Arduino libraries.  With prefix arg SELECT-VERSION-P, allow selecting the library version."
  (interactive "P")
  (let* ((libs (arduino2--search-libs))
         (lib-names (if select-version-p
                        (apply #'append (seq-map (lambda (lib)
                                                   (seq-map (lambda (ver)
                                                              (format "%s@%s" (cdr (assoc 'name lib)) ver))
                                                            (cdr (assoc 'available_versions lib))))
                                                 libs))
                      (seq-map (lambda (lib) (cdr (assoc 'name lib))) libs)))
         (selection (arduino2--select lib-names "Library "))
         (arduino2-exec-path (expand-file-name arduino2-cli-executable arduino2-default-bin))
         (cmd (concat arduino2-exec-path " lib install " (shell-quote-argument selection))))
    (shell-command-to-string (concat arduino2-exec-path " lib update-index"))
    (setf arduino2--compilation-buffer
          (compilation-start cmd 'arduino2-compilation-mode))))

(defun arduino2-lib-uninstall ()
  "Find and uninstall Arduino libraries."
  (interactive)
  (let* ((libs (arduino2--libs))
         (selection (arduino2--select libs "Library "))
         (cmd (concat "lib uninstall " (shell-quote-argument selection))))
    (arduino2--message cmd)))

(defun arduino2-lib-browse ()
  "Browse the install directory of an installed Arduino library."
  (interactive)
  (let* ((output    (arduino2--libs t))
         (lib-dirs  (seq-map (lambda (lib)
                               (let ((library (cdr (assoc 'library lib))))
                                 (cons (cdr (assoc 'name library))
                                       (cdr (assoc 'install_dir library)))))
                             output))
         (selection (let ((completion-extra-properties
                           `(:annotation-function ,(lambda (k) (format " (%s)" (alist-get k lib-dirs nil nil #'string=))))))
                      (arduino2--select (seq-map #'car lib-dirs) "Library "))))
    (find-file (alist-get selection lib-dirs nil nil #'string=))))

(defun arduino2-new-sketch ()
  "Create a new Arduino sketch."
  (interactive)
  (let* ((name (read-string "Sketch name: "))
         (path (expand-file-name (read-directory-name "Sketch path: " arduino2-mode-home)))
         (cmd  (concat "sketch new " name)))
    (arduino2--message cmd path)
    (find-file (file-name-concat path name (concat name ".ino")))))

(defun arduino2-config-init ()
  "Create a new Arduino config."
  (interactive)
  (when (y-or-n-p "Init will override any existing config files, are you sure? ")
    (arduino2--message "config init")))

(defun arduino2-config-dump ()
  "Dump the current Arduino config."
  (interactive)
  (arduino2--message "config dump"))

(defun arduino2-config-directory-browse ()
  "Browse a directory specified in the current Arduino config."
  (interactive)
  (let* ((output    (arduino2--cmd-json "config get directories"))
         (dir-keys  (seq-map (lambda (kv) (substring-no-properties (symbol-name (car kv)))) output))
         (selection (let ((completion-extra-properties
                           `(:annotation-function ,(lambda (k) (format " (%s)" (alist-get (intern k) output))))))
                      (arduino2--select dir-keys "Directory ")))
         )
    (find-file (alist-get (intern selection) output))))

(defcustom arduino2-monitor-buffer-name "arduino cli monitor"
  "The name for the arduino monitor buffer."
  :group 'arduino2
  :type 'string)

(defvar arduino2--monitor-buffer nil
  "The buffer for the monitor.")

(defvar arduino2-monitor-default-baud-rate 115200
  "The default baud rate to listen to for the serial monitor.

It can be overridden by passing a prefix argument to
`#'arduino2-start-serial-monitor'.

This must match the value set in your sketch, in a line of code that
looks like Serial.begin(115200).

The arduino will only accept certain values. For more, see
https://www.arduino.cc/reference/it/language/functions/communication/serial/begin/")

(defun arduino2--serial-monitor-is-active ()
  "Return t if the monitor is active, nil otherwise."
  (not (not (process-live-p (get-buffer-process arduino2--monitor-buffer)))))

(defun arduino2--start-serial-monitor-callback (compilation-buffer process-finish-status)
  "Start the serial monitor and remove itself from `compilation-finish-functions'.

It only runs when COMPILATION-BUFFER is
`arduino2--compilation-buffer', and PROCESS-FINISH-STATUS is
\"finished\n\", which is what the arduino reports."
  (when (and (eq compilation-buffer
                 arduino2--compilation-buffer)
             (string= process-finish-status
                      "finished\n"))
    (remove-hook 'compilation-finish-functions #'arduino2--start-serial-monitor-callback)
    (arduino2-start-serial-monitor)))

(defun arduino2-start-serial-monitor (&optional monitor-baud-rate)
  "Start the arduino serial monitor.

If MONITOR-BAUD-RATE is passed, use that as the baud rate. Otherwise,
use `arduino2-monitor-default-baud-rate'."
  (interactive "P")
  (when (arduino2--serial-monitor-is-active)
    (arduino2-stop-serial-monitor "to restart the serial monitor")
    (while (arduino2--serial-monitor-is-active)
      ;; arduino2-stop-serial-monitor calls kill-process, which
      ;; kills the process asynchronously, so we need to wait for the
      ;; process to actually end before restarting the monitor.
      (sit-for 0.01)))
  (let ((monitor-buffer (or (and (buffer-live-p arduino2--monitor-buffer)
                                 arduino2--monitor-buffer)
                            (get-buffer-create arduino2-monitor-buffer-name))))
    (unless (eq arduino2-verbosity 'quiet)
      (with-current-buffer monitor-buffer
        (insert (format-time-string "\nStarting the monitor at %T...\nTo stop it, press C-c C-c, or run arduino2-stop-serial-monitor.\n\n"))))
    (let* ((board (arduino2--board))
           (port (if-let (port (arduino2--board-address board))
                     port
                   (error "ERROR: No port specified")))
           (async-shell-command-buffer 'confirm-kill-process)
           (shell-command-dont-erase-buffer t)
           (arduino2-exec-path (expand-file-name arduino2-cli-executable arduino2-default-bin))
           (window (async-shell-command (format (concat arduino2-exec-path " monitor --port %s --config baudrate=%s %s")
                                                (shell-quote-argument port)
                                                (shell-quote-argument (format "%d"
                                                                              (or (when monitor-baud-rate (prefix-numeric-value monitor-baud-rate))
                                                                                  arduino2-monitor-default-baud-rate)))
                                                (arduino2--general-flags))
                                        monitor-buffer)))
      (setf arduino2--monitor-buffer (window-buffer window)))))

(defun arduino2-stop-serial-monitor (&optional reason)
  "Stop the arduino serial monitor.

If provided, REASON is printed in a message in the buffer."
  (interactive)
  (let ((arduino-monitor-process (get-buffer-process arduino2--monitor-buffer)))
    (when (and (bufferp arduino2--monitor-buffer)
               (process-live-p arduino-monitor-process))
      (kill-process arduino-monitor-process)
      (unless (eq arduino2-verbosity 'quiet)
        (with-current-buffer arduino2--monitor-buffer
          (insert (format "\nStopped serial monitor %sat %s...\n\n"
                          (if reason
                              (concat reason " ")
                            "")
                          (format-time-string "%T"))))))))

(defun arduino2-open-with-arduino-ide()
  "Open the sketch with the Arduino IDE."
  (interactive)
  (when (arduino2--serial-monitor-is-active)
    (arduino2-stop-serial-monitor "to open sketch with arduino IDE")
    (add-hook 'compilation-finish-functions
              #'arduino2--start-serial-monitor-callback))
  (let ((current-file-name (buffer-file-name)))
    (if (null current-file-name)
        (error "ERROR: save current buffer to file before opening it with arduino IDE")
      (arduino2--ide-open (buffer-file-name)))))

;;; Major mode
(defvar arduino2-command-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "c") #'arduino2-compile)
    (define-key map (kbd "b") #'arduino2-compile-and-upload)
    (define-key map (kbd "u") #'arduino2-upload)
    (define-key map (kbd "n") #'arduino2-new-sketch)
    (define-key map (kbd "l") #'arduino2-board-list)
    (define-key map (kbd "i") #'arduino2-lib-install)
    (define-key map (kbd "U") #'arduino2-lib-uninstall)
    (define-key map (kbd "k") #'arduino2-kill-arduino-connection)
    (define-key map (kbd "m") #'arduino2-start-serial-monitor)
    (define-key map (kbd "M") #'arduino2-stop-serial-monitor)
    (define-key map (kbd "x") #'arduino2-open-with-arduino-ide)
    map)
  "Keymap for arduino2 mode commands after `arduino2-mode-keymap-prefix'.")
(fset 'arduino2-command-map arduino2-command-map)

(defvar arduino2-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map arduino2-mode-keymap-prefix 'arduino2-command-map)
    map)
  "Keymap for arduino2 mode.")

(defvar arduino2--compilation-buffer nil
  "The compilation buffer for the most recent compilation.")

(easy-menu-define arduino2-menu arduino2-mode-map
  "Menu for arduino2."
  '("Arduino2"
    ["New sketch" arduino2-new-sketch]
    ["Open with Arduino IDE" arduino2-open-with-arduino-ide]
    "--"
    ["Compile Project"            arduino2-compile]
    ["Upload Project"             arduino2-upload]
    ["Compile and Upload Project" arduino2-compile-and-upload]
    "--"
    ["Board list" arduino2-board-list]
    ["Refresh Connected Boards" arduino2-refresh-connected-board-list]
    ["Update Board Name" arduino2-set-board-fqbn]
    ["Select Port Board Connected to" arduino2-select-port]
    ;; ["Core list"      arduino2-core-list]
    ;; ["Core install"   arduino2-core-install]
    ;; ["Core uninstall" arduino2-core-uninstall]
    "--"
    ["Library list"      arduino2-lib-list]
    ["Library install"   arduino2-lib-install]
    ["Library uninstall" arduino2-lib-uninstall]
    "--"
    ["Core list"      arduino2-core-list]
    ["Core install"   arduino2-core-install]
    ["Core uninstall" arduino2-core-uninstall]
    ["Core upgrade"   arduino2-core-upgrade]
    "--"
    ["Config init" arduino2-config-init]
    ["Config dump" arduino2-config-dump]
    "--"
    ["Install IDE" arduino2-install-ide]
    ["Install CLI" arduino2-install-cli]))

;;;###autoload
;; (define-derived-mode arduino2-mode c-mode "arduino2"
;;   ;; (define-minor-mode arduino2-mode
;;   "Major mode for editing Arduino code."
;;   ;; :lighter " arduino2"
;;   :keymap   arduino2-mode-map
;;   :group   'arduino2
;;   :require 'arduino2)

(define-derived-mode arduino2-mode c-mode "arduino2"
  "Major mode for editing Arduino code."
  ;; For `cc-mode' initialize.
  (c-initialize-cc-mode t)
  ;; `c-init-language-vars' is a macro that is expanded at compile time to a
  ;; large `setq' with all the language variables and their customized values
  ;; for our language.
  (c-init-language-vars arduino2-mode)
  ;; `c-common-init' initializes most of the components of a CC Mode buffer,
  ;; including setup of the mode menu, font-lock, etc. There's also a lower
  ;; level routine `c-basic-common-init' that only makes the necessary
  ;; initialization to get the syntactic analysis and similar things working.
  (c-common-init 'arduino2-mode)

  (set (make-local-variable 'c-basic-offset) 2)
  (set (make-local-variable 'tab-width) 2))

;;;###autoload
(add-to-list 'auto-mode-alist '("\\.pde\\'" . arduino2-mode))
;;;###autoload
(add-to-list 'auto-mode-alist '("\\.ino\\'" . arduino2-mode))

(provide 'arduino2-mode)
;;; arduino2-mode.el ends here
