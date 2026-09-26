#!/usr/bin/env bash
set -euo pipefail

if (( $# != 1 )); then
    echo "usage: $0 <vector-indexing-executable>" >&2
    exit 2
fi

vector_probe="$1"
if [[ ! -x "$vector_probe" ]]; then
    echo "vector indexing executable not found: $vector_probe" >&2
    exit 2
fi

if ! command -v objdump >/dev/null 2>&1; then
    echo "objdump is required to inspect vector indexing" >&2
    exit 2
fi

"$vector_probe"

if ! objdump -f "$vector_probe" | grep -q 'architecture: i386:x86-64'; then
    echo "vector indexing instruction comparison requires x86-64" >&2
    exit 2
fi

instructions() {
    objdump -d --no-show-raw-insn --disassemble="$1" "$vector_probe" |
        awk '
            /^[[:space:]]*[[:xdigit:]]+:/ {
                sub(/^[[:space:]]*[[:xdigit:]]+:[[:space:]]*/, "")
                sub(/[[:space:]]+#.*/, "")
                if ($0 !~ /^(nop|data16|cs nop|xchg[[:space:]].*%ax)/)
                    print
            }
        '
}

# Compare actual instructions, not timing. Different addresses and alignment
# padding are immaterial; calls, dispatch, and extra loads/stores are not.
for vector in Vector2 Vector3 Vector4; do
    for operation in indexed_read constant_read indexed_write constant_write; do
        case "$operation" in
            indexed_read) baseline=array_read ;;
            indexed_write) baseline=array_write ;;
            constant_read) baseline=array_constant_read ;;
            constant_write) baseline=array_constant_write ;;
        esac

        actual="$(instructions "${vector}_${operation}")"
        expected="$(instructions "${vector}_${baseline}")"
        if [[ -z "$actual" || -z "$expected" || "$actual" != "$expected" ]]; then
            echo "${vector}_${operation} does not match its raw-array baseline" >&2
            echo "vector instructions: $actual" >&2
            echo "array instructions: $expected" >&2
            exit 1
        fi
    done
done

echo "Vector indexing matches raw-array loads and stores"
