# process

`import xtb.process;` exposes commands, child processes, explicit standard-I/O
routing, bounded communication, and linear pipelines. Process resources use
explicit ownership and expected failures are returned as typed status/error
values.

See [processes and pipelines](docs/guide.md) and
[`process_demo.d`](../../examples/process_demo.d).

The package also owns current-process environment lookup; the OS package only
provides the native environment mechanism used underneath.
