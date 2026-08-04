set shell := ["bash", "-eu", "-o", "pipefail", "-c"]
set script-interpreter := ["bash", "-eu", "-o", "pipefail"]

d_files := `find source tests examples -type f -name '*.d' -print | sort | tr '\n' ' '`
library_subpackages := `for recipe in source/xtb/*/dub.sdl; do basename "$(dirname "$recipe")"; done | sort | tr '\n' ' '`
example_configurations := `sed -n 's/^configuration "\([^"]*\)".*/\1/p' examples/dub.sdl | tr '\n' ' '`
test_configurations := `sed -n 's/^configuration "\([^"]*\)".*/\1/p' tests/dub.sdl | tr '\n' ' '`
library_output_dir := env_var_or_default("XTB_LIBRARY_OUTPUT_DIR", "build")
export XTB_LIBRARY_OUTPUT_DIR := library_output_dir
# Relative library paths belong to the project that invoked this Justfile.
consumer_project_dir := invocation_directory()
d_compiler := env_var_or_default("DC", "ldc2")
dub_options := "--quiet --skip-registry=all --compiler=" + d_compiler

default: check

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

# Build every component, or only the named components when arguments are given.
[script]
build *libraries:
    output_dir="{{ library_output_dir }}"
    if [[ "$output_dir" != /* ]]; then
        output_dir="{{ consumer_project_dir }}/$output_dir"
    fi
    mkdir -p "$output_dir"
    export XTB_LIBRARY_OUTPUT_DIR="$(cd "$output_dir" && pwd -P)"
    libraries=({{ libraries }})
    if (( ${#libraries[@]} == 0 )); then
        for library in {{ library_subpackages }}; do
            dub build ":$library" {{ dub_options }} --parallel --build=plain
        done
    else
        for library in "${libraries[@]}"; do
            dub build ":$library" {{ dub_options }} --parallel --build=plain
        done
    fi

[script]
_test mode build_type:
    echo "Testing {{ mode }}"
    export XTB_TEST_MODE={{ mode }}
    for config in {{ test_configurations }}; do
        if [[ "$config" == test-helper-* ]]; then
            dub build :tests {{ dub_options }} --parallel --build={{ build_type }} --config="$config"
        fi
    done
    for config in {{ test_configurations }}; do
        if [[ "$config" == test-* && "$config" != test-helper-* ]]; then
            dub run :tests {{ dub_options }} --build={{ build_type }} --config="$config"
        fi
    done

# Run the BetterC unit and integration tests.
test: (_test "debug" "test-debug")

# Run the test suite with optimization enabled.
test-optimized: (_test "optimized" "test-optimized")

# Run the release-safe suite with bounds checks retained.
test-release: (_test "release" "test-release-safe")

# Run all native tests under AddressSanitizer.
test-sanitize: (_test "asan" "test-asan")

# Build and run one named example.
[script]
run-example example:
    config="{{ example }}"
    config="${config%-demo}-demo"
    dub run :examples {{ dub_options }} --build=debug --config="$config"

# Build and run every public example.
[script]
run-examples:
    for config in {{ example_configurations }}; do
        dub run :examples {{ dub_options }} --build=debug --config="$config"
    done

# Run compiler semantic checks and D-Scanner policy checks.
[script]
lint:
    dub build {{ dub_options }} --build=syntax --config=library
    for config in {{ example_configurations }}; do
        if [[ "$config" == *-demo ]]; then
            dub build :examples {{ dub_options }} --build=syntax --config="$config"
        fi
    done
    dscanner_files=()
    for file in {{ d_files }}; do
        if ! grep -Fxq "; ignore=$file" dscanner.ini; then
            dscanner_files+=("$file")
        fi
    done
    dscanner lint --config dscanner.ini --styleCheck "${dscanner_files[@]}"

# Run the complete local verification matrix.
check: format-check lint build test test-optimized test-release test-sanitize run-examples
