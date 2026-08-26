module examples.pool_world_demo;

import xtb;

nothrow @nogc:

struct Vec2
{
    float x;
    float y;
}

struct Position
{
    Vec2 value;
    Vec2 velocity;
}

alias PositionPool = GenerationalPool!Position;
alias PositionId = PositionPool.Handle;

struct Health
{
    int current;
}

alias HealthPool = GenerationalPool!Health;
alias HealthId = HealthPool.Handle;

// Render keeps the component handles it needs while Entity keeps the RenderId
// that owns this render component. The pools do not need a global
// entity-to-component lookup table.
struct Render
{
    PositionId position;
    HealthId health;
}

alias RenderPool = GenerationalPool!Render;
alias RenderId = RenderPool.Handle;

struct Attack
{
    HealthId target;
    int damage;
}

alias AttackPool = GenerationalPool!Attack;
alias AttackId = AttackPool.Handle;

// Entity is a small composition root. It contains identities of independently
// pooled pieces rather than embedding their storage.
struct Entity
{
    PositionId position;
    HealthId health;
    RenderId render;
    AttackId attack;
}

alias EntityPool = GenerationalPool!Entity;
alias EntityId = EntityPool.Handle;

private enum tickStyle = AnsiColor.brightCyan.foreground.bold;
private enum moveStyle = AnsiColor.brightBlue.foreground;
private enum attackStyle = AnsiColor.brightYellow.foreground;
private enum staleStyle = AnsiColor.brightBlack.foreground.dim;
private enum cullStyle = AnsiColor.brightRed.foreground.bold;
private enum renderStyle = AnsiColor.brightMagenta.foreground;
private enum spawnStyle = AnsiColor.brightGreen.foreground.bold;
private enum stateStyle = AnsiColor.brightWhite.foreground.dim;

// Pool identities keep a stable color throughout the trace so relationships
// remain easy to follow across systems and generations.
private enum entityIdStyle = AnsiColor.brightCyan.foreground;
private enum positionIdStyle = AnsiColor.brightBlue.foreground;
private enum healthIdStyle = AnsiColor.brightGreen.foreground;
private enum renderIdStyle = AnsiColor.brightMagenta.foreground;
private enum attackIdStyle = AnsiColor.brightYellow.foreground;
private enum positionValueStyle = AnsiColor.cyan.foreground;
private enum healthValueStyle = AnsiColor.green.foreground;
private enum damageStyle = AnsiColor.brightRed.foreground.bold;
private enum countStyle = AnsiColor.brightWhite.foreground;

private auto poolId(Handle)(Handle handle)
{
    return formatted!"#{}:{}"(handle.index, handle.generation);
}

private struct World
{
nothrow @nogc:

    alias Self = World;

    PositionPool positions;
    HealthPool health;
    RenderPool renders;
    AttackPool attacks;
    EntityPool entities;
    VirtualArray!EntityId destroyQueue;

    @disable this(this);
    @disable ref Self opAssign(Self source) return;

    static Self create(uint capacity) @system
    {
        Self result = {
            positions: PositionPool.create(capacity),
            health: HealthPool.create(capacity),
            renders: RenderPool.create(capacity),
            attacks: AttackPool.create(capacity),
            entities: EntityPool.create(capacity),
            destroyQueue: VirtualArray!EntityId.create(capacity),
        };
        return move(result);
    }

    void deinit() @system
    {
        destroyQueue.deinit();
        entities.deinit();
        attacks.deinit();
        renders.deinit();
        health.deinit();
        positions.deinit();
    }
}

private EntityId spawnEntity(
    scope World* world,
    Vec2 position,
    Vec2 velocity,
    int health,
) @system
{
    PositionId positionId = world.positions.construct(position, velocity);
    HealthId healthId = world.health.construct(health);
    RenderId renderId = world.renders.construct(positionId, healthId);
    return world.entities.construct(positionId, healthId, renderId, AttackId.init);
}

private void addAttack(scope World* world, EntityId attacker, HealthId target, int damage) @system
{
    Entity* entity = world.entities.get(attacker);
    if (entity is null)
        panic("attacker entity is stale");
    if (entity.attack.valid)
        panic("attacker already has an Attack component");

    entity.attack = world.attacks.construct(target, damage);
    formatln!"  {} entity {} owns attack {} -> health {} (damage={})"(
        styled("[attack]", attackStyle),
        styled(poolId(attacker), entityIdStyle),
        styled(poolId(entity.attack), attackIdStyle),
        styled(poolId(target), healthIdStyle),
        styled(damage, damageStyle),
    );
}

private void retargetAttack(scope World* world, EntityId attacker, HealthId target) @system
{
    Entity* entity = world.entities.get(attacker);
    if (entity is null)
        panic("attacker entity is stale");

    Attack* attack = world.attacks.get(entity.attack);
    if (attack is null)
        panic("attacker has no live Attack component");
    attack.target = target;
    formatln!"  {} attack {} retargeted -> health {}"(
        styled("[attack]", attackStyle),
        styled(poolId(entity.attack), attackIdStyle),
        styled(poolId(target), healthIdStyle),
    );
}

private void destroyEntity(scope World* world, EntityId id) @system
{
    Entity* entity = world.entities.get(id);
    if (entity is null)
        return;

    // Entity owns these component handles. Deallocation preserves their
    // representations while advancing each pool's generation.
    if (entity.attack.valid)
        cast(void) world.attacks.tryDeallocate(entity.attack);
    cast(void) world.renders.tryDeallocate(entity.render);
    cast(void) world.health.tryDeallocate(entity.health);
    cast(void) world.positions.tryDeallocate(entity.position);
    cast(void) world.entities.tryDeallocate(id);
}

// Position is deliberately plain numerical state. Freshly provisioned pages
// are zero-filled, deallocation does not overwrite the value representation,
// and construction overwrites a slot when it is reused. This system can
// therefore process every provisioned slot without testing occupancy. It may do
// some harmless arithmetic on inactive slots in exchange for a tight,
// branch-free contiguous loop.
private void tickPositions(scope PositionPool* positions, float seconds) @system
{
    foreach (slot; positions.slots())
    {
        ref position = slot.storage;
        position.value.x += position.velocity.x * seconds;
        position.value.y += position.velocity.y * seconds;
    }
}

// Other systems do care about liveness. Attack components use the pool's
// live-item range, and their target is resolved through a
// generational HealthId. A stale target simply stops receiving damage.
private void tickAttacks(scope AttackPool* attacks, scope HealthPool* health) @system
{
    foreach (item; attacks.indexedItems())
    {
        ref attack = item.value;
        Health* target = health.get(attack.target);
        if (target is null)
        {
            formatln!"  {} attack slot {} -> health {} no longer resolves"(
                styled("[stale]", staleStyle),
                styled(item.index, attackIdStyle),
                styled(poolId(attack.target), healthIdStyle),
            );
            continue;
        }

        const before = target.current;
        target.current -= attack.damage;
        const afterStyle = target.current <= 0 ? damageStyle : healthValueStyle;
        formatln!"  {} attack slot {} -> health {}: {} -> {}"(
            styled("[attack]", attackStyle),
            styled(item.index, attackIdStyle),
            styled(poolId(attack.target), healthIdStyle),
            styled(before, healthValueStyle),
            styled(target.current, afterStyle),
        );
    }
}

private size_t cullDeadEntities(scope World* world) @system
{
    world.destroyQueue.clear();

    // Structural mutation would invalidate this range, so collect handles
    // first and destroy them after entity iteration has finished.
    foreach (slot; world.entities.occupiedSlots())
    {
        const Entity* entity = &slot.value();
        const(Health)* health = world.health.get(entity.health);
        if (health !is null && health.current <= 0)
        {
            formatln!"  {} entity {} reached hp={} and will be recycled"(
                styled("[cull]", cullStyle),
                styled(poolId(slot.handle), entityIdStyle),
                styled(health.current, damageStyle),
            );
            world.destroyQueue.append(slot.handle);
        }
    }

    const count = world.destroyQueue.length;
    foreach (id; world.destroyQueue.slice)
        destroyEntity(world, id);
    return count;
}

private void renderWorld(scope const World* world) @system
{
    foreach (item; world.renders.indexedItems())
    {
        ref const render = item.value;
        const(Position)* position = world.positions.get(render.position);
        const(Health)* health = world.health.get(render.health);
        if (position is null || health is null)
            continue;

        const positionText = formatted!"({}, {})"(
            position.value.x,
            position.value.y,
        );
        formatln!"  {} render slot {} -> position {}={}, health {}={}"(
            styled("[render]", renderStyle),
            styled(item.index, renderIdStyle),
            styled(poolId(render.position), positionIdStyle),
            styled(positionText, positionValueStyle),
            styled(poolId(render.health), healthIdStyle),
            styled(health.current, healthValueStyle),
        );
    }
}

private size_t tickWorld(scope World* world, uint tick, float seconds) @system
{
    formatln!"{} {}"(
        styled("tick", tickStyle),
        styled(tick, countStyle),
    );

    formatln!"  {} branchless update over {}"(
        styled("[move]", moveStyle),
        styled("every provisioned position slot", positionIdStyle),
    );
    tickPositions(&world.positions, seconds);
    tickAttacks(&world.attacks, &world.health);
    const removed = cullDeadEntities(world);
    renderWorld(world);

    const removedStyle = removed == 0 ? stateStyle : cullStyle;
    formatln!"  {} live entities={}, removed={}"(
        styled("[state]", stateStyle),
        styled(world.entities.liveCount, entityIdStyle),
        styled(removed, removedStyle),
    );
    return removed;
}

extern (C) int main() nothrow @nogc
{
    enum uint capacity = 1_024;

    World world = World.create(capacity);
    scope (exit)
        world.deinit();

    EntityId enemy = spawnEntity(
        &world,
        Vec2(6, 0),
        Vec2(-0.5f, 0),
        30,
    );
    EntityId player = spawnEntity(
        &world,
        Vec2(0, 0),
        Vec2(1, 0),
        100,
    );

    formatln!"  {} enemy entity {}, player entity {}"(
        styled("[spawn]", spawnStyle),
        styled(poolId(enemy), entityIdStyle),
        styled(poolId(player), entityIdStyle),
    );

    const Entity* enemyEntity = world.entities.get(enemy);
    assert(enemyEntity !is null);
    const oldEnemyPosition = enemyEntity.position;
    const oldEnemyHealth = enemyEntity.health;
    const oldEnemyRender = enemyEntity.render;

    addAttack(&world, player, oldEnemyHealth, 10);

    // Movement feeds rendering; attacks feed health; health feeds culling.
    // The third tick kills the enemy and recycles all of its owned pool slots.
    foreach (tick; 0 .. 3)
    {
        const removed = tickWorld(&world, tick, 1.0f);
        assert(removed == (tick == 2 ? 1 : 0));
    }
    assert(!world.entities.contains(enemy));

    // A replacement reuses the same stable indices but receives new
    // generations. The player's Attack still contains oldEnemyHealth, so tick
    // 3 must not accidentally damage the replacement.
    EntityId replacement = spawnEntity(
        &world,
        Vec2(12, 0),
        Vec2(-1, 0),
        40,
    );
    const Entity* replacementEntity = world.entities.get(replacement);
    assert(replacementEntity !is null);
    assert(replacement.index == enemy.index);
    assert(replacement.generation != enemy.generation);
    assert(replacementEntity.position.index == oldEnemyPosition.index);
    assert(replacementEntity.position.generation != oldEnemyPosition.generation);
    assert(replacementEntity.health.index == oldEnemyHealth.index);
    assert(replacementEntity.health.generation != oldEnemyHealth.generation);
    assert(replacementEntity.render.index == oldEnemyRender.index);
    assert(replacementEntity.render.generation != oldEnemyRender.generation);

    formatln!"  {} replacement entity {} reused enemy slot {} with a new generation"(
        styled("[spawn]", spawnStyle),
        styled(poolId(replacement), entityIdStyle),
        styled(enemy.index, entityIdStyle),
    );
    formatln!"  {} player's attack still targets old health {}"(
        styled("[stale]", staleStyle),
        styled(poolId(oldEnemyHealth), healthIdStyle),
    );

    cast(void) tickWorld(&world, 3, 1.0f);
    const(Health)* replacementHealth = world.health.get(replacementEntity.health);
    assert(replacementHealth !is null);
    assert(replacementHealth.current == 40);

    // Retarget the live Attack component explicitly. The next system pass now
    // sees the new HealthId and damages the replacement.
    retargetAttack(&world, player, replacementEntity.health);
    cast(void) tickWorld(&world, 4, 1.0f);
    const(Health)* retargetedHealth = world.health.get(replacementEntity.health);
    assert(retargetedHealth !is null);
    assert(retargetedHealth.current == 30);

    return 0;
}
