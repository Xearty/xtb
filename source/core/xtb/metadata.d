module xtb.metadata;

enum version_major = 0;
enum version_minor = 1;
enum version_patch = 0;
enum version_string = version_major.stringof
    ~ "."
    ~ version_minor.stringof
    ~ "."
    ~ version_patch.stringof;

version (linux)
{
    enum operating_system = "linux";
}
else version (OSX)
{
    enum operating_system = "macos";
}
else version (Windows)
{
    enum operating_system = "windows";
}
else
{
    enum operating_system = "unknown";
}

version (X86_64)
{
    enum architecture = "x86_64";
}
else version (AArch64)
{
    enum architecture = "aarch64";
}
else version (X86)
{
    enum architecture = "x86";
}
else version (ARM)
{
    enum architecture = "arm";
}
else
{
    enum architecture = "unknown";
}

static assert(version_string == "0.1.0");
