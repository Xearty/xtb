# terminal

`import xtb.terminal;` exposes terminal presentation policy above the raw OS
capability layer. It provides `AnsiMode` and `shouldUseAnsi` while `xtb.os`
retains only native terminal detection.

Automatic ANSI selection honors `NO_COLOR`, `CLICOLOR_FORCE`, `TERM=dumb`, and
whether the destination is a terminal.
