#ifndef _XTB_OS_H_
#define _XTB_OS_H_

#include <xtb_core/core.h>
#include <xtb_core/string.h>
#include <stddef.h>

#define XTB_FILE_NAME_BUFFER_SIZE 256

namespace xtb::os
{

using FileHandle = struct FileHandle;

struct FileMode
{
    enum : Flags32
    {
        Read = 0b001,
        Write = 0b010,
        Binary = 0b100
    };
};

using FileModeFlags = Flags32;

enum class FileType
{
    Unknown = 0,
    Regular,
    Directory,
    Symlink,
    CharDevice,
    BlockDevice,
    Fifo,
    Socket,
};

FileHandle* open_file(String filepath, FileModeFlags mode);
void close_file(FileHandle* handle);

size_t get_file_size(FileHandle* handle);

size_t read_file(FileHandle* handle, const u8* buffer, size_t size);
String read_entire_file(Allocator* allcoator, String filepath);

size_t write_file(FileHandle* handle, const u8* buffer, size_t size);
size_t write_entire_file(String filepath, const u8* buffer, size_t size);

bool file_exists(String filepath);
bool create_directory(String path);
bool delete_file(String filepath);
bool delete_directory(String filepath);
bool move_file(String old_path, String new_path);
bool copy_file(String filepath, String new_path);

bool file_has_read_permission(String filepath);
bool file_has_write_permission(String filepath);
bool file_has_execute_permission(String filepath);

bool file_is_regular(String filepath);
bool file_is_directory(String filepath);

bool file_is_regular_nofollow(String filepath);
bool file_is_directory_nofollow(String filepath);
bool file_is_symbolic_link(String filepath);

FileType get_file_type_nofollow(String filepath);
FileType get_file_type(String filepath);

String real_path(Allocator* allocator, String filepath);

struct DirectoryListingNode {
    FileType type;;
    String path;
    struct DirectoryListingNode* prev;
    struct DirectoryListingNode* next;
};

struct DirectoryList
{
    DirectoryListingNode* head;
    DirectoryListingNode* tail;
};

struct DirectoryListing
{
    enum : Flags32
    {
        None               = 0b000,
        Current            = 0b001,
        Previous           = 0b010,
        CurrentAndPrevious = 0b011,
    };
};

using DirectoryListingFlags = Flags32;

DirectoryList list_directory_custom(Allocator* allocator, String filepath, DirectoryListingFlags flags);
DirectoryList list_directory(Allocator* allocator, String filepath);
DirectoryList list_directory_recursively(Allocator* allocator, String filepath);

String path_join(Allocator* allocator, String* parts, size_t count);
}

#endif // _XTB_OS_H_
