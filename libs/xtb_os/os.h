#ifndef _XTB_OS_H_
#define _XTB_OS_H_

#include <xtb_core/core.h>
#include <stddef.h>
#include <stdbool.h>

typedef struct XTB_File_Handle XTB_File_Handle;

typedef enum XTB_File_Mode
{
    XTB_READ = 0b001,
    XTB_WRITE = 0b010,
    XTB_BINARY = 0b100
} XTB_File_Mode;

typedef enum XTB_File_Type
{
    XTB_FT_REGULAR = 0,
    XTB_FT_DIRECTORY,
    XTB_FT_SYMLINK,
    XTB_FT_UNKNOWN
} XTB_File_Type;

typedef enum XTB_Graph_Traversal_type
{
    XTB_BFS = 0,
    XTB_DFS
} XTB_Graph_Traversal_Type;

XTB_File_Handle *xtb_os_open_file(const char *filepath, XTB_File_Mode mode);
void xtb_os_close_file(XTB_File_Handle *handle);

size_t xtb_os_get_file_size(XTB_File_Handle *handle);

size_t xtb_os_read_file(XTB_File_Handle *handle, char *buffer, size_t size);
char *xtb_os_read_entire_file(const char *filepath, size_t *out_size);

size_t xtb_os_write_file(XTB_File_Handle *handle, const char *buffer, size_t size);
size_t xtb_os_write_entire_file(const char *filepath, const char *buffer, size_t size);

bool xtb_os_file_exists(const char *filepath);
bool xtb_os_delete_file(const char *filepath);
bool xtb_os_delete_directory(const char *filepath);
bool xtb_os_move_file(const char *old_path, const char *new_path);

bool xtb_os_file_has_read_permission(const char *filepath);
bool xtb_os_file_has_write_permission(const char *filepath);
bool xtb_os_file_has_execute_permission(const char *filepath);

bool xtb_os_is_regular_file(const char *filepath);
bool xtb_os_is_directory(const char *filepath);

bool xtb_os_is_regular_file_nofollow(const char *filepath);
bool xtb_os_is_directory_nofollow(const char *filepath);
bool xtb_os_is_symbolic_link(const char *filepath);

XTB_File_Type xtb_os_get_file_type_nofollow(const char *filepath);
XTB_File_Type xtb_os_get_file_type(const char *filepath);

char *xtb_os_real_path(const char *filepath);

typedef struct XTB_Directory_Listing_Node {
    char value[256];
    struct XTB_Directory_Listing_Node* prev;
    struct XTB_Directory_Listing_Node* next;
} XTB_Directory_Listing_Node;

typedef enum XTB_Directory_Listing_Flags
{
    XTB_DIR_LIST_NONE          = 0b000,
    XTB_DIR_LIST_CURR          = 0b001,
    XTB_DIR_LIST_PREV          = 0b010,
    XTB_DIR_LIST_CURR_AND_PREV = 0b011,
} XTB_Directory_Listing_Flags;

XTB_Directory_Listing_Node* xtb_os_iterate_directory_custom(XTB_Allocator allocator, const char *filepath, XTB_Directory_Listing_Flags flags);
XTB_Directory_Listing_Node* xtb_os_iterate_directory(XTB_Allocator allocator, const char *filepath);
XTB_Directory_Listing_Node* xtb_os_iterate_directory_recursively(XTB_Allocator allocator, const char *filepath, XTB_Graph_Traversal_Type traversal_type);

#endif // _XTB_OS_H_
