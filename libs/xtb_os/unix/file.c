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
        if (strncmp(filepath, ".", XTB_FILE_NAME_BUFFER_SIZE - 1) == 0)
        {
            return true;;
        }
    }

    if (!(flags & XTB_DIR_LIST_PREV))
    {
        if (strncmp(filepath, "..", XTB_FILE_NAME_BUFFER_SIZE - 1) == 0)
        {
            return true;
        }
    }

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

XTB_Directory_List xtb_os_list_directory_custom(XTB_Allocator allocator, const char *filepath, XTB_Directory_Listing_Flags flags)
{
    XTB_Directory_List list = {0};

    DIR *dir = opendir(filepath);
    if (dir == NULL)
    {
        perror("opendir failed");
        return list;
    }

    size_t dir_path_len = strlen(filepath);

    struct dirent *entry;
    while ((entry = readdir(dir)))
    {
        if (should_skip_file_in_listing(entry->d_name, flags)) continue;

        XTB_Directory_Listing_Node *node = XTB_Allocate(allocator, XTB_Directory_Listing_Node);

        size_t filename_len = strlen(entry->d_name);
        size_t child_path_len = dir_path_len + 1 + filename_len + 1;

        node->type = dirent_ft_to_xtb_ft(entry->d_type);
        node->path = XTB_AllocateArray(allocator, char, child_path_len);

        // Copy directory path
        strncpy(node->path, filepath, dir_path_len);

        // Append a slash to the directory path
        if (node->path[dir_path_len - 1] != '/')
        {
            node->path[dir_path_len] = '/';
            node->path[dir_path_len + 1] = '\0';
        }

        // Append the file name to the directory path
        strncat(node->path, entry->d_name, filename_len);

        DLLPushBack(list.head, list.tail, node);
    }

    closedir(dir);
    return list;
}

XTB_Directory_List xtb_os_list_directory(XTB_Allocator allocator, const char *filepath)
{
    return xtb_os_list_directory_custom(allocator, filepath, XTB_DIR_LIST_NONE);
}

XTB_Directory_List xtb_os_list_directory_recursively(XTB_Allocator allocator, const char *filepath)
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
        XTB_Deallocate(allocator, head->path);
        XTB_Deallocate(allocator, head);
        head = next;
    }
}

