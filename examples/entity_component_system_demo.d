module examples.entity_component_system_demo;

import xtb.core;

nothrow @nogc:

// Entity identity lives in a GenerationalPool. Component stores keep the full
// handle beside each component, so stale handles cannot alias a replacement
// entity that later reuses the same stable index.
struct Entity
{
}

alias EntityPool = GenerationalPool!Entity;
alias EntityId = EntityPool.Handle;

struct Position
{
    float x;
    float y;
}

struct Velocity
{
    float x;
    float y;
}

struct Health
{
    int current;
    int maximum;
}

struct Projectile
{
    float secondsRemaining;
}

private struct ComponentRecord(Component)
{
    EntityId entity;
    Component value;
}

/// Sparse component storage with stable component addresses and O(1) entity
/// lookup.
///
/// The Pool stores only present components. `byEntity_` maps a stable entity
/// index to a stable Pool index; zero means absent. A record also stores the
/// entity generation, so lookup through an old EntityId cannot return a
/// component belonging to a newer entity at the same index.
private struct ComponentStore(Component)
{
nothrow @nogc:

    alias Record = ComponentRecord!Component;
    alias Self = ComponentStore!Component;

    // This example keeps component replacement/removal deliberately simple.
    // Resource-owning component types would give their store an explicit
    // cleanup policy instead of overwriting/deallocating shallowly.
    static assert(__traits(isPOD, Component));

private:
    Pool!Record records_;
    VirtualArray!uint byEntity_;

public:
    @disable this(this);
    @disable ref Self opAssign(Self source) return;

    static Self create(uint entityCapacity) @system
    {
        Pool!Record records = Pool!Record.create(entityCapacity);
        VirtualArray!uint byEntity = VirtualArray!uint.create(
            cast(size_t) entityCapacity + 1,
        );

        Self result;
        moveEmplace(records, result.records_);
        moveEmplace(byEntity, result.byEntity_);
        return move(result);
    }

    void deinit() @system
    {
        byEntity_.deinit();
        records_.deinit();
    }

    /// Adds or replaces the component for one exact entity incarnation.
    Component* set(EntityId entity, Component value) @system
    {
        if (entity.index == 0 || entity.index > records_.capacity)
            panic("ComponentStore entity index is out of range");

        const requiredLength = cast(size_t) entity.index + 1;
        if (requiredLength > byEntity_.length && !byEntity_.tryResize(requiredLength))
            panic("ComponentStore index map commitment failed");

        const mappedIndex = byEntity_[entity.index];
        if (mappedIndex != 0)
        {
            Record* existing = records_.get(mappedIndex);
            if (existing !is null)
            {
                if (existing.entity == entity)
                {
                    existing.value = value;
                    return &existing.value;
                }

                // A different generation reused this entity index. World
                // destruction normally removes the old record first, but
                // reclaiming it here keeps the store stale-handle-safe even
                // if it is used independently.
                records_.deallocate(existing);
            }
            byEntity_[entity.index] = 0;
        }

        Record record = Record(entity, value);
        Record* inserted = records_.tryConstruct(record);
        if (inserted is null)
            panic("ComponentStore component capacity exceeded");

        const componentIndex = records_.indexOf(inserted);
        assert(componentIndex != 0);
        byEntity_[entity.index] = componentIndex;
        return &inserted.value;
    }

    Component* get(EntityId entity) return @system
    {
        if (entity.index == 0 || entity.index >= byEntity_.length)
            return null;

        const componentIndex = byEntity_[entity.index];
        if (componentIndex == 0)
            return null;

        Record* record = records_.get(componentIndex);
        if (record is null || record.entity != entity)
            return null;
        return &record.value;
    }

    const(Component)* get(EntityId entity) const return @system
    {
        if (entity.index == 0 || entity.index >= byEntity_.length)
            return null;

        const componentIndex = byEntity_[entity.index];
        if (componentIndex == 0)
            return null;

        const(Record)* record = records_.get(componentIndex);
        if (record is null || record.entity != entity)
            return null;
        return &record.value;
    }

    bool contains(EntityId entity) const @system
    {
        return get(entity) !is null;
    }

    bool remove(EntityId entity) @system
    {
        if (entity.index == 0 || entity.index >= byEntity_.length)
            return false;

        const componentIndex = byEntity_[entity.index];
        if (componentIndex == 0)
            return false;

        Record* record = records_.get(componentIndex);
        if (record is null || record.entity != entity)
            return false;

        byEntity_[entity.index] = 0;
        records_.deallocate(record);
        return true;
    }

    void clear() @system
    {
        records_.clear();
        byEntity_.clear();
    }

    auto entries() return @trusted
    {
        return records_.items();
    }

    auto entries() const return @trusted
    {
        return records_.items();
    }

    auto occupiedEntries() return @trusted
    {
        return records_.occupiedSlots();
    }

    size_t liveCount() const pure @safe
    {
        return records_.liveCount;
    }
}

private struct World
{
nothrow @nogc:

    alias Self = World;

private:
    EntityPool entities_;
    ComponentStore!Position positions_;
    ComponentStore!Velocity velocities_;
    ComponentStore!Health health_;
    ComponentStore!Projectile projectiles_;
    VirtualArray!EntityId destroyQueue_;

public:
    @disable this(this);
    @disable ref Self opAssign(Self source) return;

    static Self create(uint maxEntities) @system
    {
        EntityPool entities = EntityPool.create(maxEntities);
        ComponentStore!Position positions = ComponentStore!Position.create(maxEntities);
        ComponentStore!Velocity velocities = ComponentStore!Velocity.create(maxEntities);
        ComponentStore!Health health = ComponentStore!Health.create(maxEntities);
        ComponentStore!Projectile projectiles = ComponentStore!Projectile.create(maxEntities);
        VirtualArray!EntityId destroyQueue = VirtualArray!EntityId.create(maxEntities);

        Self result;
        moveEmplace(entities, result.entities_);
        moveEmplace(positions, result.positions_);
        moveEmplace(velocities, result.velocities_);
        moveEmplace(health, result.health_);
        moveEmplace(projectiles, result.projectiles_);
        moveEmplace(destroyQueue, result.destroyQueue_);
        return move(result);
    }

    void deinit() @system
    {
        destroyQueue_.deinit();
        projectiles_.deinit();
        health_.deinit();
        velocities_.deinit();
        positions_.deinit();
        entities_.deinit();
    }

    EntityId createEntity() @system
    {
        return entities_.construct();
    }

    bool alive(EntityId entity) const @system
    {
        return entities_.contains(entity);
    }

    bool destroyEntity(EntityId entity) @system
    {
        if (!entities_.contains(entity))
            return false;

        projectiles_.remove(entity);
        health_.remove(entity);
        velocities_.remove(entity);
        positions_.remove(entity);
        return entities_.tryDeallocate(entity);
    }

    size_t entityCount() const pure @safe
    {
        return entities_.liveCount;
    }

    Position* setPosition(EntityId entity, Position value) @system
    {
        requireAlive(entity);
        return positions_.set(entity, value);
    }

    Velocity* setVelocity(EntityId entity, Velocity value) @system
    {
        requireAlive(entity);
        return velocities_.set(entity, value);
    }

    Health* setHealth(EntityId entity, Health value) @system
    {
        requireAlive(entity);
        return health_.set(entity, value);
    }

    Projectile* setProjectile(EntityId entity, Projectile value) @system
    {
        requireAlive(entity);
        return projectiles_.set(entity, value);
    }

    Position* position(EntityId entity) return @system
    {
        return positions_.get(entity);
    }

    Health* health(EntityId entity) return @system
    {
        return health_.get(entity);
    }

private:
    void requireAlive(EntityId entity) const @system
    {
        if (!entities_.contains(entity))
            panic("component operation requires a live entity");
    }
}

private void movementSystem(World* world, float seconds) @system
{
    foreach (ref velocity; world.velocities_.entries())
    {
        Position* position = world.positions_.get(velocity.entity);
        if (position is null)
            continue;

        position.x += velocity.value.x * seconds;
        position.y += velocity.value.y * seconds;
    }
}

private void projectileLifetimeSystem(World* world, float seconds) @system
{
    // Structural Pool mutation invalidates active ranges, so destruction is
    // deliberately two-phase: collect handles while iterating, destroy after
    // the range is finished. VirtualArray keeps this queue stable and bounded.
    world.destroyQueue_.clear();

    foreach (ref projectile; world.projectiles_.entries())
    {
        projectile.value.secondsRemaining -= seconds;
        if (projectile.value.secondsRemaining <= 0)
            world.destroyQueue_.append(projectile.entity);
    }

    foreach (entity; world.destroyQueue_.slice)
        world.destroyEntity(entity);
}

private bool damage(World* world, EntityId entity, int amount) @system
{
    Health* health = world.health(entity);
    if (health is null)
        return false;

    health.current -= amount;
    if (health.current > 0)
        return false;
    return world.destroyEntity(entity);
}

private void printWorldStats(scope const World* world, uint frame) @system
{
    formatln!"frame {}: entities={}, positions={}, velocities={}, health={}, projectiles={}"(
        frame,
        world.entityCount,
        world.positions_.liveCount,
        world.velocities_.liveCount,
        world.health_.liveCount,
        world.projectiles_.liveCount,
    );
}

extern (C) int main() nothrow @nogc
{
    enum uint maxEntities = 100_000;
    enum uint enemyCount = 1_000;
    enum uint projectileCount = 256;

    World world = World.create(maxEntities);
    scope (exit)
        world.deinit();

    EntityId player = world.createEntity();
    world.setPosition(player, Position(0, 0));
    world.setVelocity(player, Velocity(2.5f, 0));
    world.setHealth(player, Health(100, 100));

    // Immediate recycle demonstrates why entity identity needs a generation.
    EntityId old = world.createEntity();
    world.setPosition(old, Position(-100, -100));
    const destroyedOld = world.destroyEntity(old);
    assert(destroyedOld);

    EntityId replacement = world.createEntity();
    assert(replacement.index == old.index);
    assert(replacement.generation != old.generation);
    world.setPosition(replacement, Position(10, 10));
    assert(world.positions_.get(old) is null);
    assert(world.positions_.get(replacement) !is null);
    world.destroyEntity(replacement);

    EntityId firstEnemy;
    foreach (index; 0 .. enemyCount)
    {
        EntityId enemy = world.createEntity();
        if (index == 0)
            firstEnemy = enemy;

        world.setPosition(
            enemy,
            Position(cast(float) index * 0.25f, cast(float)(index % 17)),
        );
        world.setVelocity(
            enemy,
            Velocity(-0.5f - cast(float)(index % 5) * 0.1f, 0.05f),
        );
        world.setHealth(enemy, Health(20 + cast(int)(index % 4) * 5, 35));
    }

    foreach (index; 0 .. projectileCount)
    {
        EntityId projectile = world.createEntity();
        world.setPosition(projectile, Position(0, cast(float)(index % 8)));
        world.setVelocity(
            projectile,
            Velocity(12.0f + cast(float)(index % 4), 0),
        );
        world.setProjectile(
            projectile,
            Projectile(0.25f + cast(float)(index % 5) * 0.10f),
        );
    }

    printWorldStats(&world, 0);

    enum float fixedStep = 1.0f / 60.0f;
    foreach (frame; 1 .. 121)
    {
        movementSystem(&world, fixedStep);
        projectileLifetimeSystem(&world, fixedStep);

        if (frame == 30 || frame == 60 || frame == 90)
        {
            const destroyed = damage(&world, firstEnemy, 10);
            if (frame == 60)
                assert(destroyed);
            else
                assert(!destroyed);
        }

        if (frame % 30 == 0)
            printWorldStats(&world, frame);
    }

    assert(world.alive(player));
    assert(world.position(player) !is null);
    assert(world.position(player).x > 4.9f);
    assert(world.projectiles_.liveCount == 0);

    // When component-pool identity matters, occupiedSlots() exposes the stable
    // Pool index without wrapping the common items() path in a proxy.
    auto positionSlots = world.positions_.occupiedEntries();
    assert(!positionSlots.empty);
    auto firstPositionSlot = positionSlots.front;
    formatln!"component slot {} belongs to entity index={} generation={}"(
        firstPositionSlot.index,
        firstPositionSlot.value.entity.index,
        firstPositionSlot.value.entity.generation,
    );

    formatln!"player handle: index={}, generation={}, x={}"(
        player.index,
        player.generation,
        world.position(player).x,
    );
    return 0;
}
