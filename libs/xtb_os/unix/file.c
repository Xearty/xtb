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

static bool access_helper(XTB_String8 filepath, int check_value)
{
    XTB_Temp_Arena scratch = xtb_scratch_begin_no_conflicts();
    filepath = xtb_str8_push_copy(scratch.arena, filepath);
    bool result = access(filepath.str, check_value) == 0;
    xtb_scratch_end(scratch);
    return result;
}

bool xtb_os_file_exists(XTB_String8 filepath)
{
    return access_helper(filepath, F_OK);
}

bool xtb_os_file_has_read_permission(XTB_String8 filepath)
{
    return access_helper(filepath, R_OK);
}

bool xtb_os_file_has_write_permission(XTB_String8 filepath)
{
    return access_helper(filepath, W_OK);
}

bool xtb_os_file_has_execute_permission(XTB_String8 filepath)
{
    return access_helper(filepath, X_OK);
}

bool xtb_os_file_is_regular(XTB_String8 filepath)
{
    return xtb_os_get_file_type(filepath) == XTB_FT_REGULAR;
}

bool xtb_os_file_is_directory(XTB_String8 filepath)
{
    return xtb_os_get_file_type(filepath) == XTB_FT_DIRECTORY;
}

bool xtb_os_file_is_regular_nofollow(XTB_String8 filepath)
{
    return xtb_os_get_file_type_nofollow(filepath) == XTB_FT_REGULAR;
}

bool xtb_os_file_is_directory_nofollow(XTB_String8 filepath)
{
    return xtb_os_get_file_type_nofollow(filepath) == XTB_FT_DIRECTORY;
}

bool xtb_os_file_is_symbolic_link(XTB_String8 filepath)
{
    return xtb_os_get_file_type_nofollow(filepath) == XTB_FT_SYMLINK;
}

XTB_File_Type xtb_os_get_file_type(XTB_String8 filepath)
{
    struct stat st;

    XTB_Temp_Arena scratch = xtb_scratch_begin_no_conflicts();
    filepath = xtb_str8_push_copy(scratch.arena, filepath);
    int state = stat(filepath.str, &st);
    xtb_scratch_end(scratch);

    if (state != 0) return XTB_FT_UNKNOWN;

    switch (st.st_mode & S_IFMT)
    {
        case S_IFREG:  return XTB_FT_REGULAR;
        case S_IFDIR:  return XTB_FT_DIRECTORY;
        case S_IFLNK:  return XTB_FT_SYMLINK;
        case S_IFCHR:  return XTB_FT_CHAR_DEVICE;
        case S_IFBLK:  return XTB_FT_BLOCK_DEVICE;
        case S_IFIFO:  return XTB_FT_FIFO;
        case S_IFSOCK: return XTB_FT_SOCKET;
        default:       return XTB_FT_UNKNOWN;
    }
}

XTB_File_Type xtb_os_get_file_type_nofollow(XTB_String8 filepath)
{
    struct stat st;

    XTB_Temp_Arena scratch = xtb_scratch_begin_no_conflicts();
    filepath = xtb_str8_push_copy(scratch.arena, filepath);
    int state = lstat(filepath.str, &st);
    xtb_scratch_end(scratch);

    if (state != 0) return XTB_FT_UNKNOWN;

    switch (st.st_mode & S_IFMT)
    {
        case S_IFREG:  return XTB_FT_REGULAR;
        case S_IFDIR:  return XTB_FT_DIRECTORY;
        case S_IFLNK:  return XTB_FT_SYMLINK;
        case S_IFCHR:  return XTB_FT_CHAR_DEVICE;
        case S_IFBLK:  return XTB_FT_BLOCK_DEVICE;
        case S_IFIFO:  return XTB_FT_FIFO;
        case S_IFSOCK: return XTB_FT_SOCKET;
        default:       return XTB_FT_UNKNOWN;
    }
}

static int unlink_cb(const char *filepath, const struct stat *sb, int typeflag, struct FTW *ftwbuf)
{
    return remove(filepath);
}

bool xtb_os_delete_directory(XTB_String8 filepath)
{
    XTB_Temp_Arena scratch = xtb_scratch_begin_no_conflicts();
    filepath = xtb_str8_push_copy(scratch.arena, filepath);
    bool success = nftw(filepath.str, unlink_cb, 64, FTW_DEPTH | FTW_PHYS) == 0;
    xtb_scratch_end(scratch);
    return success;
}

static bool should_skip_file_in_listing(XTB_String8 filepath, XTB_Directory_Listing_Flags flags)
{
    if (!(flags & XTB_DIR_LIST_CURR) && xtb_str8_eq_lit(filepath, ".")) return true;;
    if (!(flags & XTB_DIR_LIST_PREV) && xtb_str8_eq_lit(filepath, "..")) return true;
    return false;
}

XTB_File_Type dirent_ft_to_xtb_ft(int ft)
{
    switch (ft)
    {
        case DT_REG:  return XTB_FT_REGULAR;
        case DT_DIR:  return XTB_FT_DIRECTORY;
        case DT_LNK:  return XTB_FT_SYMLINK;
        case DT_CHR:  return XTB_FT_CHAR_DEVICE;
        case DT_BLK:  return XTB_FT_BLOCK_DEVICE;
        case DT_FIFO: return XTB_FT_FIFO;
        case DT_SOCK: return XTB_FT_SOCKET;
        default:      return XTB_FT_UNKNOWN;
    }
}

XTB_Directory_List xtb_os_list_directory_custom(Allocator* allocator, XTB_String8 filepath, XTB_Directory_Listing_Flags flags)
{
    XTB_Temp_Arena scratch = xtb_scratch_begin_conflict(allocator);
    filepath = xtb_str8_push_copy(scratch.arena, filepath);
    DIR *dir = opendir(filepath.str);
    xtb_scratch_end(scratch);

    XTB_Directory_List list = {0};

    if (dir == NULL)
    {
        perror("opendir failed");
        return list;
    }

    struct dirent *entry;
    while ((entry = readdir(dir)))
    {
        XTB_String8 entry_str = xtb_str8_cstring(entry->d_name);

        if (should_skip_file_in_listing(entry_str, flags)) continue;

        XTB_String8 path_parts[] = { filepath, entry_str };

        XTB_Directory_Listing_Node *node = XTB_Allocate(allocator, XTB_Directory_Listing_Node);
        node->type = dirent_ft_to_xtb_ft(entry->d_type);
        node->path = xtb_os_path_join(allocator, path_parts, XTB_ArrLen(path_parts));
        DLLPushBack(list.head, list.tail, node);
    }

    closedir(dir);
    return list;
}

XTB_Directory_List xtb_os_list_directory(Allocator* allocator, XTB_String8 filepath)
{
    return xtb_os_list_directory_custom(allocator, filepath, XTB_DIR_LIST_NONE);
}

XTB_Directory_List xtb_os_list_directory_recursively(Allocator* allocator, XTB_String8 filepath)
{
    XTB_Directory_List entries = xtb_os_list_directory(allocator, filepath);
    XTB_Directory_List accumulator = entries;

    XTB_IterateList(entries, XTB_Directory_Listing_Node, entry)
    {
        if (entry->type == XTB_FT_DIRECTORY)
        {
            XTB_Directory_List children =
                xtb_os_list_directory_recursively(allocator, entry->path);

            if (children.head != NULL)
            {
                DLLConcat(accumulator, children);
            }
        }
    }

    return accumulator;
}
