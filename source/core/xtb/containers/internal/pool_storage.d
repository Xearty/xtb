module xtb.containers.internal.pool_storage;

nothrow @nogc:

import xtb.allocators.internal.virtual_memory;
import xtb.containers.virtual_array;
import xtb.numeric;
import xtb.types;

/// Shared fixed-capacity three-region geometry for indexed Pool containers.
///
/// The regions are, in order: stable `T` values, caller-selected per-index
/// state, and a `u32` recycling stack. This module is package-private storage
/// machinery shared by `Pool!T` and `GenerationalPool!T`.
package(xtb.containers) struct IndexedPoolStorageLayout
{
    VirtualArrayRegionGeometry values;
    VirtualArrayRegionGeometry states;
    VirtualArrayRegionGeometry free_indices;
    usize value_capacity;
    usize state_capacity;
    usize reservation_bytes;
}

/// Computes the shared indexed-pool reservation layout.
///
/// Returns false when `output` is null; otherwise it is updated only on success.
package(xtb.containers) bool try_indexed_pool_storage_layout(T, State)(
    u32 capacity,
    usize state_capacity,
    usize page_size,
    scope IndexedPoolStorageLayout* output,
) pure @safe
{
    if (output is null || capacity == 0 || state_capacity == 0 || page_size == 0) return false;

    const capacity_as_size = cast(usize) capacity;
    if (add_overflows(capacity_as_size, 1)) return false;

    IndexedPoolStorageLayout result;
    result.value_capacity = capacity_as_size + 1;
    result.state_capacity = state_capacity;
    if (!try_virtual_array_region_geometry!T(result.value_capacity, page_size, &result.values))
        return false;

    if (!try_virtual_array_region_geometry!State(state_capacity, page_size, &result.states))
        return false;

    if (!try_virtual_array_region_geometry!u32(capacity_as_size, page_size, &result.free_indices))
        return false;

    usize total;
    if (!try_add_region_bytes(total, result.values)) return false;
    if (!try_add_region_bytes(total, result.states)) return false;
    if (!try_add_region_bytes(total, result.free_indices)) return false;

    result.reservation_bytes = total;
    *output = result;
    return true;
}

/// Produces non-owning regions for an indexed-pool reservation.
///
/// Returns false when any output pointer is null. On later failure, outputs for
/// regions already created may have been updated; all returned regions are
/// non-owning.
package(xtb.containers) bool try_indexed_pool_storage_regions(
    scope ref VirtualMemoryReservation reservation,
    IndexedPoolStorageLayout layout,
    scope VirtualMemoryRegion* values,
    scope VirtualMemoryRegion* states,
    scope VirtualMemoryRegion* free_indices,
) @system
{
    if (values is null || states is null || free_indices is null) return false;

    const reservation_base = cast(usize) reservation.base;
    usize cursor = reservation_base;

    void* values_base;
    if (!try_align_address_up(cast(void*) cursor, layout.values.base_alignment, &values_base))
        return false;

    const values_address = cast(usize) values_base;
    if (values_address < reservation_base) return false;

    const values_offset = values_address - reservation_base;
    if (!reservation.try_region(values_offset, layout.values.region_bytes, values)) return false;
    if (add_overflows(values_address, layout.values.region_bytes)) return false;

    cursor = values_address + layout.values.region_bytes;

    void* states_base;
    if (!try_align_address_up(cast(void*) cursor, layout.states.base_alignment, &states_base))
        return false;

    const states_address = cast(usize) states_base;
    if (states_address < reservation_base) return false;

    const states_offset = states_address - reservation_base;
    if (!reservation.try_region(states_offset, layout.states.region_bytes, states)) return false;
    if (add_overflows(states_address, layout.states.region_bytes)) return false;

    cursor = states_address + layout.states.region_bytes;

    void* free_base;
    if (!try_align_address_up(cast(void*) cursor, layout.free_indices.base_alignment, &free_base))
        return false;

    const free_address = cast(usize) free_base;
    if (free_address < reservation_base) return false;

    const free_offset = free_address - reservation_base;
    if (!reservation.try_region(free_offset, layout.free_indices.region_bytes, free_indices))
        return false;

    return true;
}

private bool try_add_region_bytes(
    scope ref usize total,
    VirtualArrayRegionGeometry geometry,
) pure @safe
{
    if (add_overflows(total, geometry.alignment_slack)) return false;

    total += geometry.alignment_slack;
    if (add_overflows(total, geometry.region_bytes)) return false;

    total += geometry.region_bytes;
    return true;
}
