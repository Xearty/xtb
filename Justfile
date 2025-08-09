root-dir := justfile_directory()
build-dir := root-dir + "/build"

gen-build-system:
    cmake -B {{build-dir}}

build-all: (gen-build-system)
    make -C {{build-dir}}

build target: (gen-build-system)
    make -C {{build-dir}} {{target}}

run target *args: (build target)
    {{build-dir}}/apps/{{target}}/{{target}} {{args}}

clean:
    rm -rf {{build-dir}}

generate-compilation-db: (clean)
    bear -- just build-all

