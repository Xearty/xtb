module xtb.log.level;

nothrow @nogc:

enum LogLevel : ubyte
{
    trace,
    debug_,
    info,
    warning,
    error,
    fatal,
}
