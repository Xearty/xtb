#ifndef _XTB_OS_H_
#define _XTB_OS_H_

#include <xtb_core/core.h>
#include <xtb_core/str.h>
#include <stddef.h>
#include <stdbool.h>

C_LINKAGE_BEGIN

#define XTB_FILE_NAME_BUFFER_SIZE 256

typedef struct FileHandle FileHandle;

typedef enum FileMode
{
    FM_READ = 0b001,
    FM_WRITE = 0b010,
    FM_BINARY = 0b100
} FileMode;

typedef enum FileType
{
    FT_UNKNOWN = 0,
    FT_REGULAR,
    FT_DIRECTORY,
    FT_SYMLINK,
    FT_CHAR_DEVICE,
    FT_BLOCK_DEVICE,
    FT_FIFO,
    FT_SOCKET,
} FileType;

FileHandle *os_open_file(String filepath, FileMode mode);
void os_close_file(FileHandle *handle);

size_t os_get_file_size(FileHandle *handle);

size_t os_read_file(FileHandle *handle, const u8 *buffer, size_t size);
String os_read_entire_file(Allocator *allcoator, String filepath);

size_t os_write_file(FileHandle *handle, const u8 *buffer, size_t size);
size_t os_write_entire_file(String filepath, const u8 *buffer, size_t size);

bool os_file_exists(String filepath);
bool os_delete_file(String filepath);
bool os_delete_directory(String filepath);
bool os_move_file(String old_path, String new_path);
bool os_copy_file(String filepath, String new_path);

bool os_file_has_read_permission(String filepath);
bool os_file_has_write_permission(String filepath);
bool os_file_has_execute_permission(String filepath);

bool os_file_is_regular(String filepath);
bool os_file_is_directory(String filepath);

bool os_file_is_regular_nofollow(String filepath);
bool os_file_is_directory_nofollow(String filepath);
bool os_file_is_symbolic_link(String filepath);

FileType os_get_file_type_nofollow(String filepath);
FileType os_get_file_type(String filepath);

String os_real_path(Allocator* allocator, String filepath);

typedef struct DirectoryListingNode {
    FileType type;;
    String path;
    struct DirectoryListingNode* prev;
    struct DirectoryListingNode* next;
} DirectoryListNode;

typedef struct DirectoryList
{
    DirectoryListNode *head;
    DirectoryListNode *tail;
} DirectoryList;

typedef enum DirectoryListingFlags
{
    DIR_LIST_NONE          = 0b000,
    DIR_LIST_CURR          = 0b001,
    DIR_LIST_PREV          = 0b010,
    DIR_LIST_CURR_AND_PREV = 0b011,
} DirectoryListFlags;

DirectoryList os_list_directory_custom(Allocator* allocator, String filepath, DirectoryListFlags flags);
DirectoryList os_list_directory(Allocator* allocator, String filepath);
DirectoryList os_list_directory_recursively(Allocator* allocator, String filepath);

String os_path_join(Allocator* allocator, String *parts, size_t count);

C_LINKAGE_END

#endif // _XTB_OS_H_
