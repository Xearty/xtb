#include "xtb_core/str.h"
#define _XOPEN_SOURCE 500
#define __USE_XOPEN_EXTENDED
#include <xtb_os/os.h>
#include <xtb_core/linked_list.h>
#include <xtb_core/thread_context.h>

#include <stdbool.h>
#include <stdio.h>
#include <string.h>

#include <unistd.h>
#include <ftw.h>
#include <sys/stat.h>

#ifndef __USE_MISC
#define __USE_MISC
#endif
#include <dirent.h>

static bool access_helper(String filepath, int check_value)
{
    TempArena scratch = scratch_begin_no_conflicts();
    filepath = str_push_copy(scratch.arena, filepath);
    bool result = access(filepath.str, check_value) == 0;
    scratch_end(scratch);
    return result;
}

bool os_file_exists(String filepath)
{
    return access_helper(filepath, F_OK);
}

bool os_create_directory(String path)
{
    TempArena scratch = scratch_begin_no_conflicts();
    path = str_push_copy(scratch.arena, path);

    i32 state = 0;
    if (!os_file_exists(path))
    {
        state = mkdir((const char *)path.str, 0700);
    }
    scratch_end(scratch);
    return state == 0;
}

bool os_file_has_read_permission(String filepath)
{
    return access_helper(filepath, R_OK);
}

bool os_file_has_write_permission(String filepath)
{
    return access_helper(filepath, W_OK);
}

bool os_file_has_execute_permission(String filepath)
{
    return access_helper(filepath, X_OK);
}

bool os_file_is_regular(String filepath)
{
    return os_get_file_type(filepath) == FT_REGULAR;
}

bool os_file_is_directory(String filepath)
{
    return os_get_file_type(filepath) == FT_DIRECTORY;
}

bool os_file_is_regular_nofollow(String filepath)
{
    return os_get_file_type_nofollow(filepath) == FT_REGULAR;
}

bool os_file_is_directory_nofollow(String filepath)
{
    return os_get_file_type_nofollow(filepath) == FT_DIRECTORY;
}

bool os_file_is_symbolic_link(String filepath)
{
    return os_get_file_type_nofollow(filepath) == FT_SYMLINK;
}

FileType os_get_file_type(String filepath)
{
    struct stat st;

    TempArena scratch = scratch_begin_no_conflicts();
    filepath = str_push_copy(scratch.arena, filepath);
    int state = stat(filepath.str, &st);
    scratch_end(scratch);

    if (state != 0) return FT_UNKNOWN;

    switch (st.st_mode & S_IFMT)
    {
        case S_IFREG:  return FT_REGULAR;
        case S_IFDIR:  return FT_DIRECTORY;
        case S_IFLNK:  return FT_SYMLINK;
        case S_IFCHR:  return FT_CHAR_DEVICE;
        case S_IFBLK:  return FT_BLOCK_DEVICE;
        case S_IFIFO:  return FT_FIFO;
        case S_IFSOCK: return FT_SOCKET;
        default:       return FT_UNKNOWN;
    }
}

FileType os_get_file_type_nofollow(String filepath)
{
    struct stat st;

    TempArena scratch = scratch_begin_no_conflicts();
    filepath = str_push_copy(scratch.arena, filepath);
    int state = lstat(filepath.str, &st);
    scratch_end(scratch);

    if (state != 0) return FT_UNKNOWN;

    switch (st.st_mode & S_IFMT)
    {
        case S_IFREG:  return FT_REGULAR;
        case S_IFDIR:  return FT_DIRECTORY;
        case S_IFLNK:  return FT_SYMLINK;
        case S_IFCHR:  return FT_CHAR_DEVICE;
        case S_IFBLK:  return FT_BLOCK_DEVICE;
        case S_IFIFO:  return FT_FIFO;
        case S_IFSOCK: return FT_SOCKET;
        default:       return FT_UNKNOWN;
    }
}

static int unlink_cb(const char *filepath, const struct stat *sb, int typeflag, struct FTW *ftwbuf)
{
    return remove(filepath);
}

bool os_delete_directory(String filepath)
{
    TempArena scratch = scratch_begin_no_conflicts();
    filepath = str_push_copy(scratch.arena, filepath);
    bool success = nftw(filepath.str, unlink_cb, 64, FTW_DEPTH | FTW_PHYS) == 0;
    scratch_end(scratch);
    return success;
}

static bool should_skip_file_in_listing(String filepath, DirectoryListFlags flags)
{
    if (!(flags & DIR_LIST_CURR) && str_eq_lit(filepath, ".")) return true;;
    if (!(flags & DIR_LIST_PREV) && str_eq_lit(filepath, "..")) return true;
    return false;
}

FileType dirent_ft_to_ft(int ft)
{
    switch (ft)
    {
        case DT_REG:  return FT_REGULAR;
        case DT_DIR:  return FT_DIRECTORY;
        case DT_LNK:  return FT_SYMLINK;
        case DT_CHR:  return FT_CHAR_DEVICE;
        case DT_BLK:  return FT_BLOCK_DEVICE;
        case DT_FIFO: return FT_FIFO;
        case DT_SOCK: return FT_SOCKET;
        default:      return FT_UNKNOWN;
    }
}

DirectoryList os_list_directory_custom(Allocator* allocator, String filepath, DirectoryListFlags flags)
{
    TempArena scratch = scratch_begin_conflict(allocator);
    filepath = str_push_copy(scratch.arena, filepath);
    DIR *dir = opendir(filepath.str);
    scratch_end(scratch);

    DirectoryList list = {0};

    if (dir == NULL)
    {
        perror("opendir failed");
        return list;
    }

    struct dirent *entry;
    while ((entry = readdir(dir)))
    {
        String entry_str = cstr(entry->d_name);

        if (should_skip_file_in_listing(entry_str, flags)) continue;

        String path_parts[] = { filepath, entry_str };

        DirectoryListNode *node = Allocate(allocator, DirectoryListNode);
        node->type = dirent_ft_to_ft(entry->d_type);
        node->path = os_path_join(allocator, path_parts, ArrLen(path_parts));
        DLLPushBack(list.head, list.tail, node);
    }

    closedir(dir);
    return list;
}

DirectoryList os_list_directory(Allocator* allocator, String filepath)
{
    return os_list_directory_custom(allocator, filepath, DIR_LIST_NONE);
}

DirectoryList os_list_directory_recursively(Allocator* allocator, String filepath)
{
    DirectoryList entries = os_list_directory(allocator, filepath);
    DirectoryList accumulator = entries;

    IterateList(entries, DirectoryListNode, entry)
    {
        if (entry->type == FT_DIRECTORY)
        {
            DirectoryList children =
                os_list_directory_recursively(allocator, entry->path);

            if (children.head != NULL)
            {
                DLLConcat(accumulator, children);
            }
        }
    }

    return accumulator;
}
