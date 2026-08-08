set shell := ["bash", "-eu", "-o", "pipefail", "-c"]
set script-interpreter := ["bash", "-eu", "-o", "pipefail"]

d_files := `find source tests examples -type f -name '*.d' -print | sort | tr '\n' ' '`
library_subpackages := `for recipe in source/xtb/*/dub.sdl; do basename "$(dirname "$recipe")"; done | sort | tr '\n' ' '`
example_configurations := `sed -n 's/^configuration "\([^"]*\)".*/\1/p' examples/dub.sdl | tr '\n' ' '`
test_configurations := `sed -n 's/^configuration "\([^"]*\)".*/\1/p' tests/dub.sdl | tr '\n' ' '`
library_output_dir := env_var_or_default("XTB_LIBRARY_OUTPUT_DIR", "build")
consumer_project_dir := invocation_directory()
d_compiler := env_var_or_default("DC", "ldc2")
dub_options := "--quiet --skip-registry=all --compiler=" + d_compiler

# `just` and `just build` both build the monolithic checked-debug library.
default: build

# Build a static library or example.
#
# Examples:
#   just build
#   just build static core release-safe
#   just build static xtb release-fast
#   just build static all debug
#   just build example serde release-safe
#   just build example all debug
build kind="static" name="xtb" mode="debug": (_dispatch "build" kind name mode)

# Run a named example, optionally selecting the build mode.
#
# Examples:
#   just run example core
#   just run example serde release-safe
#   just run example all debug
run kind name mode="debug": (_dispatch "run" kind name mode)

# Run or compile the complete test suite in one supported mode.
# Release-fast compiles the test runners but does not execute stripped tests.
test mode="debug": (_test mode)

# Print supported modes and target names.
[script]
targets:
    cat <<'EOF'
    Build modes:
      debug
      release-safe
      release-fast

    Static libraries:
      xtb          monolithic library containing every module
      core
      diagnostics
      math
      os
      parser
      serde
      threading
      all          xtb plus every component library

    Examples:
    EOF
    for config in {{ example_configurations }}; do
        printf '  %s\n' "${config%-demo}"
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
    dscanner_files=()
    for file in {{ d_files }}; do
        if ! grep -Fxq "; ignore=$file" dscanner.ini; then
            dscanner_files+=("$file")
        fi
    done
    dscanner lint --config dscanner.ini --styleCheck "${dscanner_files[@]}"

# Backward-compatible all-library mode aliases.
debug: (_dispatch "build" "static" "all" "debug")
release-safe: (_dispatch "build" "static" "all" "release-safe")
release-fast: (_dispatch "build" "static" "all" "release-fast")

# Convenience example aliases.
build-example name mode="debug": (_dispatch "build" "example" name mode)
run-example name mode="debug": (_dispatch "run" "example" name mode)
build-examples mode="debug": (_dispatch "build" "example" "all" mode)
run-examples mode="debug": (_dispatch "run" "example" "all" mode)

# Additional test modes retained for profiling and sanitizers.
test-optimized: (_test "optimized")
test-release-safe: (_test "release-safe")
test-release-fast: (_test "release-fast")
test-release: test-release-safe
test-sanitize: (_test "asan")

# Run the complete local verification matrix.
check: format-check lint _check-build-debug _check-build-release-safe _check-build-release-fast test test-optimized test-release-safe test-release-fast test-sanitize run-examples

_check-build-debug: (_dispatch "build" "static" "all" "debug")
_check-build-release-safe: (_dispatch "build" "static" "all" "release-safe")
_check-build-release-fast: (_dispatch "build" "static" "all" "release-fast")

# Shared build/run dispatcher.
[script]
_dispatch action kind name mode:
    action="{{ action }}"
    kind="{{ kind }}"
    name="{{ name }}"
    mode="{{ mode }}"

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
        if [[ "$target" == xtb ]]; then
            echo "Building static xtb ($mode)"
            dub build "${dub_args[@]}"
            return
        fi

        local libraries=({{ library_subpackages }})
        if ! contains "$target" "${libraries[@]}"; then
            echo "unknown static library: $target" >&2
            echo "expected xtb, all, or one of: ${libraries[*]}" >&2
            exit 2
        fi

        echo "Building static $target ($mode)"
        dub build ":$target" "${dub_args[@]}"
    }

    normalize_example() {
        local value="$1"
        value="${value%.d}"
        value="${value%_demo}"
        value="${value%-demo}"
        value="${value//-/_}"
        printf '%s-demo\n' "$value"
    }

    build_or_run_example() {
        local operation="$1"
        local requested="$2"
        local config
        config="$(normalize_example "$requested")"
        local configurations=({{ example_configurations }})
        if ! contains "$config" "${configurations[@]}"; then
            echo "unknown example: $requested" >&2
            echo "run 'just targets' to list examples" >&2
            exit 2
        fi

        echo "${operation^} example ${config%-demo} ($mode)"
        if [[ "$operation" == build ]]; then
            dub build :examples "${dub_args[@]}" --config="$config"
        else
            dub run :examples "${dub_args[@]}" --config="$config"
        fi
    }

    case "$kind" in
        static)
            if [[ "$action" != build ]]; then
                echo "static libraries can be built but not run" >&2
                exit 2
            fi
            export XTB_LIBRARY_OUTPUT_DIR="$(absolute_output_dir "{{ library_output_dir }}/$mode")"
            if [[ "$name" == all ]]; then
                build_static xtb
                for library in {{ library_subpackages }}; do
                    build_static "$library"
                done
            else
                build_static "$name"
            fi
            ;;
        example)
            if [[ "$name" == all ]]; then
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
            ;;
        optimized)
            build_type=test-optimized
            ;;
        release-safe)
            build_type=test-release-safe
            ;;
        release-fast)
            build_type=test-release-fast
            execute=false
            checked=false
            bounds=off
            ;;
        asan)
            build_type=test-asan
            ;;
        *)
            echo "unknown test mode: $mode" >&2
            echo "expected debug, optimized, release-safe, release-fast, or asan" >&2
            exit 2
            ;;
    esac

    echo "Testing $mode"
    export XTB_TEST_MODE="$mode"
    export DFLAGS="${DFLAGS:+$DFLAGS }-boundscheck=$bounds"
    dub_args=({{ dub_options }} --parallel --build="$build_type")
    if [[ "$checked" == true ]]; then
        dub_args+=(--d-version=XTB_Checked)
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
