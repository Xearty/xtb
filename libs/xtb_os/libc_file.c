#include "os.h"
#include "xtb_allocator/malloc.h"
#include "xtb_core/core.h"
#include "xtb_core/str.h"
#include <stdio.h>
#include <stdlib.h>

static const char *xtb_file_mode_to_stdio_mode(XTB_File_Mode mode)
{
    if (mode & XTB_BINARY)
    {
        if (mode & XTB_READ) return "rb";
        if (mode & XTB_WRITE) return "wb";
    }
    else
    {
        if (mode & XTB_READ) return "r";
        if (mode & XTB_WRITE) return "w";
    }

    XTB_UNREACHABLE;
    return NULL;
}

XTB_File_Handle *xtb_os_open_file(XTB_String8 filepath, XTB_File_Mode mode)
{
    return (XTB_File_Handle*)fopen(filepath.str, xtb_file_mode_to_stdio_mode(mode));
}

void xtb_os_close_file(XTB_File_Handle *handle)
{
    fclose((FILE*)handle);
}

size_t xtb_os_read_file(XTB_File_Handle *handle, const XTB_Byte *buffer, size_t size)
{
    FILE *thandle = (FILE*)handle;
    return fread((char*)buffer, sizeof(char), size, thandle);
}

size_t xtb_os_get_file_size(XTB_File_Handle *handle)
{
    FILE *thandle = (FILE *)handle;

    size_t offset = ftell(thandle);

    fseek(thandle, 0, SEEK_END);
    size_t size = ftell(thandle);

    fseek(thandle, offset, SEEK_SET);
    return size;
}

XTB_String8 xtb_os_read_entire_file(XTB_String8 filepath)
{
    XTB_File_Handle *handle = xtb_os_open_file(filepath, XTB_READ | XTB_BINARY);
    if (handle == NULL) return xtb_str8_invalid;

    size_t file_size = xtb_os_get_file_size(handle);
    char *buffer = (char*)malloc(file_size);

    size_t bytes_read = xtb_os_read_file(handle, (XTB_Byte*)buffer, file_size);
    xtb_os_close_file(handle);

    if (bytes_read == file_size)
    {
        return xtb_str8(buffer, file_size);
    }
    else
    {
        free(buffer);
        return xtb_str8_invalid;
    }
}

size_t xtb_os_write_file(XTB_File_Handle *handle, const XTB_Byte *buffer, size_t size)
{
    return fwrite(buffer, sizeof(char), size, (FILE*)handle);
}

size_t xtb_os_write_entire_file(XTB_String8 filepath, const XTB_Byte *buffer, size_t size)
{
    XTB_File_Handle *handle = xtb_os_open_file(filepath, XTB_WRITE | XTB_BINARY);
    if (handle == NULL) return 0;

    size_t bytes_written = xtb_os_write_file(handle, buffer, size);
    xtb_os_close_file(handle);

    return bytes_written;
}

bool xtb_os_delete_file(XTB_String8 filepath)
{
    return remove(filepath.str) == 0;
}

bool xtb_os_move_file(XTB_String8 old_path, XTB_String8 new_path)
{
    return rename(old_path.str, new_path.str) == 0;
}

bool xtb_os_copy_file(XTB_String8 filepath, XTB_String8 new_path)
{
    XTB_String8 content = xtb_os_read_entire_file(filepath);
    if (xtb_str8_is_invalid(content)) return false;

    bool succ = xtb_os_write_entire_file(new_path, (XTB_Byte*)content.str, content.len);

    xtb_str8_free(xtb_malloc_allocator(), content);
    return succ;
}

XTB_String8 xtb_os_real_path(XTB_String8 filepath)
{
    return xtb_str8_cstring(realpath(filepath.str, NULL));
}

