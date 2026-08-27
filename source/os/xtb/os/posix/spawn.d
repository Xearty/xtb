module xtb.os.posix.spawn;

nothrow @nogc:

public import core.sys.posix.spawn : POSIX_SPAWN_SETPGROUP, POSIX_SPAWN_SETSIGMASK,
    posix_spawn, posix_spawn_file_actions_adddup2,
    posix_spawn_file_actions_addopen, posix_spawn_file_actions_destroy,
    posix_spawn_file_actions_init, posix_spawn_file_actions_t,
    posix_spawnattr_destroy, posix_spawnattr_init, posix_spawnattr_setflags,
    posix_spawnattr_setpgroup, posix_spawnattr_setsigmask, posix_spawnattr_t;
