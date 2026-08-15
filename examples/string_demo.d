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

    Arena routeArena = Arena.create(heap, 256);

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
    {
        routeArena.deinit();
        return 1;
    }
    formatln!"fallible arena result: {}"(fallibleArenaResult);

    // There is no deinit(copied), deinit(route.key), etc. All of those values
    // become invalid together when the region is reclaimed.
    routeArena.deinit();

    writeln("\n== scratch arena and lifetime promotion ==");

    // The helper creates several scratch String values, then promotes only the
    // result that must survive the scratch scope into independent ownership.
    OwnedString persistentKey = buildPersistentRouteKey(
        heap,
        "POST",
        "//v1//sessions",
    );
    formatln!"promoted key: {}"(persistentKey.view);

    writeln("\n== independently owned immutable strings ==");

    // Passing Allocator* selects independent ownership and returns OwnedString.
    OwnedString ownedCopy = "hello".copy(heap);
    OwnedString ownedConcat = ownedCopy.view.concat(" world", heap);
    OwnedString ownedReplace = ownedConcat.view.replace("world", "XTB", heap);
    OwnedString ownedEscape = "first\nsecond\t\"quoted\"".escape(heap);
    String[3] ownedParts = [
        ownedReplace.view,
        " | ",
        ownedEscape.view,
    ];
    OwnedString ownedJoin = ownedParts[].join("", heap);

    formatln!"owned copy:    {}"(ownedCopy.view);
    formatln!"owned concat:  {}"(ownedConcat.view);
    formatln!"owned replace: {}"(ownedReplace.view);
    formatln!"owned escape:  {}"(ownedEscape.view);
    formatln!"owned join:    {}"(ownedJoin.view);

    // Operations consume String views, not ownership. Borrowing an OwnedString
    // with .view never transfers or duplicates ownership.
    String borrowedFromOwner = ownedJoin.view;
    formatln!"borrowed from owner: {}"(borrowedFromOwner);

    // clone() is the explicit way to create another independent owner.
    OwnedString independentClone = ownedJoin.clone(heap);
    assert(independentClone.view.equal(ownedJoin.view));

    // Fallible independently owned transforms write into an empty owner.
    OwnedString fallibleOwned;
    if (!"fallible".tryConcat(" owner", heap, &fallibleOwned))
    {
        independentClone.deinit();
        ownedJoin.deinit();
        ownedEscape.deinit();
        ownedReplace.deinit();
        ownedConcat.deinit();
        ownedCopy.deinit();
        persistentKey.deinit();
        return 1;
    }
    formatln!"fallible owned result: {}"(fallibleOwned.view);

    writeln("\n== explicit ownership transfer ==");

    // release()/adopt() transfers the exact allocation without cloning it.
    OwnedString transferable = "transfer me".copy(heap);
    OwnedString.Released released = transferable.release();
    OwnedString adopted = OwnedString.adopt(&released);
    formatln!"adopted without copying: {}"(adopted.view);

    // XTB move also transfers ownership and reconstructs the source to .init.
    OwnedString moveSource = "move me".copy(heap);
    OwnedString moveDestination = move(moveSource);
    moveSource.deinit(); // moved-from owner is inert
    formatln!"moved owner: {}"(moveDestination.view);

    writeln("\n== mutable StringBuf ==");

    // StringBuf is the general mutable independently owned string. It keeps an
    // Allocator* because it may grow and replace its backing allocation.
    StringBuf builder = StringBuf.withCapacity(heap, 64);
    builder.append("GET ");
    builder.append("/v1/users/");
    builder.append(cast(dchar) 0x1f642);
    builder.append("  ");
    builder.trimAsciiEndInPlace();
    builder.replaceInPlace("GET", "PATCH");
    builder.appendEscaped("\nrequest-id=42");
    formatln!"mutable buffer: {}"(builder.view);

    // OwnedString.fromStringBuf consumes the mutable owner and freezes it into
    // exact-sized immutable storage. With the same allocator it can reuse the
    // allocation when StringBuf can shrink it to the exact size.
    OwnedString frozen = OwnedString.fromStringBuf(heap, &builder);
    formatln!"frozen buffer: {}"(frozen.view);

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
        temporaryBuilder.append("cache-key:");
        temporaryBuilder.append("users/42");
        temporaryBuilder.append('|');
        temporaryBuilder.append("generation=7");
        formatln!"arena StringBuf: {}"(temporaryBuilder.view);

        // StringBuf still follows its own explicit-lifetime protocol even when
        // its allocator is arena-backed. Individual deallocation is a no-op;
        // the scratch scope ultimately owns the bytes.
        temporaryBuilder.deinit();
    }

    writeln("\n== externally contextual ownership ==");

    // OwnedStringUnmanaged is for an independently owned allocation whose
    // allocator context is stored somewhere else. It is NOT the normal arena
    // representation; arena-backed immutable text should simply be String.
    OwnedStringUnmanaged compact = OwnedStringUnmanaged.fromString(
        heap,
        "allocator stored externally",
    );
    formatln!"unmanaged owner: {}"(compact.view);
    formatln!"sizeof String={}, OwnedStringUnmanaged={}, OwnedString={}"(
        String.sizeof,
        OwnedStringUnmanaged.sizeof,
        OwnedString.sizeof,
    );
    compact.deinit(heap);

    writeln("\n== C string interop ==");

    // OwnedString is exact-sized and deliberately does not promise a trailing
    // NUL. StringBuf can provide a checked C string when an API requires one.
    StringBuf cBuffer = StringBuf.fromString(heap, "api.example.com");
    const(char)* cName = cBuffer.checkedCString();
    formatln!"C string bytes: {}"(strlen(cName));
    cBuffer.deinit();

    // Independent owners are cleaned individually and explicitly.
    moveDestination.deinit();
    adopted.deinit();
    fallibleOwned.deinit();
    independentClone.deinit();
    frozen.deinit();
    ownedJoin.deinit();
    ownedEscape.deinit();
    ownedReplace.deinit();
    ownedConcat.deinit();
    ownedCopy.deinit();
    persistentKey.deinit();

    writeln("\nAll string lifetime models completed successfully.");
    return 0;
}
