module xtb.core.metadata;

enum versionMajor = 0;
enum versionMinor = 1;
enum versionPatch = 0;
enum versionString = "0.1.0";

version (Linux)
    enum operatingSystem = "linux";
else version (OSX)
    enum operatingSystem = "macos";
else version (Windows)
    enum operatingSystem = "windows";
else
    enum operatingSystem = "unknown";

version (X86_64)
    enum architecture = "x86_64";
else version (AArch64)
    enum architecture = "aarch64";
else version (X86)
    enum architecture = "x86";
else version (ARM)
    enum architecture = "arm";
else
    enum architecture = "unknown";

static assert(versionString == "0.1.0");
