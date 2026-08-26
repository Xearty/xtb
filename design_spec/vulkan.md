# Vulkan library design specification

## Status and scope

This document defines the intended Vulkan architecture for xtb. It is a design
contract only; no Vulkan implementation exists yet. The implementation belongs
under `xtb.graphics.vulkan`, must compile with `-betterC`, and must preserve the
dependency direction described in `docs/architecture.md`.

The library must provide two independently useful layers:

1. Generated Vulkan ABI declarations and explicit function-pointer dispatch.
2. An optional bootstrap layer that creates a useful instance, selects a
   physical device and queues, creates a logical device, and installs optional
   validation diagnostics according to caller-supplied policy.

The bootstrap layer is a convenience facility, not the only way to use the
bindings. A caller must be able to load commands and construct Vulkan objects
manually without accepting device-selection or feature policy from xtb.

All ordinary project constraints apply. Production code must not use the GC,
exceptions, classes, runtime reflection, module constructors, hidden heap
allocation, or mutable process-wide state. Unsupported platforms must retain a
compilable public API and return an explicit unsupported error without leaving
partially initialized output.

## Goals

The Vulkan package must:

- build without requiring the Vulkan SDK on the consumer's machine;
- load the Vulkan runtime dynamically by default, so a missing runtime is an
  ordinary setup error rather than a program load failure;
- expose exact Vulkan ABI names and types for raw usage;
- keep global, instance, and device command lifetimes explicit;
- support multiple instances and multiple devices in the same process;
- avoid a global current instance, current device, or mutable dispatch table;
- make required, preferred, and disabled capabilities distinguishable;
- negotiate API versions rather than blindly assuming the generated binding's
  newest version is available;
- query layers, extensions, features, properties, queue families, and surface
  support before using them;
- choose a deterministic suitable device and queue topology under a documented
  default policy while allowing caller overrides;
- make validation, diagnostics, presentation, and portability policy explicit;
- clean up every partially created Vulkan object when setup fails;
- leave output owners in their empty state on failure;
- use fixed-layout, non-copyable owners with explicit `deinit`; and
- be testable without a physical GPU or installed Vulkan runtime.

## Initial non-goals

The first bootstrap implementation must not attempt to provide:

- a renderer, render graph, command scheduler, frame loop, or resource manager;
- automatic swapchain creation or recreation;
- a default render pass, pipeline, descriptor layout, or synchronization model;
- shader compilation or SPIR-V reflection;
- a window-system abstraction;
- global forwarding functions backed by an implicit current context;
- transparent fallback to OpenGL or another graphics API;
- direct loading of vendor drivers while bypassing the platform Vulkan loader;
- automatic exposure of `xtb.memory.Allocator` as
  `VkAllocationCallbacks`; or
- a promise that every Vulkan extension receives a high-level wrapper.

Swapchain format, present mode, extent, image count, and recreation policy are
application or renderer concerns. They may receive a separate helper later,
but they do not belong in basic instance/device bootstrap.

## Package organization

Use focused modules rather than one generated monolith:

```text
source/xtb/graphics/vulkan/
├── binding/
│   ├── package.d             # stable raw-binding imports
│   ├── types.d               # handles, structs, enums, bitmasks
│   ├── constants.d           # versions, names, limits
│   ├── commands.d            # PFN_vk* declarations
│   └── platform_*.d          # guarded WSI declarations when needed
├── library.d                 # loader-library lifetime and initial resolver
├── dispatch.d                # global/instance/device command tables
├── error.d                   # VulkanError and operation context
├── options.d                 # copyable bootstrap policy values
├── device_selection.d        # candidates, requirements, scoring, queues
├── surface.d                 # window-system provider contract
├── debug.d                   # debug-utils callback and messenger ownership
├── bootstrap.d               # transactional convenience setup
└── package.d                 # deliberate stable public surface
```

Do not create empty placeholders. Add modules with the first coherent behavior
that belongs in them. The exact generated binding split may change if compiler
performance measurements justify it, but generated ABI declarations must stay
separate from handwritten policy.

Opening dynamic libraries is operating-system work. The preferred prerequisite
is a platform-neutral `xtb.os.dynamic_library` owner, with supported native
backends and a compiling unsupported backend. Vulkan code should not duplicate
`dlopen`, `dlsym`, `LoadLibrary`, or equivalent lifetime handling throughout
the graphics package.

## Generated Vulkan bindings

Raw declarations must be generated from a pinned revision of Khronos `vk.xml`,
not copied from the archived C++ project or manually maintained. The repository
must record both the registry revision and the Vulkan header/specification
version represented by the generated source.

Generated D source is committed. Regeneration is a maintainer operation exposed
through the xtb flake and justfile; normal builds must not download the
registry, run a generator, or require an installed SDK.

Generation must preserve the foreign API spelling:

- `Vk*` for Vulkan types;
- `VK_*` for Vulkan constants; and
- `PFN_vk*` and `vk*` for function-pointer types and command fields.

The project's ordinary naming conventions do not justify renaming a foreign
ABI. Handwritten xtb policy types and functions continue to use normal D names.

Bindings must use the platform calling convention represented by `VKAPI_CALL`,
including architecture-specific differences. Platform WSI declarations are
guarded so the library continues to compile without headers for every native
window system. ABI tests must compare representative D sizes, alignments,
offsets, enum values, bit values, handles, and callback signatures against the
official C headers.

The generated binding version defines what xtb knows how to name and load. It
does not assert that the runtime, driver, device, or enabled extension supports
all generated commands.

## Dynamic library and resolver ownership

`VulkanLibrary` owns, or explicitly borrows, the source of
`vkGetInstanceProcAddr`. In the ordinary dynamic case it owns the native
library handle and unloads it in `deinit`:

```d
struct VulkanLibrary
{
    private NativeLibrary native_;
    private PFN_vkGetInstanceProcAddr getInstanceProcAddr_;
    private bool ownsNativeLibrary_;

    @disable this(this);
    ~this();

    bool valid() const pure @safe;
    PFN_vkGetInstanceProcAddr resolver() const @system;
}
```

The exact private representation is not public API. A second construction path
must accept a caller-supplied `PFN_vkGetInstanceProcAddr`. It supports tests,
embedders, platforms whose runtime supplies the resolver directly, and callers
that already manage loader lifetime. That form is borrowed and must not unload
anything. Its source must remain alive through every instance and device made
from it.

The Vulkan library must remain loaded until all dispatch pointers obtained from
it have stopped being used and all associated instances and devices have been
destroyed. A `VulkanContext` therefore destroys Vulkan children before
releasing its `VulkanLibrary`.

The primary design does not link ordinary calls directly against the Vulkan
loader. A separately tested linked-loader mode could be added later, but it
must feed the same resolver and dispatch abstractions rather than introduce a
second ownership model.

## Command loading and dispatch tables

Loading follows Vulkan's three command scopes:

1. Obtain `vkGetInstanceProcAddr` through the platform loader mechanism or an
   injected resolver.
2. With a null `VkInstance`, load global commands such as
   `vkEnumerateInstanceVersion`, `vkEnumerateInstanceExtensionProperties`,
   `vkEnumerateInstanceLayerProperties`, and `vkCreateInstance`.
3. After instance creation, use `vkGetInstanceProcAddr(instance, name)` to fill
   an instance-specific table.
4. Obtain `vkGetDeviceProcAddr` from the instance table and, after device
   creation, use it to fill a device-specific table.

Device commands should be loaded with `vkGetDeviceProcAddr`, not routed through
`vkGetInstanceProcAddr`. The returned pointers are specialized for the logical
device and may avoid an extra loader dispatch step. They must be called only
with that device or its children.

Dispatch tables are plain typed function-pointer values associated with the
handle used to load them:

```d
struct GlobalCommands
{
    PFN_vkGetInstanceProcAddr vkGetInstanceProcAddr;
    PFN_vkEnumerateInstanceVersion vkEnumerateInstanceVersion;
    PFN_vkEnumerateInstanceExtensionProperties
        vkEnumerateInstanceExtensionProperties;
    PFN_vkEnumerateInstanceLayerProperties vkEnumerateInstanceLayerProperties;
    PFN_vkCreateInstance vkCreateInstance;
}

struct InstanceCommands
{
    VkInstance instance;
    PFN_vkDestroyInstance vkDestroyInstance;
    PFN_vkEnumeratePhysicalDevices vkEnumeratePhysicalDevices;
    PFN_vkGetPhysicalDeviceProperties2 vkGetPhysicalDeviceProperties2;
    PFN_vkGetPhysicalDeviceFeatures2 vkGetPhysicalDeviceFeatures2;
    PFN_vkCreateDevice vkCreateDevice;
    PFN_vkGetDeviceProcAddr vkGetDeviceProcAddr;
    // Enabled core and instance-extension commands continue here.
}

struct DeviceCommands
{
    VkDevice device;
    PFN_vkDestroyDevice vkDestroyDevice;
    PFN_vkGetDeviceQueue2 vkGetDeviceQueue2;
    PFN_vkQueueSubmit2 vkQueueSubmit2;
    // Enabled core and device-extension commands continue here.
}
```

These sketches show association, not a final promise that the handle fields
will remain publicly mutable. Bootstrap accessors should expose borrowed const
tables after setup so command pointers cannot change underneath users.

A required command missing for the negotiated API version or an enabled
extension is setup failure. Commands that belong to unavailable or disabled
extensions may remain null in the raw table. The bootstrap layer must never
present a capability as enabled merely because querying its command name
returned a non-null pointer. Version, extension, and feature enablement remain
the authority.

Promoted commands may have both core and extension spellings. Raw dispatch
retains those actual entry points. A future capability wrapper may select a
core command or its enabled extension fallback, but it must state that policy
explicitly rather than silently rewriting the raw binding.

## Why Vulkan commands are not process-global D functions

Dynamic loading means normal Vulkan calls are typed fields rather than
ordinary globally linked D functions. Raw usage is deliberately explicit:

```d
context.deviceCommands().vkCreateBuffer(
    context.device(),
    &createInfo,
    null,
    &buffer,
);
```

The word *global* in Vulkan's "global command" classification does not mean a
command must be a global D declaration. It means that the command does not
require an instance dispatchable object. `vkCreateInstance` is a Vulkan global
command but still lives in `GlobalCommands` in the dynamic interface.

Instance command pointers may be specific to one `VkInstance`. Device command
pointers obtained from `vkGetDeviceProcAddr` are specific to one `VkDevice` and
its children. A mutable process-global table would silently assume one active
context and could route calls through the wrong device after a second context
was initialized.

Do not provide global forwarding functions backed by a current context, TLS,
or last-created device. They hide ownership, complicate threads, make tests
order-dependent, and conflict with the project's explicit-state policy.

Ergonomic wrappers are allowed when they still carry the dispatch source
explicitly. For example, a borrowed `VulkanDevice` view could pair a handle and
`const(DeviceCommands)*` and offer selected helpers. The raw table remains
available and raw command names remain unchanged. Manually wrapping every
Vulkan command is not a goal because it would duplicate the specification and
create a large maintenance surface for cosmetic benefit.

## Bootstrap owner and lifetime

The all-in-one convenience owner is non-copyable:

```d
struct VulkanContext
{
    @disable this(this);
    ~this();

    bool valid() const pure @safe;
    void deinit();

    VkInstance instance() const @safe;
    VkPhysicalDevice physicalDevice() const @safe;
    VkDevice device() const @safe;
    const(InstanceCommands)* instanceCommands() const return @system;
    const(DeviceCommands)* deviceCommands() const return @system;
}
```

Its zero state is empty and valid. `deinit` is idempotent and destroys owned
resources in dependency order:

1. logical-device children owned by the bootstrap, if any;
2. `VkDevice`;
3. an owned `VkSurfaceKHR`;
4. the debug-utils messenger;
5. `VkInstance`; and
6. the dynamically loaded Vulkan library.

The exact ordering of independent instance children may be adjusted to obey
the specification, but all must be gone before the instance. The same
`VkAllocationCallbacks` pointer used for an object's creation must be used for
its destruction.

`deinit` must not silently call `vkDeviceWaitIdle`. Waiting can block forever,
conceal application synchronization errors, and is observable policy. The
caller must explicitly finish or wait for submitted work before destroying the
context. A debug contract may diagnose known live library-owned work, but it
cannot prove that arbitrary user submissions are complete.

Context creation is transactional. Output pointers are required non-null, and
an output owner must be empty on entry. Expected setup failures are returned.
Every failure path destroys partially created objects and leaves the output in
its empty state.

## Options are values, not a stateful builder

Bootstrap options follow the process-library convention: copyable policy
values with a useful `.init`, named factories, public fields where practical,
and allocation-free UFCS transformations that return a modified copy.

```d
VulkanOptions options = VulkanOptions.graphics()
    .withApplication("my_game", VulkanVersion(1, 0, 0))
    .withPreferredApiVersion(VulkanVersion(1, 3, 0))
    .withMinimumApiVersion(VulkanVersion(1, 2, 0))
    .withValidation(ValidationMode.ifAvailable)
    .requireDeviceExtension("VK_EXT_memory_budget");
```

Do not introduce a separately allocated builder, sticky hidden error, or
mandatory `finish` call. Borrowed slices in an options value must remain alive
until `createVulkan` returns. The context copies only state that must survive
setup.

Core policy enums should distinguish intent instead of using positional bools:

```d
enum Requirement : ubyte
{
    disabled,
    preferred,
    required,
}

enum ValidationMode : ubyte
{
    disabled,
    ifAvailable,
    required,
}

enum DevicePreference : ubyte
{
    automatic,
    discrete,
    integrated,
    lowPower,
    exact,
}
```

Required capabilities filter candidates and cause a descriptive failure when
none qualify. Preferred capabilities influence scoring but never prevent
startup. Disabled capabilities must not be enabled implicitly.

## Named setup profiles

Avoid one opaque preset that silently assumes every application is a game with
a window. Provide named starting profiles:

- `VulkanOptions.minimal()` creates an instance and logical device without
  requiring graphics, presentation, or validation.
- `VulkanOptions.graphics()` requires a graphics-capable queue, applies the
  documented general-purpose device score, and requests useful diagnostics
  according to its validation policy.
- `VulkanOptions.compute()` requires compute but not graphics or presentation
  and does not penalize compute-only devices.
- A surface provider added with `withSurface` extends a graphics setup with
  presentation and swapchain requirements.

`VulkanOptions.init` must have one documented meaning and should be equivalent
to the least surprising `minimal()` profile. Applications should normally use
a named profile so intent is visible.

A profile defines requirements and preferences, not a frozen hardware recipe.
In particular, it must not enable a feature merely because some development
machine supports it. The selected API version, features, extensions, queues,
validation state, and portability state remain queryable from the resulting
context.

Validation defaults must not depend on mutable process state. Named options
may deliberately choose `ifAvailable`, while release-oriented callers can
select `disabled`. If a future build-mode convenience changes a default, the
profile name and documentation must make that policy visible; there must still
be a direct runtime override.

## API-version negotiation

Version policy contains a minimum and a preferred version:

- If `vkEnumerateInstanceVersion` is unavailable, the loader version is Vulkan
  1.0.
- The requested instance version is the highest version no newer than the
  preferred version and supported by both the loader and generated bindings.
- Setup fails if that result is older than the minimum.
- Physical devices older than the required minimum are rejected.
- The context records the requested instance version, selected device version,
  and effective version usable with that device.

Code must still query individual capabilities. A sufficiently new version is
not a substitute for querying optional features, properties, formats, or
limits. Conversely, promoted extension functionality may be usable through an
explicitly enabled extension fallback on an older core version.

The default preferred version should advance deliberately with the pinned
bindings and test matrix. Do not silently equate "newest declaration generated"
with "minimum device required." A profile's minimum version is compatibility
policy and must be reviewed separately.

## Layers, extensions, features, and `pNext`

Options contain distinct required and preferred lists for instance extensions,
device extensions, and layers. `String` values are ergonomic borrowed names;
bootstrap validates them, rejects embedded NUL, and builds temporary C-string
arrays in its scratch scope. No scratch-backed name may escape setup.

The bootstrap must enumerate support before creation and report the exact
missing required name. Duplicate input names should be coalesced without
changing required-over-preferred precedence. Extension dependencies must be
satisfied rather than relying on a later opaque `vkCreateInstance` or
`vkCreateDevice` error.

Validation uses `VK_LAYER_KHRONOS_validation` and `VK_EXT_debug_utils` when the
selected policy and runtime support permit it. `ifAvailable` records that
validation was unavailable and continues; `required` fails. The debug messenger
callback and severity/type masks are configurable. The callback must not
allocate, throw, or call unsafe high-level logging paths from an unknown driver
thread. A caller-supplied function-pointer/context pair may receive structured
message data synchronously under an explicitly documented lifetime.

Features are queried before device creation, normally through
`VkPhysicalDeviceFeatures2` and the appropriate `pNext` chain. Every feature
placed in the enable chain must have been requested and observed as supported.
Do not pass user-owned query structures directly into the enable chain or
retain caller pointers after setup.

The initial implementation should support core version feature structures and
the common features required by its profiles. Extensibility for uncommon
feature structures must use an explicit advanced provider contract with
separate query and enable storage/lifetimes. It must not accept an arbitrary
opaque `pNext` chain that the bootstrap cannot validate, clone, or keep alive.

## Portability

When `VK_KHR_portability_enumeration` is available, a general-purpose profile
should enable the extension and set
`VK_INSTANCE_CREATE_ENUMERATE_PORTABILITY_BIT_KHR` so portability devices can
be enumerated. The context records whether this happened.

If a selected physical device reports `VK_KHR_portability_subset`, device
creation must enable it as required by the Vulkan specification. Portability
support is ordinary capability negotiation, not a platform-name special case.

## Physical-device selection

Do not select the first enumerated device. Selection has two phases:

1. Reject devices that fail hard requirements.
2. Score the remaining devices using documented preferences.

Hard requirements may include:

- minimum effective API version;
- required device extensions and features;
- required queue capabilities and counts;
- presentation support for the supplied surface;
- required limits; and
- an exact device identity selected by the caller.

The default graphics score may prefer, in order of influence:

- devices satisfying preferred extensions and features;
- the caller's requested device class;
- discrete GPUs over integrated GPUs for the automatic performance profile;
- integrated or otherwise low-power devices for a low-power profile;
- larger relevant limits and memory capacity only where the comparison is
  meaningful; and
- queue topologies requiring less cross-family ownership transfer.

A compute profile must not demote a capable compute-only device merely because
it lacks graphics or presentation.

Scoring must use checked arithmetic and deterministic tie-breaking. The chosen
candidate and the reasons candidates were rejected should be observable through
structured selection information or caller diagnostics. Setup errors should at
least identify the strongest unsatisfied requirement rather than returning only
`VK_ERROR_INITIALIZATION_FAILED`.

Advanced callers may provide filter and scoring callbacks as explicit function
pointer/context pairs. A callback receives a borrowed `DeviceCandidate` that is
valid only for the call. It must not retain scratch-backed extension, feature,
property, or queue-family slices.

## Queue selection

Queue requirements are expressed by role rather than hardcoded family indexes:

- graphics;
- compute;
- transfer; and
- presentation for a particular surface.

The selector first satisfies required roles and counts. It should prefer a
dedicated compute family and a dedicated transfer family when available, but
must share a capable family when dedicated queues are absent unless the caller
made separation required. Graphics and presentation may share a family or use
different families; the chosen topology is recorded explicitly.

Device creation coalesces requests for the same family and never asks a family
for more queues than it advertises. Queue priorities come from caller policy or
documented defaults and remain alive through `vkCreateDevice`.

The context stores only the selected queue handles and family/index metadata
needed after setup. Temporary enumeration arrays come from scratch and do not
force a persistent general-purpose allocator into `VulkanContext`.

## Surface and window integration

Vulkan bootstrap cannot infer a native window system. Instance WSI extensions
must be known before instance creation, while the surface itself is created
after an instance exists. A window library or application therefore supplies a
borrowed `SurfaceProvider` containing:

- required instance extension names;
- a context pointer;
- a function that creates `VkSurfaceKHR` from the new instance; and
- explicit ownership behavior.

The callback is an internal D function-pointer/context pair unless a foreign
adapter specifically requires `extern(C)`. It is not a D delegate and does not
cross the Vulkan C ABI.

Conceptually:

```d
alias CreateSurface = VkResult function(
    void* context,
    VkInstance instance,
    scope const(InstanceCommands)* commands,
    scope const(VkAllocationCallbacks)* callbacks,
    scope VkSurfaceKHR* output,
);

struct SurfaceProvider
{
    const(String)[] requiredInstanceExtensions;
    void* context;
    CreateSurface create;
}
```

The final declaration must apply truthful DIP1000 attributes and document
thread affinity imposed by the window backend. The provider and borrowed names
must remain alive only until setup returns. If bootstrap owns the created
surface, it destroys it before the instance. A separately supplied borrowed
surface requires a lower-level instance/device path because a surface cannot
normally predate the instance that owns it.

Providing a surface adds presentation support and `VK_KHR_swapchain` to the
device requirements. It does not create the swapchain.

## Allocation and scratch space

Enumeration and temporary C-string conversion use `ScratchScope` from the
explicitly installed thread context. Every allocator that may back live input
or output is included in the conflict set. Scratch acquisition failure remains
a panic under the core scratch contract, and scratch storage never appears as
a fallible public buffer parameter.

Bootstrap should keep its persistent owner fixed-size where practical. Device
candidates, extension lists, feature-query structures, queue-family lists, and
creation arrays are setup temporaries. Selected handles, versions, capabilities,
and queue metadata fit directly in `VulkanContext`.

The existing `xtb.memory.Allocator` cannot be mechanically forwarded as
`VkAllocationCallbacks`. Vulkan's free and reallocation callbacks do not supply
the old allocation size, while the xtb allocator procedure requires old size
for deallocation and reallocation. Vulkan may also invoke allocation callbacks
from threads controlled by the loader or driver.

The initial bootstrap therefore passes null `VkAllocationCallbacks`. A future
adapter must:

- store original size and alignment in metadata associated with every returned
  allocation;
- recover that metadata safely for reallocation and free;
- satisfy arbitrary Vulkan-requested alignments without losing its header;
- detect overflow while reserving metadata and alignment padding;
- preserve the allocation when a reallocation fails as Vulkan requires;
- use an allocator that is safe for every possible callback thread;
- implement the internal-allocation notification callbacks if exposed; and
- store one stable `VkAllocationCallbacks` value for the entire lifetime of
  every object created with it.

This adapter is an advanced opt-in facility. It must not be hidden inside
ordinary bootstrap defaults.

## Error model

Vulkan availability and setup failures are expected runtime states. Do not
panic because the loader, a validation layer, a required extension, a suitable
device, or a queue family is absent.

Use a concrete error with operation context rather than introducing a generic
exception or an unrelated universal `Result`:

```d
enum VulkanOperation : ubyte
{
    none,
    loadLibrary,
    loadGlobalCommands,
    enumerateInstanceSupport,
    createInstance,
    loadInstanceCommands,
    createDebugMessenger,
    createSurface,
    enumerateDevices,
    selectDevice,
    createDevice,
    loadDeviceCommands,
}

enum VulkanErrorKind : ubyte
{
    none,
    unsupported,
    loaderNotFound,
    missingCommand,
    invalidOptions,
    missingLayer,
    missingExtension,
    missingFeature,
    noSuitableDevice,
    noSuitableQueue,
    outOfMemory,
    vulkan,
}

struct VulkanError
{
    VulkanErrorKind kind;
    VulkanOperation operation;
    VkResult vkResult;
    // Owned fixed-capacity detail for a command/capability name when relevant.

    bool failed() const pure @safe;
    bool succeeded() const pure @safe;
    String detail() const return scope @safe;
}
```

The exact categories may be refined during implementation, but the error must
retain the original `VkResult` when a Vulkan command produced it. A missing
command, layer, extension, or feature name must not borrow scratch memory. Use
fixed-capacity owned error storage sized for Vulkan names and reject impossible
overflow rather than returning a dangling view.

The convenience entry point follows existing explicit-output conventions:

```d
VulkanError createVulkan(
    scope const(VulkanOptions) options,
    scope VulkanContext* output,
);
```

The options value is shallow and borrowed. It is passed by value rather than a
required pointer because nullability has no meaning and the native ABI may
still lower the aggregate indirectly. The mutable owner output remains an
explicit pointer.

## Threading and external synchronization

Dispatch tables become immutable after construction and may be borrowed by
threads as long as their owning context remains alive. The Vulkan package does
not impose a global lock around commands and does not pretend to satisfy
Vulkan's externally synchronized object rules for the application.

Options, surface callbacks, debug callbacks, selection callbacks, and custom
allocation callbacks document whether the Vulkan implementation may call them
from foreign threads. No callback may rely on the scratch context of the setup
thread unless it is invoked synchronously during that setup call and the API
contract says so.

Destroying a context while another thread uses one of its handles or dispatch
pointers is a caller error. Borrowed table views must not outlive the context.

## Platform behavior and build organization

Raw generated bindings should compile on every supported D target even when no
Vulkan runtime exists. Native dynamic-loader support is selected through
versioned backend modules. An unimplemented backend returns
`VulkanErrorKind.unsupported`; it must not use a compile-time error that prevents
the rest of xtb from building.

The initial implementation may target one platform, but its public design must
not expose that platform's library handle or WSI types in common bootstrap
policy. Each additional backend requires native lifetime and integration tests
before it is advertised.

The flake should provide the generator's pinned registry inputs and an optional
Vulkan development/test environment. Ordinary library consumers should not
inherit validation layers, a software driver, or SDK tools as runtime
dependencies merely because the Vulkan package exists.

## Testing strategy

Most behavior must be testable without a GPU. Every loader and bootstrap stage
therefore depends on an injected command resolver/API table rather than direct
unmockable global calls.

Unit and simulated integration tests must cover:

- dynamic-library absence and malformed resolver injection;
- global, instance, and device command loading;
- command lookup names and correct resolver scope;
- required-command failure versus optional null commands;
- multiple contexts with distinct instance/device function pointers;
- API-version negotiation including the Vulkan 1.0 fallback when
  `vkEnumerateInstanceVersion` is absent;
- required, preferred, disabled, duplicate, and dependency-related layers and
  extensions;
- validation disabled, available, unavailable-optional, and unavailable-required
  behavior;
- portability enumeration and portability-subset enablement;
- feature query and enable chains;
- device rejection, scoring, deterministic tie-breaking, and exact selection;
- graphics, compute-only, shared, dedicated, and split-present queue layouts;
- surface-provider success, failure, and ownership cleanup;
- allocation failure in every temporary setup stage;
- cleanup after failure at every object-creation boundary;
- empty-output preservation and idempotent `deinit`;
- unsupported-platform compilation and behavior; and
- ABI agreement with representative official C declarations.

The Nix integration environment should additionally provide the Khronos loader,
validation layer, and Mesa software Vulkan implementation where supported. A
headless integration test should create an instance and device, load command
tables, submit a minimal queue operation where practical, wait explicitly, and
destroy everything without validation errors. Hardware GPU availability must
not be required for `just check`.

Fuzz or property tests are appropriate for synthetic extension/feature lists,
duplicate resolution, queue-family selection, score overflow, and failure-path
cleanup. They are not a substitute for a real loader integration test.

## Representative usage

The ordinary convenience path remains explicit about errors and ownership:

```d
VulkanOptions options = VulkanOptions.graphics()
    .withApplication("example", VulkanVersion(1, 0, 0))
    .withValidation(ValidationMode.ifAvailable);

VulkanContext vk;
VulkanError error = createVulkan(options, &vk);
if (error.failed)
{
    // Format error.kind, error.operation, error.vkResult, and error.detail().
    return 1;
}
scope(exit) vk.deinit();

VkBuffer buffer;
VkResult result = vk.deviceCommands().vkCreateBuffer(
    vk.device(),
    &bufferInfo,
    null,
    &buffer,
);
```

A presenting application supplies its native integration rather than making
the Vulkan package depend on a particular window library:

```d
VulkanOptions options = VulkanOptions.graphics()
    .withSurface(window.vulkanSurfaceProvider())
    .withValidation(ValidationMode.ifAvailable);
```

Advanced code may stop after any lower-level stage:

```d
VulkanLibrary library;
VulkanError error = loadVulkanLibrary(&library);
if (error.failed)
    return 1;
scope(exit) library.deinit();

GlobalCommands global;
error = loadGlobalCommands(library.resolver(), &global);
if (error.failed)
    return 1;

// The caller may now create and configure VkInstance manually.
```

These layers share the same raw bindings, error conventions, resolver, and
dispatch representation. Convenience must not fork the package into a separate
incompatible Vulkan API.

## Authoritative references

Implementation and review should use the current pinned revisions of these
primary Khronos sources:

- [Vulkan specification](https://registry.khronos.org/vulkan/specs/latest/html/vkspec.html)
- [`vkGetInstanceProcAddr` reference](https://docs.vulkan.org/refpages/latest/refpages/source/vkGetInstanceProcAddr.html)
- [`vkGetDeviceProcAddr` reference](https://docs.vulkan.org/refpages/latest/refpages/source/vkGetDeviceProcAddr.html)
- [Vulkan loader interface architecture](https://github.com/KhronosGroup/Vulkan-Loader/blob/main/docs/LoaderInterfaceArchitecture.md)
- [Querying extensions, features, and properties](https://docs.vulkan.org/guide/latest/querying_extensions_features.html)
- [Vulkan versions and feature detection](https://docs.vulkan.org/guide/latest/versions.html)
- [Vulkan layers](https://docs.vulkan.org/guide/latest/layers.html)

The moving `latest` links are discovery aids. The generated binding and test
environment must pin an exact registry revision so a future specification
change cannot silently alter the ABI contract.
