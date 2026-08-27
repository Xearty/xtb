# Processes and pipelines

Use `Command.exact` for a known executable path or `Command.search` to resolve an
executable through `PATH`.

```d
String[] arguments = ["--version"];
Command command = Command.search("ldc2", arguments);
```

`Command` borrows its executable, arguments, working directory, and environment
storage; they only need to remain valid while the command is being used to
spawn.

## I/O routes

Standard input/output/error can be:

- inherited from the parent;
- connected to the null device;
- created as a new pipe with `piped()`;
- borrowed from an existing `File`/pipe endpoint;
- for stderr, merged with stdout.

`File` values used by process routes come from `xtb.fs`; raw pipe endpoints come from `xtb.os`.

A `borrow(...)` route never transfers ownership. `piped()` creates a new pipe
and transfers the **parent-side endpoint** into the resulting `ChildProcess`.
Access it through `stdinPipe`, `stdoutPipe`, or `stderrPipe`.

`close()` reports close errors. Calling `deinit()` on a pipe endpoint is the
convenience form when a close error is not useful to the caller.

## Child lifecycle

`spawn` fills an owning `ChildProcess`. Process lifetime and resource lifetime
are intentionally separate:

1. resolve the live process with `wait`, `terminateAndWait`, `killAndWait`, or an
   equivalent operation;
2. consume/close any remaining parent-side pipes;
3. `deinit()` the `ChildProcess`.

`ChildProcess.deinit()` **does not wait for or terminate a live process**. In
checked builds, deinitializing a still-live child is diagnosed as misuse.

```d
String[1] arguments = ["hello\n"];
Command command = Command.search("printf", arguments[]);
SpawnOptions options = SpawnOptions.init
    .withStdin(InputRoute.nullDevice())
    .withStdout(OutputRoute.piped());

ChildProcess child;
ProcessError error = spawn(command, options, &child);
assert(!error.failed);

ExitStatus status;
error = wait(&child, &status);
assert(!error.failed);
// Read child.stdoutPipe until EOF as needed.
child.deinit();
```

Waiting reaps the process but does not discard unread pipe data; parent-side
pipe endpoints remain owned by the `ChildProcess` until closed or deinitialized.
For output that may fill a pipe, drain it while the child runs (or use
`communicate`) rather than waiting first. `tryWait`/`waitFor` are available when
blocking indefinitely is not desired.

`communicate` drives piped stdin/stdout/stderr together, optionally with a
timeout. Its timeout policy can leave the child running, request termination and
then kill, or kill immediately; check the returned state before deciding what
lifecycle work remains.

## Pipelines

`spawnPipeline` connects a linear sequence and returns one owning `Pipeline`.
Internal stage-to-stage pipes are managed by the pipeline. If the outer stdin or
stdout route is `piped()`, `stdinPipe()` exposes the first stage's input and
`stdoutPipe()` the last stage's output. Per-stage stderr can be accessed with
`stderrPipe(index)` when configured as piped.

```d
String[1] printfArgs = ["hello\n"];
String[1] wcArgs = ["-c"];
Command[2] commands = [
    Command.search("printf", printfArgs[]),
    Command.search("wc", wcArgs[]),
];

Pipeline pipeline;
ProcessError error = spawnPipeline(commands[], PipelineOptions.init,
    mallocAllocator(), &pipeline);
assert(!error.failed);

error = waitPipeline(&pipeline);
assert(!error.failed);
assert(pipeline.succeeded);
pipeline.deinit();
```

The allocator passed to `spawnPipeline` backs the pipeline's stage/status
storage. As with a child, `Pipeline.deinit()` never chooses to terminate live
stages: call `waitPipeline`, `terminatePipelineAndWait`, or
`killPipelineAndWait` first.

`PipelineSuccess.lastStage` (the default) defines success by the last stage;
`everyStage` requires every stage to succeed. Use `PipelineStage` when a stage
needs its own stderr route.

Expected process failures are reported as `ProcessError`; a normal child exit,
including a nonzero exit code or signal, is represented separately by
`ExitStatus`.

See [`process_demo.d`](../../../examples/process_demo.d) for capture, streaming
I/O, timeout handling, termination, and pipelines.
