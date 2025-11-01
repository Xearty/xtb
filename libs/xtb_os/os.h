#ifndef _XTB_OS_H_
#define _XTB_OS_H_

#include <stddef.h>
#include <stdbool.h>

typedef struct XTB_File_Handle XTB_File_Handle;

typedef enum XTB_File_Mode
{
    XTB_READ = 0b001,
    XTB_WRITE = 0b010,
    XTB_BINARY = 0b100
} XTB_File_Mode;

XTB_File_Handle *xtb_os_open_file(const char *filepath, XTB_File_Mode mode);
void xtb_os_close_file(XTB_File_Handle *handle);

size_t xtb_os_get_file_size(XTB_File_Handle *handle);

size_t xtb_os_read_file(XTB_File_Handle *handle, char *buffer, size_t size);
char *xtb_os_read_entire_file(const char *filepath, size_t *out_size);

size_t xtb_os_write_file(XTB_File_Handle *handle, const char *buffer, size_t size);
size_t xtb_os_write_entire_file(const char *filepath, const char *buffer, size_t size);

bool xtb_os_file_exists(const char *filepath);
bool xtb_os_delete_file(const char *filepath);

bool xtb_os_file_has_read_permission(const char *filepath);
bool xtb_os_file_has_write_permission(const char *filepath);
bool xtb_os_file_has_execute_permission(const char *filepath);

bool xtb_os_is_regular_file(const char *filepath);
bool xtb_os_is_directory(const char *filepath);

bool xtb_os_is_regular_file_nofollow(const char *filepath);
bool xtb_os_is_directory_nofollow(const char *filepath);
bool xtb_os_is_symbolic_link(const char *filepath);

#endif // _XTB_OS_H_
