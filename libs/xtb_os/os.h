#ifndef _XTB_OS_H_
#define _XTB_OS_H_

#include <xtb_core/core.h>
#include <xtb_core/str.h>
#include <stddef.h>
#include <stdbool.h>

XTB_C_LINKAGE_BEGIN

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
    XTB_FT_SYMLINK,
    XTB_FT_CHAR_DEVICE,
    XTB_FT_BLOCK_DEVICE,
    XTB_FT_FIFO,
    XTB_FT_SOCKET,
} XTB_File_Type;

XTB_File_Handle *xtb_os_open_file(XTB_String8 filepath, XTB_File_Mode mode);
void xtb_os_close_file(XTB_File_Handle *handle);

size_t xtb_os_get_file_size(XTB_File_Handle *handle);

size_t xtb_os_read_file(XTB_File_Handle *handle, const XTB_Byte *buffer, size_t size);
XTB_String8 xtb_os_read_entire_file(Allocator *allcoator, XTB_String8 filepath);

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

bool xtb_os_file_is_regular(XTB_String8 filepath);
bool xtb_os_file_is_directory(XTB_String8 filepath);

bool xtb_os_file_is_regular_nofollow(XTB_String8 filepath);
bool xtb_os_file_is_directory_nofollow(XTB_String8 filepath);
bool xtb_os_file_is_symbolic_link(XTB_String8 filepath);

XTB_File_Type xtb_os_get_file_type_nofollow(XTB_String8 filepath);
XTB_File_Type xtb_os_get_file_type(XTB_String8 filepath);

XTB_String8 xtb_os_real_path(Allocator* allocator, XTB_String8 filepath);

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

XTB_Directory_List xtb_os_list_directory_custom(Allocator* allocator, XTB_String8 filepath, XTB_Directory_Listing_Flags flags);
XTB_Directory_List xtb_os_list_directory(Allocator* allocator, XTB_String8 filepath);
XTB_Directory_List xtb_os_list_directory_recursively(Allocator* allocator, XTB_String8 filepath);

XTB_String8 xtb_os_path_join(Allocator* allocator, XTB_String8 *parts, size_t count);

#ifdef XTB_OS_SHORTHANDS
typedef XTB_File_Handle File_Handle;
typedef XTB_File_Mode   File_Mode;
typedef XTB_File_Type   File_Type;

#define os_open_file                   xtb_os_open_file
#define os_close_file                  xtb_os_close_file
#define os_get_file_size               xtb_os_get_file_size
#define os_read_file                   xtb_os_read_file
#define os_read_entire_file            xtb_os_read_entire_file
#define os_write_file                  xtb_os_write_file
#define os_write_entire_file           xtb_os_write_entire_file
#define os_file_exists                 xtb_os_file_exists
#define os_delete_file                 xtb_os_delete_file
#define os_delete_directory            xtb_os_delete_directory
#define os_move_file                   xtb_os_move_file
#define os_copy_file                   xtb_os_copy_file
#define os_file_has_read_permission    xtb_os_file_has_read_permission
#define os_file_has_write_permission   xtb_os_file_has_write_permission
#define os_file_has_execute_permission xtb_os_file_has_execute_permission
#define os_file_is_regular             xtb_os_file_is_regular
#define os_file_is_directory           xtb_os_file_is_directory
#define os_file_is_regular_nofollow    xtb_os_file_is_regular_nofollow
#define os_file_is_directory_nofollow  xtb_os_file_is_directory_nofollow
#define os_file_is_symbolic_link       xtb_os_file_is_symbolic_link
#define os_get_file_type_nofollow      xtb_os_get_file_type_nofollow
#define os_get_file_type               xtb_os_get_file_type
#define os_real_path                   xtb_os_real_path
#define os_list_directory_custom       xtb_os_list_directory_custom
#define os_list_directory              xtb_os_list_directory
#define os_list_directory_recursively  xtb_os_list_directory_recursively
#define os_path_join                   xtb_os_path_join
#endif

XTB_C_LINKAGE_END

#endif // _XTB_OS_H_
