module examples.string_demo;

import core.stdc.string : strlen;
import xtb.core;

private struct Route
{
    String method;
    String path;
    String key;
}

private Route* buildArenaRoute(
    Arena* arena,
    String method,
    String rawPath,
)
nothrow @nogc
{
    Route* route = arena.create!Route();

    // The arena owns these allocations. Route stores only cheap String views.
    route.method = method.copy(arena);
    route.path = rawPath.replace("//", "/", arena);

    String[2] keyParts = [route.method, route.path];
    route.key = keyParts[].join(" ", arena);
    return route;
}

private OwnedString buildPersistentRouteKey(
    Allocator* allocator,
    String method,
    String rawPath,
)
nothrow @nogc
{
    // Scratch strings are ideal for intermediate transformations. They are
    // reclaimed together when this scope ends.
    ScratchScope scratch = ScratchScope.acquire();
    String normalized = rawPath.replace("//", "/", scratch.arena);
    String[2] parts = [method, normalized];
    String temporaryKey = parts[].join(" ", scratch.arena);

    // Promotion across lifetime domains is explicit: Arena* -> String,
    // Allocator* -> OwnedString.
    return temporaryKey.copy(allocator);
}

extern (C) int main() nothrow @nogc
{
    ThreadContextScope context = ThreadContextScope.acquire();
    Allocator* heap = mallocAllocator();

    writeln("== borrowed String views ==");

    // String never owns memory. Literals and slices are just borrowed UTF-8
    // views and need no cleanup.
    String raw = "  /srv/config/app.toml  ";
    String trimmed = raw.trimAscii();
    String fileName = trimmed.baseName();
    String stem = fileName.stripExtension();
    formatln!"raw='{}', trimmed='{}', file='{}', stem='{}'"(
        raw,
        trimmed,
        fileName,
        stem,
    );

    assert(trimmed.startsWith("/srv/"));
    assert(trimmed.endsWith(".toml"));
    assert(stem.equal("app"));

    // External bytes can be validated before becoming a borrowed String.
    const u8[7] externalBytes = ['c', 'a', 'f', 0xc3, 0xa9, '!', '\n'];
    const validated = externalBytes[].asString;
    if (validated.failed)
        return 1;
    formatln!"validated UTF-8: {}"(validated.value);

    writeln("\n== arena-owned immutable strings ==");

    {
        Arena routeArena = Arena.create(heap, 256);
        scope (exit)
            routeArena.deinit();

        // Passing Arena* selects region ownership and returns plain String.
        String copied = "api".copy(&routeArena);
        String concatenated = copied.concat(".example.com", &routeArena);
        String normalized = "//v1//users//42".replace("//", "/", &routeArena);
        String escaped = "user=alice\nrole=admin".escape(&routeArena);
        String[3] addressParts = ["https://", concatenated, normalized];
        String address = addressParts[].join("", &routeArena);

        formatln!"copy:    {}"(copied);
        formatln!"concat:  {}"(concatenated);
        formatln!"replace: {}"(normalized);
        formatln!"escape:  {}"(escaped);
        formatln!"join:    {}"(address);

        // A whole object graph can contain String fields without embedding an
        // allocator pointer in every field. The arena is the sole owner.
        Route* route = buildArenaRoute(&routeArena, "GET", "//v1//users//42");
        formatln!"route: {}"(route.key);

        // The try API follows the same ownership rule. It commits the output only
        // after the arena allocation succeeds.
        String fallibleArenaResult = "unchanged";
        if (!"alpha//beta".tryReplace(
                "//",
                "/",
                &routeArena,
                &fallibleArenaResult,
            ))
            return 1;
        formatln!"fallible arena result: {}"(fallibleArenaResult);

        // There is no deinit(copied), deinit(route.key), etc. All of those
        // values become invalid together when routeArena is deinitialized at
        // the end of this block.
    }

    writeln("\n== scratch arena and lifetime promotion ==");

    {
        // The helper creates several scratch String values, then promotes only
        // the result that must survive the scratch scope into independent
        // ownership.
        OwnedString persistentKey = buildPersistentRouteKey(
            heap,
            "POST",
            "//v1//sessions",
        );
        scope (exit)
            persistentKey.deinit();
        formatln!"promoted key: {}"(persistentKey);
    }

    writeln("\n== independently owned immutable strings ==");

    {
        // Passing Allocator* selects independent ownership and returns
        // OwnedString. Each owner lives until the end of this block, so its
        // cleanup is registered immediately next to its declaration.
        OwnedString ownedCopy = "hello".copy(heap);
        scope (exit)
            ownedCopy.deinit();

        // OwnedString forwards immutable transforms directly. Omitting the
        // allocator reuses the source owner's allocator.
        OwnedString ownedConcat = ownedCopy.concat(" world");
        scope (exit)
            ownedConcat.deinit();

        OwnedString ownedReplace = ownedConcat.replace("world", "XTB");
        scope (exit)
            ownedReplace.deinit();

        OwnedString ownedWithControls = ownedReplace.concat(
            "\nsecond\t\"quoted\"",
        );
        scope (exit)
            ownedWithControls.deinit();

        OwnedString ownedEscape = ownedWithControls.escape();
        scope (exit)
            ownedEscape.deinit();

        String[3] ownedParts = [
            ownedReplace.view,
            " | ",
            ownedEscape.view,
        ];
        OwnedString ownedJoin = ownedParts[].join("", heap);
        scope (exit)
            ownedJoin.deinit();

        formatln!"owned copy:    {}"(ownedCopy);
        formatln!"owned concat:  {}"(ownedConcat);
        formatln!"owned replace: {}"(ownedReplace);
        formatln!"owned escape:  {}"(ownedEscape);
        formatln!"owned join:    {}"(ownedJoin);

        // Operations consume String views, not ownership. Borrowing an
        // OwnedString with .view never transfers or duplicates ownership.
        String borrowedFromOwner = ownedJoin.view;
        formatln!"borrowed from owner: {}"(borrowedFromOwner);

        // clone() is the explicit way to create another independent owner.
        OwnedString independentClone = ownedJoin.clone();
        scope (exit)
            independentClone.deinit();
        assert(independentClone == ownedJoin);

        // Fallible independently owned transforms write into an empty owner.
        // The scope guard is safe even if the operation fails before the owner
        // acquires storage because the zero state is deinitializable.
        OwnedString fallibleOwned;
        scope (exit)
            fallibleOwned.deinit();
        if (!ownedCopy.tryConcat(" owner", &fallibleOwned))
            return 1;
        formatln!"fallible owned result: {}"(fallibleOwned);
    }

    writeln("\n== explicit ownership transfer ==");

    {
        // transferable is consumed before the end of the scope, so it does not
        // get a scope(exit) cleanup. The cleanup obligation moves into adopted.
        OwnedString transferable = "transfer me".copy(heap);
        OwnedString.Released released = transferable.release();
        OwnedString adopted = OwnedString.adopt(&released);
        scope (exit)
            adopted.deinit();
        formatln!"adopted without copying: {}"(adopted);

        // moveSource is likewise consumed immediately. The destination owns
        // the allocation for the rest of the block and gets the scope guard.
        OwnedString moveSource = "move me".copy(heap);
        OwnedString moveDestination = move(moveSource);
        scope (exit)
            moveDestination.deinit();
        formatln!"moved owner: {}"(moveDestination);
    }

    writeln("\n== mutable StringBuf ==");

    {
        // builder is consumed by intoOwnedString before the end of the block, so
        // the final owner is frozen, not builder.
        StringBuf builder = StringBuf.withCapacity(heap, 64);
        builder.append("GET ");
        builder.append("/v1/users/");
        builder.append(cast(dchar) 0x1f642);
        builder.append("  ");
        builder.trimAsciiEndInPlace();

        OwnedString originalMethod = builder.replace("GET", "HEAD", heap);
        scope (exit)
            originalMethod.deinit();
        formatln!"immutable replacement: {}"(originalMethod);

        builder.replaceInPlace("GET", "PATCH");
        builder.append("\nrequest-id=42");
        builder.escapeInPlace();
        formatln!"mutable buffer: {}"(builder);

        // intoOwnedString consumes the mutable owner and freezes it into
        // exact-sized immutable storage. With no explicit allocator it reuses
        // the StringBuf allocator and can adopt the allocation after shrinking.
        OwnedString frozen = builder.intoOwnedString();
        scope (exit)
            frozen.deinit();
        formatln!"frozen buffer: {}"(frozen);
    }

    writeln("\n== temporary mutable builder in an arena ==");

    {
        ScratchScope scratch = ScratchScope.acquire();

        // This is useful when mutation is truly required. Reserve enough up
        // front when possible: arena reallocations cannot reclaim superseded
        // buffers until the scratch scope rewinds. Prefer the Arena* immutable
        // transforms above when the output size can be computed exactly.
        StringBuf temporaryBuilder = StringBuf.withCapacity(
            scratch.allocator,
            96,
        );
        scope (exit)
            temporaryBuilder.deinit();
        temporaryBuilder.append("cache-key:");
        temporaryBuilder.append("users/42");
        temporaryBuilder.append('|');
        temporaryBuilder.append("generation=7");
        formatln!"arena StringBuf: {}"(temporaryBuilder);

        // StringBuf still follows its own explicit-lifetime protocol even when
        // its allocator is arena-backed. Individual deallocation is a no-op;
        // the ScratchScope ultimately owns the bytes.
    }

    writeln("\n== externally contextual ownership ==");

    {
        // OwnedStringUnmanaged is for an independently owned allocation whose
        // allocator context is stored somewhere else. It is NOT the normal
        // arena representation; arena-backed immutable text should be String.
        OwnedStringUnmanaged compact = OwnedStringUnmanaged.fromString(
            heap,
            "allocator stored externally",
        );
        scope (exit)
            compact.deinit(heap);
        formatln!"unmanaged owner: {}"(compact);
        formatln!"sizeof String={}, OwnedStringUnmanaged={}, OwnedString={}"(
            String.sizeof,
            OwnedStringUnmanaged.sizeof,
            OwnedString.sizeof,
        );
    }

    writeln("\n== C string interop ==");

    {
        // OwnedString is exact-sized and deliberately does not promise a
        // trailing NUL. StringBuf can provide a checked C string when an API
        // requires one.
        StringBuf cBuffer = StringBuf.fromString(heap, "api.example.com");
        scope (exit)
            cBuffer.deinit();
        const(char)* cName = cBuffer.checkedCString();
        formatln!"C string bytes: {}"(strlen(cName));
    }

    writeln("\nAll string lifetime models completed successfully.");
    return 0;
}
