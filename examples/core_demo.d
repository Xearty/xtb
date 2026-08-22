module examples.core_demo;

import xtb.core;

private enum Permission
{
    read,
    write,
    execute,
}

extern (C) int main() nothrow @nogc
{
    ThreadContextScope context = ThreadContextScope.acquire();
    ScratchScope scratch = ScratchScope.acquire();

    Array!int numbers = Array!int.create(scratch.allocator);
    foreach (number; 1 .. 6)
        numbers.append(number);

    StringBuf message = StringBuf.create(scratch.allocator);
    message.format!"{} {}"("core values:", numbers.length);
    writeln(message);

    StringBuf path = StringBuf.fromString(scratch.allocator, "assets");
    path.append('/');
    path.append("image.bmp");
    formatln!"path={}, first={}, last={}"(
        path,
        numbers[0],
        numbers[numbers.length - 1],
    );

    char[128] logStorage;
    Logger logger = stderrLogger(logStorage[], LogLevel.info);
    logger.info("logger configured for ", numbers.length, " values");
    ThreadLoggerScope logging = ThreadLoggerScope.install(&logger);
    infof!"processed {} values"(numbers.length);

    alias Permissions = FlagSet!Permission;
    auto permissions = Permissions.of(Permission.read)
        .enabled(Permission.write);
    permissions.enable(Permission.execute);
    formatln!"enabled permissions: {}"(permissions.enabledCount);
    foreach (permission; permissions)
        formatln!"permission bit position: {}"(cast(int) permission);

    const timeout = milliseconds(2_000);
    formatln!"timeout: {} ms"(timeout.wholeMilliseconds);

    String text = "Aé🙂";
    formatln!"text bytes={}, code points={}"(
        text.byteLength,
        text.codePointCount,
    );
    foreach (decoded; text.codePointsWithOffsets)
        formatln!"scalar U+{} starts at byte {} and occupies {} bytes"(
            hexadecimal(cast(uint) decoded.value).upper,
            decoded.byteOffset,
            decoded.byteLength,
        );

    const u8[5] externalBytes = ['c', 'a', 'f', 0xc3, 0xa9];
    const checkedText = externalBytes[].asString;
    if (checkedText.failed)
        return 1;
    formatln!"validated external text: {}"(checkedText.value);

    // Arena-backed transforms return cheap String views because the scratch
    // arena owns their bytes. No per-string allocator pointer or deinit is
    // needed while the values stay inside this scratch scope.
    String normalizedPath = "//api//users".replace("//", "/", scratch.arena);
    String[2] routeParts = ["GET", normalizedPath];
    String routeKey = routeParts[].join(" ", scratch.arena);
    formatln!"scratch route key: {}"(routeKey);

    // Copy only when the value needs an independent lifetime.
    OwnedString persistentRoute = routeKey.copy(mallocAllocator());
    formatln!"persistent route key: {}"(persistentRoute);
    persistentRoute.deinit();
    return 0;
}
