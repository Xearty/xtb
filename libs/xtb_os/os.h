#ifndef _XTB_OS_H_
#define _XTB_OS_H_

#include <xtb_core/core.h>
#include <xtb_str/str.h>
#include <stddef.h>
#include <stdbool.h>

#define XTB_FILE_NAME_BUFFER_SIZE 256

typedef struct XTB_File_Handle XTB_File_Handle;

typedef enum XTB_File_Mode
{
    XTB_READ = 0b001,
    XTB_WRITE = 0b010,
    XTB_BINARY = 0b100
} XTB_File_Mode;

typedef enum XTB_File_Type
{
    XTB_FT_UNKNOWN = 0,
    XTB_FT_REGULAR,
    XTB_FT_DIRECTORY,
    XTB_FT_SYMLINK
} XTB_File_Type;

XTB_File_Handle *xtb_os_open_file(XTB_String8 filepath, XTB_File_Mode mode);
void xtb_os_close_file(XTB_File_Handle *handle);

size_t xtb_os_get_file_size(XTB_File_Handle *handle);

size_t xtb_os_read_file(XTB_File_Handle *handle, const XTB_Byte *buffer, size_t size);
XTB_String8 xtb_os_read_entire_file(XTB_String8 filepath);

size_t xtb_os_write_file(XTB_File_Handle *handle, const XTB_Byte *buffer, size_t size);
size_t xtb_os_write_entire_file(XTB_String8 filepath, const XTB_Byte *buffer, size_t size);

bool xtb_os_file_exists(XTB_String8 filepath);
bool xtb_os_delete_file(XTB_String8 filepath);
bool xtb_os_delete_directory(XTB_String8 filepath);
bool xtb_os_move_file(XTB_String8 old_path, XTB_String8 new_path);
bool xtb_os_copy_file(XTB_String8 filepath, XTB_String8 new_path);

bool xtb_os_file_has_read_permission(XTB_String8 filepath);
bool xtb_os_file_has_write_permission(XTB_String8 filepath);
bool xtb_os_file_has_execute_permission(XTB_String8 filepath);

bool xtb_os_is_regular_file(XTB_String8 filepath);
bool xtb_os_is_directory(XTB_String8 filepath);

bool xtb_os_is_regular_file_nofollow(XTB_String8 filepath);
bool xtb_os_is_directory_nofollow(XTB_String8 filepath);
bool xtb_os_is_symbolic_link(XTB_String8 filepath);

XTB_File_Type xtb_os_get_file_type_nofollow(XTB_String8 filepath);
XTB_File_Type xtb_os_get_file_type(XTB_String8 filepath);

XTB_String8 xtb_os_real_path(XTB_String8 filepath);

typedef struct XTB_Directory_Listing_Node {
    XTB_File_Type type;;
    XTB_String8 path;
    struct XTB_Directory_Listing_Node* prev;
    struct XTB_Directory_Listing_Node* next;
} XTB_Directory_Listing_Node;

typedef struct XTB_Directory_List
{
    XTB_Directory_Listing_Node *head;
    XTB_Directory_Listing_Node *tail;
} XTB_Directory_List;

typedef enum XTB_Directory_Listing_Flags
{
    XTB_DIR_LIST_NONE          = 0b000,
    XTB_DIR_LIST_CURR          = 0b001,
    XTB_DIR_LIST_PREV          = 0b010,
    XTB_DIR_LIST_CURR_AND_PREV = 0b011,
} XTB_Directory_Listing_Flags;

XTB_Directory_List xtb_os_list_directory_custom(XTB_Allocator allocator, XTB_String8 filepath, XTB_Directory_Listing_Flags flags);
XTB_Directory_List xtb_os_list_directory(XTB_Allocator allocator, XTB_String8 filepath);
XTB_Directory_List xtb_os_list_directory_recursively(XTB_Allocator allocator, XTB_String8 filepath);
void xtb_os_free_directory_list(XTB_Allocator allocator, XTB_Directory_List *list);

#endif // _XTB_OS_H_
