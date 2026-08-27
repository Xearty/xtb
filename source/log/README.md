# log

`import xtb.log;` provides allocation-conscious logging with level filtering,
configurable labels and palettes, ANSI or plain sinks, prefixes, timestamps,
callsites, tee fan-out, and an optional thread-local logger. Timestamp prefixes
use wall-clock time from the `time` subpackage.

See the [logging guide](docs/logging.md) and
[`logging_demo.d`](../../examples/logging_demo.d).
