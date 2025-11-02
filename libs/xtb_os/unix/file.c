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

#define __USE_MISC
#include <dirent.h>

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

static bool should_skip_file_in_listing(const char *filepath, XTB_Directory_Listing_Flags flags)
{
    if (!(flags & XTB_DIR_LIST_CURR))
    {
        if (strncmp(filepath, ".", 256) == 0)
        {
            return true;;
        }
    }

    if (!(flags & XTB_DIR_LIST_PREV))
    {
        if (strncmp(filepath, "..", 256) == 0)
        {
            return true;
        }
    }

    return false;
}

XTB_Directory_Listing_Node* xtb_os_iterate_directory_custom(XTB_Allocator allocator, const char *filepath, XTB_Directory_Listing_Flags flags)
{
    DIR *dir = opendir(filepath);

    XTB_Directory_Listing_Node *begin = NULL;
    XTB_Directory_Listing_Node *end = NULL;

    struct dirent *entry;
    while ((entry = readdir(dir)))
    {
        if (should_skip_file_in_listing(entry->d_name, flags)) continue;

        XTB_Directory_Listing_Node *node = XTB_Allocate(allocator, XTB_Directory_Listing_Node);
        strncpy(node->path, entry->d_name, sizeof(node->path));

        switch (entry->d_type)
        {
            case DT_REG: node->type = XTB_FT_REGULAR; break;
            case DT_DIR: node->type = XTB_FT_DIRECTORY; break;
            case DT_LNK: node->type = XTB_FT_SYMLINK; break;
            default: node->type = XTB_FT_UNKNOWN; break;
        }

        DLLPushBack(begin, end, node);
    }

    closedir(dir);

    return begin;
}

XTB_Directory_Listing_Node* xtb_os_iterate_directory(XTB_Allocator allocator, const char *filepath)
{
    return xtb_os_iterate_directory_custom(allocator, filepath, XTB_DIR_LIST_NONE);
}

XTB_Directory_Listing_Node* xtb_os_iterate_directory_recursively(XTB_Allocator allocator, const char *filepath, XTB_Graph_Traversal_Type traversal_type)
{
    return NULL;
}

