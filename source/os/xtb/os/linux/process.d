module xtb.os.linux.process;

nothrow @nogc:

import xtb.os.posix.spawn : posix_spawn_file_actions_t;

extern (C) pragma(mangle, "pidfd_open")
int pidfdOpen(int processId, uint flags);

extern (C) pragma(mangle, "posix_spawn_file_actions_addchdir_np")
int spawnFileActionsAddChdir(
    posix_spawn_file_actions_t* actions,
    const(char)* path,
);

extern (C) pragma(mangle, "posix_spawn_file_actions_addclosefrom_np")
int spawnFileActionsAddCloseFrom(
    posix_spawn_file_actions_t* actions,
    int from,
);
