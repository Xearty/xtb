module xtb.os.posix.file;

nothrow @nogc:

public import core.sys.posix.fcntl : O_APPEND, O_CLOEXEC, O_CREAT, O_EXCL,
    O_RDONLY, O_RDWR, O_TRUNC, O_WRONLY, open;
public import core.sys.posix.sys.stat : S_IFBLK, S_IFCHR, S_IFDIR, S_IFIFO,
    S_IFLNK, S_IFMT, S_IFREG, S_IFSOCK, fstat, lstat, stat, stat_t;
public import core.sys.posix.unistd : STDERR_FILENO, close, fsync, read, write;
