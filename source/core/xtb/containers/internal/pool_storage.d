module xtb.containers.internal.pool_storage;

nothrow @nogc:

import xtb.allocators.internal.virtual_memory : VirtualMemoryRegion,
    VirtualMemoryReservation;
import xtb.numeric : addOverflows;
import xtb.containers.virtual_array : tryAlignAddressUp,
    tryVirtualArrayRegionGeometry, VirtualArrayRegionGeometry;

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
    if (addOverflows(capacityAsSize, 1))
        return false;

    IndexedPoolStorageLayout result;
    result.valueCapacity = capacityAsSize + 1;
    result.stateCapacity = stateCapacity;
    if (!tryVirtualArrayRegionGeometry!T(
            result.valueCapacity,
            pageSize,
            &result.values,
        ))
        return false;
    if (!tryVirtualArrayRegionGeometry!State(
            stateCapacity,
            pageSize,
            &result.states,
        ))
        return false;
    if (!tryVirtualArrayRegionGeometry!uint(
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
    if (!tryAlignAddressUp(
            cast(void*) cursor,
            layout.values.baseAlignment,
            &valuesBase,
        ))
        return false;
    const valuesAddress = cast(size_t) valuesBase;
    if (valuesAddress < reservationBase)
        return false;
    const valuesOffset = valuesAddress - reservationBase;
    if (!reservation.tryRegion(valuesOffset, layout.values.regionBytes, values))
        return false;
    if (addOverflows(valuesAddress, layout.values.regionBytes))
        return false;
    cursor = valuesAddress + layout.values.regionBytes;

    void* statesBase;
    if (!tryAlignAddressUp(
            cast(void*) cursor,
            layout.states.baseAlignment,
            &statesBase,
        ))
        return false;
    const statesAddress = cast(size_t) statesBase;
    if (statesAddress < reservationBase)
        return false;
    const statesOffset = statesAddress - reservationBase;
    if (!reservation.tryRegion(
            statesOffset,
            layout.states.regionBytes,
            states,
        ))
        return false;
    if (addOverflows(statesAddress, layout.states.regionBytes))
        return false;
    cursor = statesAddress + layout.states.regionBytes;

    void* freeBase;
    if (!tryAlignAddressUp(
            cast(void*) cursor,
            layout.freeIndices.baseAlignment,
            &freeBase,
        ))
        return false;
    const freeAddress = cast(size_t) freeBase;
    if (freeAddress < reservationBase)
        return false;
    const freeOffset = freeAddress - reservationBase;
    if (!reservation.tryRegion(
            freeOffset,
            layout.freeIndices.regionBytes,
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
    if (addOverflows(total, geometry.alignmentSlack))
        return false;
    total += geometry.alignmentSlack;
    if (addOverflows(total, geometry.regionBytes))
        return false;
    total += geometry.regionBytes;
    return true;
}
