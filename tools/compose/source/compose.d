module compose;

import std.algorithm : canFind, sort, uniq;
import std.array : array, join;
import std.conv : to;
import std.file : copy, exists, isFile, mkdirRecurse, readText, rename,
    remove, rmdirRecurse, write;
import std.json : parseJSON;
import std.path : absolutePath, baseName, buildPath, dirName;
import std.process : Config, environment, execute;
import std.string : endsWith, splitLines, startsWith, strip;
import std.uuid : randomUUID;

struct ComposeOptions
{
    string mode = "debug";
    string outputDirectory;
    string[] features;
}

string[] canonicalFeaturesFromDescribe(scope const(char)[] jsonText)
{
    auto document = parseJSON(jsonText);
    string[] features;

    foreach (packageValue; document["packages"].array)
    {
        const name = packageValue["name"].str;
        if (name.startsWith("xtb:"))
            features ~= name[4 .. $];
    }

    features.sort();
    return features.uniq.array;
}

string canonicalFeatureName(scope const(string)[] features)
{
    auto copy = features.dup;
    copy.sort();
    return copy.uniq.array.join("+");
}

string findRepositoryRoot(string start)
{
    auto current = absolutePath(start);
    for (;;)
    {
        if (exists(buildPath(current, "dub.sdl")) &&
            exists(buildPath(current, "source", "core", "dub.sdl")))
            return current;

        const parent = dirName(current);
        if (parent == current)
            throw new Exception("unable to locate the XTB repository root");
        current = parent;
    }
}

private string repositoryCacheKey(scope const(char)[] repositoryRoot)
{
    // A stable key keeps separate checkouts from rewriting one another's
    // generated recipes while leaving source-content validation to DUB.
    ulong hash = 14_695_981_039_346_656_037UL;
    foreach (value; cast(const(ubyte)[]) repositoryRoot)
    {
        hash ^= value;
        hash *= 1_099_511_628_211UL;
    }
    return to!string(hash);
}

private string composeCacheDirectory(string repositoryRoot)
{
    string dubHome = environment.get("DUB_HOME");
    if (!dubHome.length)
    {
        const home = environment.get("HOME");
        if (!home.length)
            throw new Exception("DUB_HOME and HOME are both unset");
        dubHome = buildPath(home, ".dub");
    }

    return buildPath(
        absolutePath(dubHome),
        "xtb-compose",
        repositoryCacheKey(repositoryRoot),
    );
}

private string[] availableFeatures(string repositoryRoot)
{
    enum prefix = `subPackage "source/`;
    string[] features;

    foreach (rawLine; readText(buildPath(repositoryRoot, "dub.sdl")).splitLines())
    {
        const line = rawLine.strip;
        if (!line.startsWith(prefix) || !line.endsWith(`"`))
            continue;

        const feature = line[prefix.length .. $ - 1];
        if (!feature.length || baseName(feature) != feature)
            throw new Exception("invalid subpackage path: " ~ line);
        if (!isFile(buildPath(repositoryRoot, "source", feature, "dub.sdl")))
            throw new Exception("subpackage is missing its recipe: " ~ feature);
        if (features.canFind(feature))
            throw new Exception("duplicate subpackage: " ~ feature);
        features ~= feature;
    }

    features.sort();
    if (!features.canFind("core"))
        throw new Exception("the root package does not declare the core subpackage");
    return features;
}

private void validateFeatures(
    scope const(string)[] requested,
    scope const(string)[] available,
)
{
    foreach (feature; requested)
        if (!available.canFind(feature))
            throw new Exception(
                "unknown subpackage: " ~ feature ~
                    "\navailable subpackages: " ~ available.join(", "),
            );
}

private string quoteSdl(string value)
{
    string result = "\"";
    foreach (ch; value)
    {
        switch (ch)
        {
            case '\\':
                result ~= "\\\\";
                break;
            case '"':
                result ~= "\\\"";
                break;
            case '\n':
                result ~= "\\n";
                break;
            case '\r':
                result ~= "\\r";
                break;
            case '\t':
                result ~= "\\t";
                break;
            default:
                result ~= ch;
                break;
        }
    }
    return result ~ '"';
}

string aggregatorRecipe(string repositoryRoot, string[] requested)
{
    string result = q"SDL
name "xtb-compose"
targetType "staticLibrary"
targetName "xtb"
sourceFiles "anchor.d"
buildOptions "betterC"
buildRequirements "disallowDeprecations"
dflags "-preview=dip1000" platform="ldc"

buildType "release-safe" {
    buildOptions "optimize" "inline"
    dflags "-fno-delete-null-pointer-checks" platform="ldc"
}

SDL";

    auto roots = requested.dup;
    roots ~= "core";
    roots.sort();
    foreach (feature; roots.uniq)
        result ~= "dependency \"xtb:" ~ feature ~ "\" path=" ~ quoteSdl(repositoryRoot) ~ "\n";
    return result;
}

void writeIfChanged(string path, string contents)
{
    if (exists(path) && readText(path) == contents)
        return;
    write(path, contents);
}

string dubBuildType(string mode)
{
    switch (mode)
    {
        case "debug":
            return "debug";
        case "release-safe":
            return "release-safe";
        case "release-fast":
            return "release-nobounds";
        default:
            throw new Exception("unknown build mode: " ~ mode);
    }
}

private string[] archiveMembers(string archiver, string archive)
{
    auto listed = execute([archiver, "t", archive]);
    if (listed.status != 0)
        throw new Exception("unable to inspect static archive " ~ archive ~ ":\n" ~ listed.output);

    string[] members;
    foreach (line; listed.output.splitLines())
        if (line.length)
            members ~= line;
    return members;
}

private void executeChecked(string[] command, string workingDirectory = null)
{
    auto result = execute(command, null, Config.none, size_t.max, workingDirectory);
    if (result.status != 0)
        throw new Exception(command[0] ~ " failed:\n" ~ result.output);
}

private void flattenStaticArchive(
    string library,
    string dependency,
    string workingRoot,
)
{
    if (!exists(library) || !isFile(library))
        throw new Exception("XTB archive does not exist: " ~ library);
    if (!exists(dependency) || !isFile(dependency))
        throw new Exception("diagnostics native archive does not exist: " ~ dependency);

    const archiver = environment.get("AR", "ar");
    const ranlib = environment.get("RANLIB", "ranlib");
    const dependencyMembers = archiveMembers(archiver, dependency);
    if (!dependencyMembers.length)
        throw new Exception("diagnostics native archive is empty: " ~ dependency);

    string[] seenMembers;
    foreach (member; dependencyMembers)
    {
        if (baseName(member) != member)
            throw new Exception("diagnostics native archive contains a non-flat member: " ~ member);
        if (seenMembers.canFind(member))
            throw new Exception("diagnostics native archive contains duplicate members: " ~ member);
        seenMembers ~= member;
    }

    const stagingRoot = buildPath(
        workingRoot,
        ".diagnostics-native-" ~ randomUUID().toString(),
    );
    const extractedRoot = buildPath(stagingRoot, "objects");
    const stagedLibrary = buildPath(stagingRoot, "libxtb.a");
    mkdirRecurse(extractedRoot);
    scope (exit)
        if (exists(stagingRoot))
            rmdirRecurse(stagingRoot);

    executeChecked([archiver, "x", dependency], extractedRoot);
    copy(library, stagedLibrary);

    // Static linkers do not search an archive nested inside another archive.
    // Append the dependency's object members instead. Their archive member
    // names are prefixed to avoid replacing an identically named XTB object;
    // the native symbols themselves remain unchanged.
    string[] appendCommand = [archiver, "rcsD", stagedLibrary];
    foreach (member; dependencyMembers)
    {
        const objectPath = buildPath(extractedRoot, member);
        if (!exists(objectPath) || !isFile(objectPath))
            throw new Exception("archiver did not extract diagnostics member: " ~ member);
        const privateObjectPath = buildPath(
            extractedRoot,
            "xtb_diagnostics_native_" ~ member,
        );
        rename(objectPath, privateObjectPath);
        appendCommand ~= privateObjectPath;
    }

    executeChecked(appendCommand);
    executeChecked([ranlib, "-D", stagedLibrary]);
    rename(stagedLibrary, library);
}

private string publishArchive(
    string source,
    string outputRoot,
    string diagnosticsNativeArchive = null,
)
{
    if (!exists(source) || !isFile(source))
        throw new Exception("XTB cache archive does not exist: " ~ source);

    mkdirRecurse(outputRoot);
    const stagingRoot = buildPath(
        outputRoot,
        ".publish-" ~ randomUUID().toString(),
    );
    const stagedLibrary = buildPath(stagingRoot, "libxtb.a");
    mkdirRecurse(stagingRoot);
    scope (exit)
        if (exists(stagingRoot))
            rmdirRecurse(stagingRoot);

    copy(source, stagedLibrary);
    if (diagnosticsNativeArchive.length)
        flattenStaticArchive(stagedLibrary, diagnosticsNativeArchive, stagingRoot);

    const output = buildPath(outputRoot, "libxtb.a");
    if (exists(output))
        remove(output);
    rename(stagedLibrary, output);
    return output;
}

string compose(ComposeOptions options, string workingDirectory)
{
    const repositoryRoot = findRepositoryRoot(workingDirectory);
    return composeInRepository(
        options,
        repositoryRoot,
        composeCacheDirectory(repositoryRoot),
    );
}

private string composeInRepository(
    ComposeOptions options,
    string repositoryRoot,
    string cacheRoot,
)
{
    const buildType = dubBuildType(options.mode);
    const features = availableFeatures(repositoryRoot);
    validateFeatures(options.features, features);
    const compiler = environment.get("DC", "ldc2");
    const requestedKey = canonicalFeatureName(options.features.length ? options.features : ["core"]);
    const modeRoot = buildPath(repositoryRoot, "build", "compose", options.mode);
    const resolveRoot = buildPath(cacheRoot, options.mode, requestedKey);
    mkdirRecurse(resolveRoot);

    const recipe = aggregatorRecipe(repositoryRoot, options.features);
    writeIfChanged(buildPath(resolveRoot, "dub.sdl"), recipe);
    writeIfChanged(buildPath(resolveRoot, "anchor.d"), "module xtb_compose_anchor;\n");
    writeIfChanged(buildPath(resolveRoot, "dub.selections.json"), "{\n\t\"fileVersion\": 1,\n\t\"versions\": {}\n}\n");

    auto describe = execute([
        "dub", "describe",
        "--root=" ~ resolveRoot,
        "--compiler=" ~ compiler,
        "--skip-registry=all",
    ]);
    if (describe.status != 0)
        throw new Exception("DUB dependency resolution failed:\n" ~ describe.output);

    const resolved = canonicalFeaturesFromDescribe(describe.output);
    validateFeatures(resolved, features);
    if (!resolved.canFind("core"))
        throw new Exception("DUB resolved a subpackage closure without core");
    const canonical = canonicalFeatureName(resolved);
    string diagnosticsNativeArchive;
    version (linux)
    {
        if (resolved.canFind("diagnostics"))
        {
            const configuredArchive = environment.get("XTB_DIAGNOSTICS_NATIVE_ARCHIVE");
            if (!configuredArchive.length)
                throw new Exception("diagnostics native archive is not configured");
            diagnosticsNativeArchive = absolutePath(configuredArchive);
            if (!exists(diagnosticsNativeArchive) || !isFile(diagnosticsNativeArchive))
                throw new Exception("diagnostics native archive does not exist: " ~ diagnosticsNativeArchive);
        }
    }

    auto env = environment.toAA();
    const checked = options.mode != "release-fast";
    env["DFLAGS"] = "-boundscheck=" ~ (checked ? "on" : "off");

    string[] command = [
        "dub", "build",
        "--root=" ~ resolveRoot,
        "--compiler=" ~ compiler,
        "--skip-registry=all",
        "--parallel",
        "--build=" ~ buildType,
    ];
    if (checked)
        command ~= "--d-version=XTB_Checked";

    auto built = execute(command, env, Config.none);
    if (built.status != 0)
        throw new Exception("DUB build failed:\n" ~ built.output);

    const cachedLibrary = buildPath(resolveRoot, "libxtb.a");
    if (!exists(cachedLibrary))
        throw new Exception("DUB completed without producing " ~ cachedLibrary);

    const library = publishArchive(
        cachedLibrary,
        buildPath(modeRoot, canonical),
        diagnosticsNativeArchive,
    );

    if (options.outputDirectory.length)
        return publishArchive(library, absolutePath(options.outputDirectory));

    return library;
}

unittest
{
    assert(canonicalFeatureName(["math", "core", "log", "core"]) == "core+log+math");
}

unittest
{
    const json = `{"packages":[{"name":"xtb-compose"},{"name":"xtb:os"},{"name":"xtb:core"},{"name":"xtb:log"}]}`;
    assert(canonicalFeatureName(canonicalFeaturesFromDescribe(json)) == "core+log+os");
}

unittest
{
    import std.file : tempDir;

    const root = buildPath(tempDir(), "xtb-compose-input-test-" ~ randomUUID().toString());
    const coreRoot = buildPath(root, "source", "core");
    mkdirRecurse(coreRoot);
    scope (exit)
        if (exists(root))
            rmdirRecurse(root);
    write(buildPath(root, "dub.sdl"), `subPackage "source/core"` ~ "\n");
    write(buildPath(coreRoot, "dub.sdl"), `name "core"` ~ "\n");

    void expectRejected(ComposeOptions options)
    {
        bool rejected;
        try
            compose(options, root);
        catch (Exception)
            rejected = true;
        assert(rejected);
        assert(!exists(buildPath(root, "build")));
    }

    ComposeOptions invalidMode;
    invalidMode.mode = "../../escaped-mode";
    expectRejected(invalidMode);
    assert(!exists(buildPath(root, "escaped-mode")));

    ComposeOptions traversalFeature;
    traversalFeature.features = ["../../escaped-feature"];
    expectRejected(traversalFeature);

    const absoluteFeature = buildPath(root, "escaped-absolute-feature");
    ComposeOptions absoluteFeatureOptions;
    absoluteFeatureOptions.features = [absoluteFeature];
    expectRejected(absoluteFeatureOptions);
    assert(!exists(absoluteFeature));

    ComposeOptions unknownFeature;
    unknownFeature.features = ["unknown"];
    expectRejected(unknownFeature);
}

unittest
{
    import std.file : tempDir, timeLastModified;

    const root = buildPath(tempDir(), "xtb-compose-cache-test-" ~ randomUUID().toString());
    const coreRoot = buildPath(root, "source", "core");
    const cacheRoot = buildPath(root, "cache");
    mkdirRecurse(coreRoot);
    scope (exit)
        if (exists(root))
            rmdirRecurse(root);

    write(buildPath(root, "dub.sdl"), q"SDL
name "xtb"
targetType "none"
subPackage "source/core"
SDL");
    write(buildPath(coreRoot, "dub.sdl"), q"SDL
name "core"
targetType "sourceLibrary"
sourcePaths "."
importPaths "."
buildOptions "betterC"
SDL");
    const coreSource = buildPath(coreRoot, "cache_test_core.d");
    write(coreSource, q"D
module cache_test_core;

nothrow @nogc:

int cacheTestValue()
{
    return 42;
}
D");

    ComposeOptions options;
    options.mode = "release-safe";
    options.features = ["core"];
    const firstOutput = composeInRepository(options, root, cacheRoot);
    assert(isFile(firstOutput));

    const cachedLibrary = buildPath(cacheRoot, "release-safe", "core", "libxtb.a");
    assert(isFile(cachedLibrary));
    const cachedModificationTime = timeLastModified(cachedLibrary);

    rmdirRecurse(buildPath(root, "build"));
    assert(!exists(firstOutput));
    assert(isFile(cachedLibrary));

    const restoredOutput = composeInRepository(options, root, cacheRoot);
    assert(isFile(restoredOutput));
    assert(timeLastModified(cachedLibrary) == cachedModificationTime);

    write(coreSource, q"D
module cache_test_core;

nothrow @nogc:

int cacheTestValue()
{
    return 43;
}
D");
    composeInRepository(options, root, cacheRoot);
    assert(timeLastModified(cachedLibrary) > cachedModificationTime);
}

version (linux) unittest
{
    import std.file : tempDir;

    const root = buildPath(tempDir(), "xtb-compose-archive-test-" ~ randomUUID().toString());
    mkdirRecurse(root);
    scope (exit)
        if (exists(root))
            rmdirRecurse(root);

    const baseSource = buildPath(root, "base.c");
    const dependencySource = buildPath(root, "dependency.c");
    const consumerSource = buildPath(root, "consumer.c");
    const baseObject = buildPath(root, "base.o");
    const dependencyObject = buildPath(root, "dependency.o");
    const baseArchive = buildPath(root, "libxtb.a");
    const dependencyArchive = buildPath(root, "libnative.a");
    const consumer = buildPath(root, "consumer");
    write(baseSource, "int xtb_compose_base(void) { return 5; }\n");
    write(dependencySource, "int xtb_compose_dependency(void) { return 7; }\n");
    write(consumerSource,
        "int xtb_compose_base(void);\n" ~
            "int xtb_compose_dependency(void);\n" ~
            "int main(void) { return xtb_compose_base() + xtb_compose_dependency() == 12 ? 0 : 1; }\n");

    const compiler = environment.get("CC", "cc");
    const archiver = environment.get("AR", "ar");
    executeChecked([compiler, "-c", baseSource, "-o", baseObject]);
    executeChecked([compiler, "-c", dependencySource, "-o", dependencyObject]);
    executeChecked([archiver, "rcsD", baseArchive, baseObject]);
    executeChecked([archiver, "rcsD", dependencyArchive, dependencyObject]);

    flattenStaticArchive(baseArchive, dependencyArchive, root);
    // Re-finalizing the same archive must replace dependency members rather
    // than accumulating duplicate copies.
    flattenStaticArchive(baseArchive, dependencyArchive, root);
    const members = archiveMembers(archiver, baseArchive);
    assert(members.canFind("base.o"));
    assert(members.canFind("xtb_diagnostics_native_dependency.o"));
    assert(!members.canFind("dependency.o"));
    size_t dependencyMemberCount;
    foreach (member; members)
        if (member == "xtb_diagnostics_native_dependency.o")
            ++dependencyMemberCount;
    assert(dependencyMemberCount == 1);

    executeChecked([compiler, consumerSource, baseArchive, "-o", consumer]);
    executeChecked([consumer]);
}
