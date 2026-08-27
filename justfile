set shell := ["bash", "-eu", "-o", "pipefail", "-c"]
set script-interpreter := ["bash", "-eu", "-o", "pipefail"]

d_files := `find source tools tests examples benchmarks -type f -name '*.d' -print | sort | tr '\n' ' '`
subpackages := `for recipe in source/*/dub.sdl; do sed -n 's/^name "\([^"]*\)".*/\1/p' "$recipe" | head -n 1; done | sort | tr '\n' ' '`
example_configurations := `sed -n 's/^configuration "\([^"]*\)".*/\1/p' examples/dub.sdl | tr '\n' ' '`
benchmark_configurations := `sed -n 's/^configuration "\([^"]*\)".*/\1/p' benchmarks/dub.sdl | tr '\n' ' '`
test_configurations := `sed -n 's/^configuration "\([^"]*\)".*/\1/p' tests/dub.sdl | tr '\n' ' '`
library_output_dir := env_var_or_default("XTB_LIBRARY_OUTPUT_DIR", "build")
consumer_project_dir := invocation_directory()
d_compiler := env_var_or_default("DC", "ldc2")
dub_options := "--quiet --skip-registry=all --compiler=" + d_compiler

# `just` and `just build` both build the full checked-debug library.
default: build

# Build a static library or example.
#
# Examples:
#   just build
#   just build static xtb release-safe
#   just build static xtb release-fast
#   just build example serde release-safe
#   just build example all debug
build kind="static" name="xtb" mode="debug": (_dispatch "build" kind name mode)

# Compose a slim libxtb.a from selected subpackages. Core is always included and
# DUB resolves the complete transitive subpackage closure.
[script]
[positional-arguments]
compose *args:
    args=("$@")
    mode=debug
    subpackages=()
    for arg in "${args[@]}"; do
        case "$arg" in
            debug|release-safe|release-fast) mode="$arg" ;;
            *) subpackages+=("$arg") ;;
        esac
    done
    dub run :compose {{ dub_options }} --temp-build -- --mode="$mode" "${subpackages[@]}"

# Run a named example, optionally selecting the build mode and forwarding
# arguments after `--` to the executable.
#
# Examples:
#   just run example core
#   just run example serde release-safe
#   just run example cli -- --help
#   just run example cli release-safe -- build -r
[script]
[positional-arguments]
run kind name *tail:
    kind="$1"
    name="$2"
    shift 2

    mode=debug
    case "${1-}" in
        debug|release-safe|release-fast)
            mode="$1"
            shift
            ;;
    esac

    # Program arguments must be separated from the wrapper arguments
    # explicitly. This keeps build-mode names unambiguous when they are meant
    # to be passed to the executable.
    if (( $# != 0 )); then
        if [[ "$1" != -- ]]; then
            echo "example arguments must follow '--'" >&2
            echo "usage: just run example <name> [mode] -- <arguments...>" >&2
            exit 2
        fi
        shift
    fi

    just --justfile "{{ justfile() }}" --working-directory "{{ consumer_project_dir }}" \
        _dispatch run "$kind" "$name" "$mode" -- "$@"

# Run an opt-in release-fast microbenchmark. Benchmarks are deliberately not
# part of `check` or `run-examples`.
#
# Example:
#   just benchmark logging 500000
[script]
[positional-arguments]
benchmark name="logging" iterations="200000":
    name="$1"
    iterations="$2"
    case " {{ benchmark_configurations }} " in
        *" $name "*) ;;
        *)
            echo "unknown benchmark: $name" >&2
            exit 2
            ;;
    esac
    dub run :benchmarks {{ dub_options }} --build=release-nobounds --config="$name" -- "$iterations"

# Run or compile the complete test suite in one supported mode.
# Release-fast compiles the test runners but does not execute stripped tests.
test mode="debug": (_test mode)

# Verify that the published diagnostics composition is self-contained: its
# consumer links only libxtb.a and never names the private native dependency.
[script]
_check-compose-diagnostics:
    if [[ "$(uname -s)" != Linux ]]; then
        exit 0
    fi

    output_dir="$(mkdir -p build/check/compose-diagnostics && cd build/check/compose-diagnostics && pwd -P)"
    archive="$(dub run :compose {{ dub_options }} --temp-build -- \
        --mode=release-safe \
        diagnostics)"
    if [[ "$(basename "$(dirname "$archive")")" != core+diagnostics ]]; then
        echo "diagnostics composition has an unexpected subpackage closure: $archive" >&2
        exit 1
    fi

    archiver="${AR:-ar}"
    if ! "$archiver" t "$archive" | grep -q '^xtb_diagnostics_native_'; then
        echo "diagnostics composition does not contain its private native objects" >&2
        exit 1
    fi

    core_output_dir="$(mkdir -p build/check/compose-core && cd build/check/compose-core && pwd -P)"
    dub run :compose {{ dub_options }} --temp-build -- \
        --mode=release-safe \
        --output="$core_output_dir" \
        core >/dev/null
    if "$archiver" t "$core_output_dir/libxtb.a" | grep -q '^xtb_diagnostics_native_'; then
        echo "core composition unexpectedly contains diagnostics native objects" >&2
        exit 1
    fi

    "{{ d_compiler }}" \
        -betterC \
        -preview=dip1000 \
        -boundscheck=on \
        -Isource/core \
        -Isource/log \
        -Isource/os \
        -Isource/diagnostics \
        examples/stacktrace_demo.d \
        "$archive" \
        -of="$output_dir/diagnostics_archive_consumer"
    "$output_dir/diagnostics_archive_consumer" >/dev/null

# Compile every subpackage and its colocated unit tests using only the subpackage's
# declared dependency closure. The no-op main keeps this a compile-only gate;
# behavioral tests already run through the full development aggregate.
[script]
_check-subpackage-tests:
    base_dflags="${DFLAGS-}"
    selected_subpackages=({{ subpackages }})

    for mode in debug release-safe release-fast; do
        case "$mode" in
            debug)
                mode_flags="-d-debug -g -unittest -boundscheck=on"
                checked=true
                ;;
            release-safe)
                mode_flags="-O -enable-inlining -fno-delete-null-pointer-checks -unittest -boundscheck=on"
                checked=true
                ;;
            release-fast)
                mode_flags="-O -enable-inlining -release -unittest -boundscheck=off"
                checked=false
                ;;
        esac

        echo "Compiling isolated subpackages and unit tests ($mode)"
        for subpackage in "${selected_subpackages[@]}"; do
            test_args=(
                ":$subpackage"
                {{ dub_options }}
                --parallel
                --build=plain
                --main-file=tests/support/compile_unittests.d
                --temp-build
            )
            if [[ "$checked" == true ]]; then
                test_args+=(--d-version=XTB_Checked)
            fi
            DFLAGS="${base_dflags:+$base_dflags }$mode_flags" dub test "${test_args[@]}"
        done
    done

# Verify every subpackage boundary in the three public modes (slow and optional).
check-subpackages: _check-subpackage-tests

# Print supported modes and target names.
[script]
targets:
    cat <<'EOF'
    Build modes:
      debug
      release-safe
      release-fast

    Static library:
      xtb          full development library containing every subpackage

    Composable subpackages:
    EOF
    for subpackage in {{ subpackages }}; do
        printf '  %s\n' "$subpackage"
    done
    cat <<'EOF'

    Examples:
    EOF
    for config in {{ example_configurations }}; do
        printf '  %s\n' "${config%-demo}"
    done
    echo
    echo "Benchmarks:"
    for config in {{ benchmark_configurations }}; do
        printf '  %s\n' "$config"
    done

# Remove DUB state and generated build outputs.
clean:
    rm -rf .dub build

# Format every D source file in place.
format:
    @dfmt --config . --inplace {{ d_files }}

# Verify formatting without modifying the working tree.
[script]
format-check:
    status=0
    for file in {{ d_files }}; do
        if ! dfmt --config . "$file" | cmp -s "$file" -; then
            echo "not formatted: $file" >&2
            status=1
        fi
    done
    exit "$status"

# Run compiler semantic checks and D-Scanner policy checks.
[script]
lint:
    export DFLAGS="${DFLAGS:+$DFLAGS }-boundscheck=on"
    export XTB_LIBRARY_OUTPUT_DIR="$(mkdir -p build/lint && cd build/lint && pwd -P)"
    dub build {{ dub_options }} --build=syntax --d-version=XTB_Checked --config=library
    for config in {{ example_configurations }}; do
        dub build :examples {{ dub_options }} --build=syntax --d-version=XTB_Checked --config="$config"
    done
    for config in {{ benchmark_configurations }}; do
        dub build :benchmarks {{ dub_options }} --build=syntax --d-version=XTB_Checked --config="$config"
    done
    dscanner_files=()
    for file in {{ d_files }}; do
        if ! grep -Fxq "; ignore=$file" dscanner.ini; then
            dscanner_files+=("$file")
        fi
    done
    dscanner lint --config dscanner.ini --styleCheck "${dscanner_files[@]}"

# Backward-compatible all-library mode aliases.
debug: (_dispatch "build" "static" "xtb" "debug")
release-safe: (_dispatch "build" "static" "xtb" "release-safe")
release-fast: (_dispatch "build" "static" "xtb" "release-fast")

# Convenience example aliases.
build-example name mode="debug": (_dispatch "build" "example" name mode)

# `mode` is recognized as the first argument when it is one of the supported
# build modes. Executable arguments must follow an explicit `--` separator.
#
# Examples:
#   just run-example cli -- --help
#   just run-example cli release-safe -- build -r
[script]
[positional-arguments]
run-example name *tail:
    name="$1"
    shift

    mode=debug
    case "${1-}" in
        debug|release-safe|release-fast)
            mode="$1"
            shift
            ;;
    esac

    # Program arguments must be separated from the wrapper arguments
    # explicitly. A deliberate second `--` remains an executable argument.
    if (( $# != 0 )); then
        if [[ "$1" != -- ]]; then
            echo "example arguments must follow '--'" >&2
            echo "usage: just run-example <name> [mode] -- <arguments...>" >&2
            exit 2
        fi
        shift
    fi

    just --justfile "{{ justfile() }}" --working-directory "{{ consumer_project_dir }}" \
        _dispatch run example "$name" "$mode" -- "$@"

build-examples mode="debug": (_dispatch "build" "example" "all" mode)
run-examples mode="debug": (_dispatch "run" "example" "all" mode)

# Additional test modes retained for profiling and sanitizers.
test-optimized: (_test "optimized")
test-release-safe: (_test "release-safe")
test-release-fast: (_test "release-fast")
test-release: test-release-safe
test-sanitize: (_test "asan")

# Run the routine local verification matrix.
check: format-check lint _check-build-debug _check-build-release-safe _check-build-release-fast _check-compose-diagnostics test test-optimized test-release-safe test-release-fast test-sanitize run-examples

# Run routine checks plus application-template validation before committing.
pre-commit: check check-template

check-template:
    nix flake check path:templates/app --override-input xtb path:.

_check-build-debug: (_dispatch "build" "static" "xtb" "debug")
_check-build-release-safe: (_dispatch "build" "static" "xtb" "release-safe")
_check-build-release-fast: (_dispatch "build" "static" "xtb" "release-fast")

# Shared build/run dispatcher.
[script]
[positional-arguments]
_dispatch action kind name mode *program_args:
    action="$1"
    kind="$2"
    name="$3"
    mode="$4"
    shift 4

    # The nested `just` call uses its own `--` boundary. With
    # `[positional-arguments]` that separator reaches this script, so consume
    # exactly one copy before forwarding the executable arguments to DUB.
    if [[ "${1-}" == -- ]]; then
        shift
    fi
    program_args=("$@")

    case "$mode" in
        debug)
            build_type=debug
            bounds=on
            checked=true
            ;;
        release-safe)
            build_type=release-safe
            bounds=on
            checked=true
            ;;
        release-fast)
            build_type=release-nobounds
            bounds=off
            checked=false
            ;;
        *)
            echo "unknown build mode: $mode" >&2
            echo "expected debug, release-safe, or release-fast" >&2
            exit 2
            ;;
    esac

    export DFLAGS="${DFLAGS:+$DFLAGS }-boundscheck=$bounds"
    dub_args=({{ dub_options }} --parallel --build="$build_type")
    if [[ "$checked" == true ]]; then
        dub_args+=(--d-version=XTB_Checked)
    fi

    absolute_output_dir() {
        local path="$1"
        if [[ "$path" != /* ]]; then
            path="{{ consumer_project_dir }}/$path"
        fi
        mkdir -p "$path"
        (cd "$path" && pwd -P)
    }

    contains() {
        local wanted="$1"
        shift
        local candidate
        for candidate in "$@"; do
            if [[ "$candidate" == "$wanted" ]]; then
                return 0
            fi
        done
        return 1
    }

    build_static() {
        local target="$1"
        if [[ "$target" != xtb && "$target" != all ]]; then
            echo "unknown static library: $target" >&2
            echo "XTB development builds produce only libxtb.a; use 'just compose' for slim subpackage sets" >&2
            exit 2
        fi

        echo "Building static xtb ($mode)"
        selected_subpackages=({{ subpackages }})
        dub run :compose {{ dub_options }} --temp-build -- \
            --mode="$mode" \
            --output="$XTB_LIBRARY_OUTPUT_DIR" \
            "${selected_subpackages[@]}"
    }

    resolve_example() {
        local requested="$1"
        local configurations=({{ example_configurations }})
        local value base candidate

        # Prefer exact configuration names first.
        if contains "$requested" "${configurations[@]}"; then
            printf '%s\n' "$requested"
            return 0
        fi

        value="${requested%.d}"
        if contains "$value" "${configurations[@]}"; then
            printf '%s\n' "$value"
            return 0
        fi

        base="${value%_demo}"
        base="${base%-demo}"

        # The public target name is exactly the configuration name without its
        # `-demo` suffix. Try that spelling before compatibility normalizations.
        candidate="$base-demo"
        if contains "$candidate" "${configurations[@]}"; then
            printf '%s\n' "$candidate"
            return 0
        fi

        candidate="${base//-/_}-demo"
        if contains "$candidate" "${configurations[@]}"; then
            printf '%s\n' "$candidate"
            return 0
        fi

        candidate="${base//_/-}-demo"
        if contains "$candidate" "${configurations[@]}"; then
            printf '%s\n' "$candidate"
            return 0
        fi

        return 1
    }

    build_or_run_example() {
        local operation="$1"
        local requested="$2"
        local config
        if ! config="$(resolve_example "$requested")"; then
            echo "unknown example: $requested" >&2
            echo "run 'just targets' to list examples" >&2
            exit 2
        fi

        echo "${operation^} example ${config%-demo} ($mode)"
        if [[ "$operation" == build ]]; then
            if (( ${#program_args[@]} != 0 )); then
                echo "example arguments are only valid when running an example" >&2
                exit 2
            fi
            dub build :examples "${dub_args[@]}" --config="$config"
        else
            dub run :examples "${dub_args[@]}" --config="$config" -- "${program_args[@]}"
        fi
    }

    case "$kind" in
        static)
            if [[ "$action" != build ]]; then
                echo "static libraries can be built but not run" >&2
                exit 2
            fi
            export XTB_LIBRARY_OUTPUT_DIR="$(absolute_output_dir "{{ library_output_dir }}/$mode")"
            build_static "$name"
            ;;
        example)
            export XTB_LIBRARY_OUTPUT_DIR="$(absolute_output_dir "{{ library_output_dir }}/$mode")"
            if [[ "$name" == all ]]; then
                if (( ${#program_args[@]} != 0 )); then
                    echo "cannot pass program arguments when running all examples" >&2
                    exit 2
                fi
                for config in {{ example_configurations }}; do
                    build_or_run_example "$action" "${config%-demo}"
                done
            else
                build_or_run_example "$action" "$name"
            fi
            ;;
        *)
            echo "unknown target kind: $kind" >&2
            echo "expected static or example" >&2
            exit 2
            ;;
    esac

# Shared test dispatcher.
[script]
_test mode:
    mode="{{ mode }}"
    execute=true
    checked=true
    bounds=on

    case "$mode" in
        debug)
            build_type=test-debug
            unit_build_type=unit-debug
            ;;
        optimized)
            build_type=test-optimized
            unit_build_type=unit-optimized
            ;;
        release-safe)
            build_type=test-release-safe
            unit_build_type=unit-release-safe
            ;;
        release-fast)
            build_type=test-release-fast
            unit_build_type=unit-release-fast
            execute=false
            checked=false
            bounds=off
            ;;
        asan)
            build_type=test-asan
            unit_build_type=unit-asan
            ;;
        *)
            echo "unknown test mode: $mode" >&2
            echo "expected debug, optimized, release-safe, release-fast, or asan" >&2
            exit 2
            ;;
    esac

    echo "Testing $mode"
    export XTB_TEST_MODE="$mode"
    export XTB_LIBRARY_OUTPUT_DIR="$(mkdir -p "build/test/$mode/libraries" && cd "build/test/$mode/libraries" && pwd -P)"
    export DFLAGS="${DFLAGS:+$DFLAGS }-boundscheck=$bounds"
    dub_args=({{ dub_options }} --parallel --build="$build_type")
    if [[ "$checked" == true ]]; then
        dub_args+=(--d-version=XTB_Checked)
    fi

    unit_args=({{ dub_options }} --parallel --build="$unit_build_type")
    if [[ "$mode" == debug ]]; then
        dub test :compose {{ dub_options }} --temp-build
    fi
    if [[ "$checked" == true ]]; then
        unit_args+=(--d-version=XTB_Checked)
        dub test "${unit_args[@]}"
    else
        # releaseMode removes unittest runners; compiling the full aggregate
        # still verifies every subpackage in the release-fast configuration.
        dub build {{ dub_options }} --parallel --build=release-nobounds
    fi

    for config in {{ test_configurations }}; do
        if [[ "$config" == test-helper-* ]]; then
            dub build :tests "${dub_args[@]}" --config="$config"
        fi
    done

    for config in {{ test_configurations }}; do
        if [[ "$config" != test-* || "$config" == test-helper-* ]]; then
            continue
        fi
        if [[ "$execute" == true ]]; then
            dub run :tests "${dub_args[@]}" --config="$config"
        else
            dub build :tests "${dub_args[@]}" --config="$config"
        fi
    done
