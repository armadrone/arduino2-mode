;;; lsp-arduino2.el --- description -*- lexical-binding: t; -*-

;; Copyright © 2022  Markus Grunwald, 2026  Armadrone LLC

;; Author: Markus Grunwald, Armadrone LLC
;; URL: https://github.com/armadrone/arduino2-mode
;; Version: 202601
;; Package-Requires: ((emacs "29.1"))
;; Created: 2026-01-11
;; Keywords: lsp, arduino, processes tools

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; LSP Client for the Arduino v.2.X.X-style ecosystem.

;;; Code:

(require 'lsp-mode)
(require 'lsp-completion)

(defgroup lsp-arduino2 nil
  "LSP support for Arduino, using arduino-language-server."
  :group 'lsp-mode
  :link '(url-link
          "https://github.com/arduino/arduino-language-server")
  )

(defcustom lsp-arduino2-server-path "arduino-language-server"
  "Path to arduino-language-server binary."
  :group 'lsp-arduino2
  :type 'file
  :group 'lsp-arduino2
  )

(defcustom lsp-arduino2-server-args nil
  "Extra CLI arguments for arduino-language-server."
  :type '(repeat string)
  :group 'lsp-arduino2)

;; (with-eval-after-load 'lsp-mode
;;   (add-to-list 'lsp-language-id-configuration
;;                '(arduino2-mode . "arduino2")))

(with-eval-after-load 'lsp-mode
  (add-to-list 'lsp-language-id-configuration '(arduino2-mode . "arduino2")))

(defun lsp-arduino2--install-server(_client callback error-callback _update?)
  "Install arduino language server.

  Will invoke CALLBACK or ERROR-CALLBACK based on result.
  Will update if UPDATE? is t"
  (lsp-async-start-process
   callback
   error-callback
   "go" "install" "github.com/arduino/arduino-language-server@latest"))

(defvar lsp-arduino2--current-fqbn arduino2-default-fqbn
  "Set current arduino2 fqbn.")

(defun lsp-arduino2-set-fqbn (fqbn)
  "Set Arduino FQBN and restart Arduino LSP server."
  ;; (interactive "sFQBN (e.g. arduino:avr:uno): ")
  (setq lsp-arduino2--current-fqbn fqbn)
  ;; Restart workspace for FQBN refresh
  (when (lsp-workspaces)
    (lsp-workspace-restart (lsp-find-workspace 'arduinols nil)))
  (message "Arduino FQBN set to %s and LSP server restarted" fqbn))

;; /home/defcon/Arduino/test4

(lsp-register-client
 (make-lsp-client :new-connection (let ((default-directory (if (buffer-file-name) (file-name-directory (buffer-file-name)) "~")))
                                    (lsp-stdio-connection
                                     (lambda ()
                                       (let* ((go-path (getenv "GOPATH"))
                                              (lsp-server-path (expand-file-name lsp-arduino2-server-path (or go-path "~/go/bin"))))
                                         (list lsp-server-path lsp-arduino2-server-args " -fqbn " lsp-arduino2--current-fqbn)))))
                  :activation-fn (lsp-activate-on "arduino2")
                  :download-server-fn #'lsp-arduino2--install-server
                  :major-modes '(arduino2-mode)
                  :priority -1
                  :server-id 'arduinols))

;; add libraries from default arduino2 home directory
(lsp-workspace-folders-add (file-name-concat arduino2-mode-home "libraries"))

;;;###autoload
(add-hook 'arduino2-mode-hook (lambda ()
                                (when
                                    (and
                                     (fboundp 'lsp-workspace-folders-add)
                                     (buffer-file-name))
                                  (lsp-workspace-folders-add (file-name-directory (buffer-file-name))))))

(provide 'lsp-arduino2)
;;; lsp-arduino2.el ends here
