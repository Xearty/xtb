#!/usr/bin/env bash
set -euo pipefail

# This test inspects the final linked executable because the D probe can prove
# that lazy contract operands were not evaluated, but cannot prove that their
# diagnostic strings and checking functions were removed from the file.
# Together, these checks protect XTB's zero-cost release-fast contract promise.

if (( $# != 1 )); then
    echo "usage: $0 <contract-test-executable>" >&2
    exit 2
fi

contract_probe="$1"

if [[ ! -x "$contract_probe" ]]; then
    echo "contract test executable not found: $contract_probe" >&2
    exit 2
fi

if ! command -v nm >/dev/null 2>&1; then
    echo "nm is required to inspect release-fast contract symbols" >&2
    exit 2
fi

# The probe returns failure if either contract evaluates its condition or
# message in release-fast.
"$contract_probe"

# These unique strings occur only as contract messages in the D probe. Finding
# either one means release-fast retained user-facing diagnostic data.
for sentinel in \
    XTB_REQUIRE_RELEASE_FAST_SENTINEL_7A3F91D2 \
    XTB_ENSURE_RELEASE_FAST_SENTINEL_4C8E20B6
do
    if grep -aFq "$sentinel" "$contract_probe"; then
        echo "release-fast executable retains contract diagnostic text: $sentinel" >&2
        exit 1
    fi
done

# LDC encodes template names as __T<length><name> in D symbols. A remaining
# require or ensure instance means contract-checking code survived linking.
if nm "$contract_probe" | grep -Eq '__T(7require|6ensure)'; then
    echo "release-fast executable retains contract-checking code" >&2
    exit 1
fi
