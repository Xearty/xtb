module xtb.containers.internal.pool_storage;

nothrow @nogc:

import xtb.allocators.internal.virtual_memory : VirtualMemoryRegion,
    VirtualMemoryReservation;
import xtb.numeric : add_overflows;
import xtb.containers.virtual_array : try_align_address_up,
    try_virtual_array_region_geometry, VirtualArrayRegionGeometry;

/// Shared fixed-capacity three-region geometry for indexed Pool containers.
///
/// The regions are, in order: stable `T` values, caller-selected per-index
/// state, and a `uint` recycling stack. This module is package-private storage
/// machinery shared by `Pool!T` and `GenerationalPool!T`.
package(xtb.containers) struct IndexedPoolStorageLayout
{
    VirtualArrayRegionGeometry values;
    VirtualArrayRegionGeometry states;
    VirtualArrayRegionGeometry freeIndices;
    size_t valueCapacity;
    size_t stateCapacity;
    size_t reservationBytes;
}

package(xtb.containers) bool tryIndexedPoolStorageLayout(T, State)(
    uint capacity,
    size_t stateCapacity,
    size_t pageSize,
    scope IndexedPoolStorageLayout* output,
) pure @safe
{
    if (output is null || capacity == 0 || stateCapacity == 0 || pageSize == 0)
        return false;

    const capacityAsSize = cast(size_t) capacity;
    if (add_overflows(capacityAsSize, 1))
        return false;

    IndexedPoolStorageLayout result;
    result.valueCapacity = capacityAsSize + 1;
    result.stateCapacity = stateCapacity;
    if (!try_virtual_array_region_geometry!T(
            result.valueCapacity,
            pageSize,
            &result.values,
        ))
        return false;
    if (!try_virtual_array_region_geometry!State(
            stateCapacity,
            pageSize,
            &result.states,
        ))
        return false;
    if (!try_virtual_array_region_geometry!uint(
            capacityAsSize,
            pageSize,
            &result.freeIndices,
        ))
        return false;

    size_t total;
    if (!tryAddRegionBytes(total, result.values) ||
        !tryAddRegionBytes(total, result.states) ||
        !tryAddRegionBytes(total, result.freeIndices))
        return false;
    result.reservationBytes = total;
    *output = result;
    return true;
}

package(xtb.containers) bool tryIndexedPoolStorageRegions(
    ref VirtualMemoryReservation reservation,
    scope const IndexedPoolStorageLayout layout,
    scope VirtualMemoryRegion* values,
    scope VirtualMemoryRegion* states,
    scope VirtualMemoryRegion* freeIndices,
) @system
{
    if (values is null || states is null || freeIndices is null)
        return false;

    const reservationBase = cast(size_t) reservation.base;
    size_t cursor = reservationBase;

    void* valuesBase;
    if (!try_align_address_up(
            cast(void*) cursor,
            layout.values.base_alignment,
            &valuesBase,
        ))
        return false;
    const valuesAddress = cast(size_t) valuesBase;
    if (valuesAddress < reservationBase)
        return false;
    const valuesOffset = valuesAddress - reservationBase;
    if (!reservation.try_region(valuesOffset, layout.values.region_bytes, values))
        return false;
    if (add_overflows(valuesAddress, layout.values.region_bytes))
        return false;
    cursor = valuesAddress + layout.values.region_bytes;

    void* statesBase;
    if (!try_align_address_up(
            cast(void*) cursor,
            layout.states.base_alignment,
            &statesBase,
        ))
        return false;
    const statesAddress = cast(size_t) statesBase;
    if (statesAddress < reservationBase)
        return false;
    const statesOffset = statesAddress - reservationBase;
    if (!reservation.try_region(
            statesOffset,
            layout.states.region_bytes,
            states,
        ))
        return false;
    if (add_overflows(statesAddress, layout.states.region_bytes))
        return false;
    cursor = statesAddress + layout.states.region_bytes;

    void* freeBase;
    if (!try_align_address_up(
            cast(void*) cursor,
            layout.freeIndices.base_alignment,
            &freeBase,
        ))
        return false;
    const freeAddress = cast(size_t) freeBase;
    if (freeAddress < reservationBase)
        return false;
    const freeOffset = freeAddress - reservationBase;
    if (!reservation.try_region(
            freeOffset,
            layout.freeIndices.region_bytes,
            freeIndices,
        ))
        return false;

    return true;
}

private bool tryAddRegionBytes(
    ref size_t total,
    scope const VirtualArrayRegionGeometry geometry,
) pure @safe
{
    if (add_overflows(total, geometry.alignment_slack))
        return false;
    total += geometry.alignment_slack;
    if (add_overflows(total, geometry.region_bytes))
        return false;
    total += geometry.region_bytes;
    return true;
}
