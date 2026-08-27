# terminal

`import xtb.terminal;` exposes terminal presentation policy above the native
platform layer. It provides `AnsiMode` and `shouldUseAnsi` while precise
low-level modules such as `xtb.os.posix.terminal` provide capability queries
over native handles.

Automatic ANSI selection honors `NO_COLOR`, `CLICOLOR_FORCE`, `TERM=dumb`, and
whether the destination is a terminal.
