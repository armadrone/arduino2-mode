# arduino2-mode

`arduino2-mode` is an Emacs major for editing arduino-based projects.
This project is a combination of original
[arduino-mode](https://github.com/stardiviner/arduino-mode/tree/23ae47c9f28f559e70b790b471f20310e163a39b)
using arduino v.1 ecosystem as a backend, [arduino-cli-mode](https://github.com/motform/arduino-cli-mode)
using the new [arduino command line interface](https://github.com/arduino/arduino2)
and [lsp-arduino](https://github.com/mgrunwald/emacs-lsp-arduino) LSP client.
Some code were ported from these projects and some is brand new.
I've tried to merge the best from all three projects into this `arduino2-mode`.

## Whats new (comparing to original ones?)

- This mode is an emacs *major* mode, using arduino v.2 IDE ecosystem, including
features like "Open with Arduino IDE", "Compile and Upload Project" and "Board list"
adopted to arduino v.2 IDE and CLI.

- This mode allows to install IDE and CLI automatically in two menu clicks:
`Menu: Arduino2` -> `Install IDE` and `Menu: Arduino2` -> `Install CLI`. But, only the CLI
is essential to work with `arduino2-mode`
- Changed board selection mechanism:
  1. After board connected, run `M-x`->`arduino2-refresh-connected-board-list` or
     click menu item `Arduino2`->`Refresh Connected Boards` (it did not implemented
     as an automatic refresh).
  2. Select working serial port with `M-x`->`arduino2-select-port` or click
     menu item `Arduino2`->`Select Port Board Connected to`
  3. _(OPTIONAL only if board type does not detected automatically by arduino-cli. 
     Typical for e.g. ESP32 boards)_ select board type manually: 
     `M-x`->`arduino2-set-board-fqbn` or click menu item `Arduino2`->
     `Update Board Name`. Than select port and board name from list.
- Message output channel could be selected and set as `arduino2-message-display-method` customization

> NOTE: `arduino2-select-port` could be performed dynamicslly at any time. It allows to work 
 with several boards at once.
 
> NOTE: manual board selection erased after connected board list refresh (TODO: probably 
this behavior should be fixed).

## Installation

Just clone this repo to some local path and add it to load-path. Than use `require` or `use-package`. Some simple example:

```elisp
(add-to-list 'load-path "/the/path/to/arduino2-mode")

(use-package arduino2-mode
  ;; :hook arduino2-mode
  ;; :mode "\\.ino\\'"
  :custom
  (arduino2-warnings 'all)
  (arduino2-verify t))

;; To use LSP integration should also `lsp-arduino2' package used
(use-package lsp-arduino2 :after arduino2-mode)
```

To install and use arduino LSP server, `golang` package must be installed initially (debian eaxmple):
```bash
user@host $ sudo apt install golang -y
```
For easy installation of arduino LSP server, execute command: `M-x`->`lsp-arduino2-install-srever`.

For easy installation of Arduino IDE and Arduino CLI, execute commands:
`M-x`->`arduino2-install-ide` and `M-x`->`arduino2-install-ide`
or use menu bar in arduino2 mode:
`Arduino2`->`Install CLI` and `Arduino2`->`Install IDE` (see customization group `arduino2` for fine tuning)

Also, keep in mind that you need a FUSE for Arduino IDE (as described [here](https://support.arduino.cc/hc/en-us/articles/360019833020-Download-and-install-Arduino-IDE)). An example for debian-based distros:

```bash
user@host $ sudo apt install libfuse2
```
Also, you should update file `/etc/udev/rules.d/99-arduino.rules` with
```conf
SUBSYSTEMS=="usb", ATTRS{idVendor}=="2341", GROUP="plugdev", MODE="0666"
```

## Customization


All `arduino2-mode` customizations are located in `arduino2` group 
for `arduino2-mode` itself and in `lsp-arduino2` group for LSP client.


## Keymap

The default keymap prefix is `C-c C-a` and can be customized with `arduino2-mode-keymap-prefix`.

The following keybindings are provided out of the box.

| Function                | Keymap      |
| ---                     | ---         |
| Compile                 | `C-c C-a c` |
| Upload                  | `C-c C-a u` |
| Compile and Upload      | `C-c C-a b` |
| List Connected Boards   | `C-c C-a l` |
| Create new sketch       | `C-c C-a n` |
| Install a Library       | `C-c C-a i` |
| Uninstall a Library     | `C-c C-a u` |
| Kill Arduino Connection | `C-c C-a k` |
| Open Serial Monitor     | `C-c C-a m` |
| Close Serial Monitor    | `C-c C-a M` |


## What it is not

This mode is not compatible with arduino v.1.x.x. ecosystem and I am not not going to support it.
For arduino v.1.x.x emacs mode, please check out
[arduino-mode](https://github.com/stardiviner/arduino-mode/tree/23ae47c9f28f559e70b790b471f20310e163a39b)

If you want auto-completion for Arduino development, see
[company-arduino](https://github.com/yuutayamada/company-arduino/tree/d7e369702b8eee63e6dfdeba645ce28b6dc66fb1).

Depending on your board, you might also enjoy [platform-io-mode](https://github.com/ZachMassia/PlatformIO-Mode),
an excellent wrapper that I took a lot of inspiration from while writing this one.


## Contribute

Please, fill free to make any contributions to this repository via github pull requests.
