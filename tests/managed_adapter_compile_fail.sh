#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
compiler=${DC:-ldc2}
temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT HUP INT TERM

for source in "$repo_root"/tests/compile_fail/managed_adapter/*.d; do
    name=$(basename "$source" .d)
    expected=$(sed -n 's#^// expected: ##p' "$source")
    log="$temporary/$name.log"
    object="$temporary/$name.o"

    if "$compiler" -betterC -preview=dip1000 -boundscheck=on \
            -I"$repo_root/source" -i -c "$source" -of="$object" \
            >"$log" 2>&1; then
        echo "expected compilation failure: $name" >&2
        exit 1
    fi

    if ! grep -F "$expected" "$log" >/dev/null; then
        echo "unexpected diagnostic for $name" >&2
        cat "$log" >&2
        exit 1
    fi

done
