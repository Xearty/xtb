#include "xtb_core/string.h"
#ifndef _XOPEN_SOURCE
#define _XOPEN_SOURCE 500
#endif
#ifndef __USE_XOPEN_EXTENDED
#define __USE_XOPEN_EXTENDED
#endif
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

namespace xtb::os
{
static bool access_helper(String filepath, int check_value)
{
    ScratchScope scratch;
    filepath = filepath.copy(&scratch->allocator);
    return access((char*)filepath.data(), check_value) == 0;
}

bool file_exists(String filepath)
{
    return access_helper(filepath, F_OK);
}

bool create_directory(String path)
{
    ScratchScope scratch;
    path = path.copy(&scratch->allocator);

    i32 state = 0;
    if (!file_exists(path))
    {
        state = mkdir((const char *)path.data(), 0700);
    }
    return state == 0;
}

bool file_has_read_permission(String filepath)
{
    return access_helper(filepath, R_OK);
}

bool file_has_write_permission(String filepath)
{
    return access_helper(filepath, W_OK);
}

bool file_has_execute_permission(String filepath)
{
    return access_helper(filepath, X_OK);
}

bool file_is_regular(String filepath)
{
    return get_file_type(filepath) == FileType::Regular;
}

bool file_is_directory(String filepath)
{
    return get_file_type(filepath) == FileType::Directory;
}

bool file_is_regular_nofollow(String filepath)
{
    return get_file_type_nofollow(filepath) == FileType::Regular;
}

bool file_is_directory_nofollow(String filepath)
{
    return get_file_type_nofollow(filepath) == FileType::Directory;
}

bool file_is_symbolic_link(String filepath)
{
    return get_file_type_nofollow(filepath) == FileType::Symlink;
}

FileType get_file_type(String filepath)
{
    ScratchScope scratch;
    filepath = filepath.copy(&scratch->allocator);

    struct stat st;
    int state = stat((char*)filepath.data(), &st);

    if (state != 0) return FileType::Unknown;

    switch (st.st_mode & S_IFMT)
    {
        case S_IFREG:  return FileType::Regular;
        case S_IFDIR:  return FileType::Directory;
        case S_IFLNK:  return FileType::Symlink;
        case S_IFCHR:  return FileType::CharDevice;
        case S_IFBLK:  return FileType::BlockDevice;
        case S_IFIFO:  return FileType::Fifo;
        case S_IFSOCK: return FileType::Socket;
        default:       return FileType::Unknown;
    }
}

FileType get_file_type_nofollow(String filepath)
{
    ScratchScope scratch;
    filepath = filepath.copy(&scratch->allocator);

    struct stat st;
    int state = lstat((char*)filepath.data(), &st);

    if (state != 0) return FileType::Unknown;

    switch (st.st_mode & S_IFMT)
    {
        case S_IFREG:  return FileType::Regular;
        case S_IFDIR:  return FileType::Directory;
        case S_IFLNK:  return FileType::Symlink;
        case S_IFCHR:  return FileType::CharDevice;
        case S_IFBLK:  return FileType::BlockDevice;
        case S_IFIFO:  return FileType::Fifo;
        case S_IFSOCK: return FileType::Socket;
        default:       return FileType::Unknown;
    }
}

static int unlink_cb(const char *filepath, const struct stat *sb, int typeflag, struct FTW *ftwbuf)
{
    return remove(filepath);
}

bool delete_directory(String filepath)
{
    ScratchScope scratch;
    filepath = filepath.copy(&scratch->allocator);
    return nftw((char*)filepath.data(), unlink_cb, 64, FTW_DEPTH | FTW_PHYS) == 0;
}

static bool should_skip_file_in_listing(String filepath, DirectoryListingFlags flags)
{
    if (!(flags & DirectoryListing::Current) && filepath == ".") return true;;
    if (!(flags & DirectoryListing::Previous) && filepath == "..") return true;
    return false;
}

FileType dirent_ft_to_ft(int ft)
{
    switch (ft)
    {
        case DT_REG:  return FileType::Regular;
        case DT_DIR:  return FileType::Directory;
        case DT_LNK:  return FileType::Symlink;
        case DT_CHR:  return FileType::CharDevice;
        case DT_BLK:  return FileType::BlockDevice;
        case DT_FIFO: return FileType::Fifo;
        case DT_SOCK: return FileType::Socket;
        default:      return FileType::Unknown;
    }
}

DirectoryList list_directory_custom(Allocator* allocator, String filepath, DirectoryListingFlags flags)
{
    ScratchScope scratch(allocator);
    String filepath_nt = filepath.copy(&scratch->allocator);

    DIR *dir = opendir((char*)filepath_nt.data());

    if (dir == NULL)
    {
        perror("opendir failed");
        return DirectoryList{};
    }

    defer (closedir(dir));

    DirectoryList list = {0};

    struct dirent *entry;
    while ((entry = readdir(dir)))
    {
        String entry_str = String::from_cstr(entry->d_name);

        if (should_skip_file_in_listing(entry_str, flags)) continue;

        String path_parts[] = { filepath, entry_str };

        DirectoryListingNode *node = allocate<DirectoryListingNode>(allocator);
        node->type = dirent_ft_to_ft(entry->d_type);
        node->path = path_join(allocator, path_parts, ArrLen(path_parts));
        DLLPushBack(list.head, list.tail, node);
    }

    return list;
}

DirectoryList list_directory(Allocator* allocator, String filepath)
{
    return list_directory_custom(allocator, filepath, DirectoryListing::None);
}

DirectoryList list_directory_recursively(Allocator* allocator, String filepath)
{
    DirectoryList entries = list_directory(allocator, filepath);
    DirectoryList accumulator = entries;

    IterateList(&entries)
    {
        if (it->type == FileType::Directory)
        {
            DirectoryList children =
                list_directory_recursively(allocator, it->path);

            if (children.head != NULL)
            {
                DLLConcat(accumulator, children);
            }
        }
    }

    return accumulator;
}
}
