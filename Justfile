root-dir := justfile_directory()
build-dir := root-dir + "/build"

# Build system gen
gen-build-system mode="Debug":
    cmake -S {{root-dir}} -B {{build-dir}} -DCMAKE_BUILD_TYPE={{mode}}

# Build
build-all mode="Debug": (gen-build-system mode)
    make -C {{build-dir}}

build target mode="Debug": (gen-build-system mode)
    make -C {{build-dir}} {{target}}

# Run actions
run-mode mode target *args: (build target mode)
    {{build-dir}}/apps/{{target}}/{{target}} {{args}}

run-debug target *args:
    just run-mode "Debug" {{target}} {{args}}

run-release-debug target *args:
    just run-mode "RelWithDebInfo" {{target}} {{args}}

run-release-min-size target *args:
    just run-mode "MinSizeRel" {{target}} {{args}}

run-release target *args:
    just run-mode "Release" {{target}} {{args}}

# Clean
clean:
    rm -rf {{build-dir}}

# Generate compile_commands.json
generate-compilation-db: (clean)
    bear -- just build-all

