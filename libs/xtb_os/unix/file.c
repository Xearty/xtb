#define _XOPEN_SOURCE 500
#define __USE_XOPEN_EXTENDED
#include <xtb_os/os.h>

#include <stdbool.h>
#include <stdio.h>

#include <unistd.h>
#include <ftw.h>
#include <sys/stat.h>

bool xtb_os_file_exists(const char *filepath)
{
    return access(filepath, F_OK) == 0;
}

bool xtb_os_file_has_read_permission(const char *filepath)
{
    return access(filepath, R_OK) == 0;
}

bool xtb_os_file_has_write_permission(const char *filepath)
{
    return access(filepath, W_OK) == 0;
}

bool xtb_os_file_has_execute_permission(const char *filepath)
{
    return access(filepath, X_OK) == 0;
}

bool xtb_os_is_regular_file(const char *filepath)
{
    struct stat path_stat;
    if (stat(filepath, &path_stat) != 0) return false;
    return S_ISREG(path_stat.st_mode);
}

bool xtb_os_is_directory(const char *filepath)
{
    struct stat path_stat;
    if (stat(filepath, &path_stat) != 0) return false;
    return S_ISDIR(path_stat.st_mode);
}

bool xtb_os_is_regular_file_nofollow(const char *filepath)
{
    struct stat path_stat;
    if (lstat(filepath, &path_stat) != 0) return false;
    return S_ISREG(path_stat.st_mode);
}

bool xtb_os_is_directory_nofollow(const char *filepath)
{
    struct stat path_stat;
    if (lstat(filepath, &path_stat) != 0) return false;
    return S_ISDIR(path_stat.st_mode);
}

bool xtb_os_is_symbolic_link(const char *filepath)
{
    struct stat path_stat;
    if (lstat(filepath, &path_stat) != 0) return false;
    return S_ISLNK(path_stat.st_mode);
}

XTB_File_Type xtb_os_get_file_type_nofollow(const char *filepath)
{
    if (xtb_os_is_regular_file_nofollow(filepath))
    {
        return XTB_FT_REGULAR;
    }
    else if (xtb_os_is_directory_nofollow(filepath))
    {
        return XTB_FT_DIRECTORY;
    }
    else if (xtb_os_is_symbolic_link(filepath))
    {
        return XTB_FT_SYMLINK;
    }

    return XTB_FT_UNKNOWN;
}

XTB_File_Type xtb_os_get_file_type(const char *filepath)
{
    if (xtb_os_is_regular_file(filepath))
    {
        return XTB_FT_REGULAR;
    }
    else if (xtb_os_is_directory(filepath))
    {
        return XTB_FT_DIRECTORY;
    }

    return XTB_FT_UNKNOWN;
}

static int unlink_cb(const char *filepath, const struct stat *sb, int typeflag, struct FTW *ftwbuf)
{
    return remove(filepath);
}

bool xtb_os_delete_directory(const char *filepath)
{
    return nftw(filepath, unlink_cb, 64, FTW_DEPTH | FTW_PHYS) == 0;
}

