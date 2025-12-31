(autoload 'arduino2-mode "arduino2-mode" "Major mode for editing Arduino code." t)
(autoload 'ede-arduino-preferences-file "ede-arduino2" "Preferences file of Arduino." t)
(add-to-list 'auto-mode-alist '("\\.ino\\'" . arduino2-mode))
(add-to-list 'auto-mode-alist '("\\.pde\\'" . arduino2-mode))
