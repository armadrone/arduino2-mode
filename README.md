# arduino2-mode

`arduino2-mode` is an Emacs minor mode for using the excellent new 
[arduino command line interface](https://github.com/arduino/arduino2)
in an Emacs-native fashion. The mode covers the full range of
`arduino2` features in an Emacs native fashion. It even 
leverages the infinite power the GNU to provide fussy-finding
of libraries and much improved support for handling multiple boards.
The commands that originally require multiple steps (such as first
searching for a library and then separately installing it) have
been folded into one.


## Installation

The recommended way to install `arduino2-mode` is through [melpa](http://melpa.org/#/arduino2-mode). 
Depending on if you use [arduino-mode](https://melpa.org/#/arduino-mode) 
or not, you might want to load `arduino2-mode` either as a hook or as a mode.
A sample configuration with [use-package](https://github.com/jwiegley/use-package) could look like this:

```elisp
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
```shell
user@host $ sudo apt install golang -y
```
For easy installation of arduino LSP server, execute command: `M-x`->`lsp-arduino2-install-srever`.

For easy installation of Arduino IDE and Arduino CLI, execute commands:
`M-x`->`arduino2-install-ide` and `M-x`->`arduino2-install-ide`
or use menu bar in arduino2 mode:
`Arduino2`->`Install CLI` and `Arduino2`->`Install IDE` (see customization group `arduino2` for fine tuning)

Also, keep in mind that you need a FUSE for Arduino IDE (as described [here](https://support.arduino.cc/hc/en-us/articles/360019833020-Download-and-install-Arduino-IDE)). An example for debian-based distros:

```shell
sudo apt install libfuse2
```
Also, you should update file `/etc/udev/rules.d/99-arduino.rules` with
```shell
SUBSYSTEMS=="usb", ATTRS{idVendor}=="2341", GROUP="plugdev", MODE="0666"
```

## Default boards

By default `arduino2-mode` uses the `board list` command from
`arduino2` to determine which board to target. This works well 
if you have a genuine Arduino board (with its unique USB Vendor ID and Product ID)
and it is currently connected, 
but won't work if your board is not plugged in 
or is an unbranded board with generic USB Vendor and Product IDs.

To cover these use cases you are able to set a default board
(fqbn) and port via `arduino2-default-fqbn` and
`arduino2-default-port` respectively. These can, of course, be set
globally via your `init`, but you may find them to be an excellent fit
for
[dir](https://www.gnu.org/software/emacs/manual/html_node/elisp/Directory-Local-Variables.html)
and [file local variables](https://www.gnu.org/software/emacs/manual/html_node/elisp/File-Local-Variables.html#File-Local-Variables).
For example, on a Linux system with an unbranded NodeMCU v2 compatible
board connected to ttyUSB0,
you could use the following line at the top of your sketch: 

```cpp
// -*- arduino2-default-fqbn: "esp8266:esp8266:nodemcuv2"; arduino2-default-port: "/dev/ttyUSB0"; -*-
// (The rest of your sketch follows as usual.)
```


To get the fqbn/port information for a currently connected board, use 
`arduino2-board-list`.

Using default board variables should be a bit faster, as it
eliminates the need to shelling out and then parse JSON from `arduino2`.


## Customization


You can enable the major flags from `arduino2` using similar enumerations. 

| Flag                                 | Values                                       |
| ---                                  | ---                                          |
| `arduino2-verify`                 | `nil` (default), `t`                         |
| `arduino2-warnings`               | `nil` (default), `'default`, `'more`, `'all` |
| `arduino2-verbosity`              | `nil` (default), `'quiet`, `'verbose`        |
| `arduino2-compile-only-verbosity` | `nil`, `t` (default)                         |
| `arduino2-compile-color`          | `nil`, `t` (default)                         |

If you want to automatically enable `arduino2-mode` on `.ino` files, you have to get [auto-minor-mode](https://github.com/joewreschnig/auto-minor-mode).
Once that is installed, add the following to your init:

```elisp
(add-to-list 'auto-minor-mode-alist '("\\.ino\\'" . arduino2-mode))
```


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


## Limitations

* Does not support `board attach` commands
* Only tested on macOS (but will probably work on other Unices)
* Not called `elduino-mode`


## What it is not

This mode is not an Arduino major mode, it only provides convenient access to arduino2.
If you are looking for something like that, check out [arduino-mode](https://github.com/stardiviner/arduino-mode/tree/23ae47c9f28f559e70b790b471f20310e163a39b).
In fact, I think they would complement each other rather well, as `arduino-mode` lacks support 
for `arduino2`, simply due to pre-dating it with a decade.

If you want auto-completion for Arduino development, see [company-arduino](https://github.com/yuutayamada/company-arduino/tree/d7e369702b8eee63e6dfdeba645ce28b6dc66fb1).

Depending on your board, you might also enjoy [platform-io-mode](https://github.com/ZachMassia/PlatformIO-Mode),
an excellent wrapper that I took a lot of inspiration from while writing this one.


## Contribute

This is my first real elisp project, so everything from code review to feature implementations are welcome!
The plan is to support (more or less) the entire feature set of arduino2, and then go into maintenance mode.
