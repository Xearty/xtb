module examples.stacktrace_demo;

import core.stdc.stdio : FILE, stdout;
import xtb.core.print : Writer;
import xtb.core.stacktrace : StackFrame, StackTrace, StackTraceContext,
    capture, writeStackTrace;

extern(C) int main(int argumentCount, char** arguments)
{
    const(char)* executable = argumentCount == 0 ? null : arguments[0];
    StackTraceContext context = StackTraceContext.create(executable);
    StackFrame[32] frames;
    char[8192] text;
    StackTrace trace = context.capture(frames[], text[], 0);

    Writer writer = Writer.fromFile(cast(FILE*) stdout);
    writer.writeStackTrace(&trace);
    return writer.finish().ok ? 0 : 1;
}
