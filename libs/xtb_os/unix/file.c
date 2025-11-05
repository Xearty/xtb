#include "xtb_core/str.h"
#define _XOPEN_SOURCE 500
#define __USE_XOPEN_EXTENDED
#include <xtb_os/os.h>
#include <xtb_core/linked_list.h>

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

bool xtb_os_file_exists(XTB_String8 filepath)
{
    xtb_str8_assert_null_terminated(filepath);
    return access(filepath.str, F_OK) == 0;
}

bool xtb_os_file_has_read_permission(XTB_String8 filepath)
{
    xtb_str8_assert_null_terminated(filepath);
    return access(filepath.str, R_OK) == 0;
}

bool xtb_os_file_has_write_permission(XTB_String8 filepath)
{
    xtb_str8_assert_null_terminated(filepath);
    return access(filepath.str, W_OK) == 0;
}

bool xtb_os_file_has_execute_permission(XTB_String8 filepath)
{
    xtb_str8_assert_null_terminated(filepath);
    return access(filepath.str, X_OK) == 0;
}

bool xtb_os_is_regular_file(XTB_String8 filepath)
{
    xtb_str8_assert_null_terminated(filepath);
    struct stat path_stat;
    if (stat(filepath.str, &path_stat) != 0) return false;
    return S_ISREG(path_stat.st_mode);
}

bool xtb_os_is_directory(XTB_String8 filepath)
{
    xtb_str8_assert_null_terminated(filepath);
    struct stat path_stat;
    if (stat(filepath.str, &path_stat) != 0) return false;
    return S_ISDIR(path_stat.st_mode);
}

bool xtb_os_is_regular_file_nofollow(XTB_String8 filepath)
{
    xtb_str8_assert_null_terminated(filepath);
    struct stat path_stat;
    if (lstat(filepath.str, &path_stat) != 0) return false;
    return S_ISREG(path_stat.st_mode);
}

bool xtb_os_is_directory_nofollow(XTB_String8 filepath)
{
    xtb_str8_assert_null_terminated(filepath);
    struct stat path_stat;
    if (lstat(filepath.str, &path_stat) != 0) return false;
    return S_ISDIR(path_stat.st_mode);
}

bool xtb_os_is_symbolic_link(XTB_String8 filepath)
{
    xtb_str8_assert_null_terminated(filepath);
    struct stat path_stat;
    if (lstat(filepath.str, &path_stat) != 0) return false;
    return S_ISLNK(path_stat.st_mode);
}

XTB_File_Type xtb_os_get_file_type_nofollow(XTB_String8 filepath)
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

XTB_File_Type xtb_os_get_file_type(XTB_String8 filepath)
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

bool xtb_os_delete_directory(XTB_String8 filepath)
{
    xtb_str8_assert_null_terminated(filepath);
    return nftw(filepath.str, unlink_cb, 64, FTW_DEPTH | FTW_PHYS) == 0;
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
        case DT_REG: return XTB_FT_REGULAR;
        case DT_DIR: return XTB_FT_DIRECTORY;
        case DT_LNK: return XTB_FT_SYMLINK;
        default: return XTB_FT_UNKNOWN;
    }
}

XTB_Directory_List xtb_os_list_directory_custom(XTB_Allocator allocator, XTB_String8 filepath, XTB_Directory_Listing_Flags flags)
{
    xtb_str8_assert_null_terminated(filepath);
    XTB_Directory_List list = {0};

    DIR *dir = opendir(filepath.str);
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

        XTB_Directory_Listing_Node *node = XTB_AllocateZero(allocator, XTB_Directory_Listing_Node);
        node->type = dirent_ft_to_xtb_ft(entry->d_type);
        node->path = xtb_os_path_join(allocator, path_parts, XTB_ArrLen(path_parts));
        xtb_str8_debug(node->path);
        DLLPushBack(list.head, list.tail, node);
    }

    closedir(dir);
    return list;
}

XTB_Directory_List xtb_os_list_directory(XTB_Allocator allocator, XTB_String8 filepath)
{
    return xtb_os_list_directory_custom(allocator, filepath, XTB_DIR_LIST_NONE);
}

XTB_Directory_List xtb_os_list_directory_recursively(XTB_Allocator allocator, XTB_String8 filepath)
{
    XTB_Directory_List entries = xtb_os_list_directory(allocator, filepath);
    XTB_Directory_List accumulator = entries;

    for (XTB_Directory_Listing_Node *entry = entries.head;
         DLLIterBoundedCond(entry, entries.tail);
         entry = entry->next)
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

void xtb_os_free_directory_list(XTB_Allocator allocator, XTB_Directory_List *list)
{
    XTB_Directory_Listing_Node *head = list->head;

    while (head != NULL)
    {
        XTB_Directory_Listing_Node *next = head->next;
        xtb_str8_free(allocator, head->path);
        XTB_Deallocate(allocator, head);
        head = next;
    }
}

