#include "os.h"
#include "xtb_core/core.h"
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

XTB_File_Handle *xtb_os_open_file(const char *filepath, XTB_File_Mode mode)
{
    return (XTB_File_Handle*)fopen(filepath, xtb_file_mode_to_stdio_mode(mode));
}

void xtb_os_close_file(XTB_File_Handle *handle)
{
    fclose((FILE*)handle);
}

size_t xtb_os_read_file(XTB_File_Handle *handle, char *buffer, size_t size)
{
    FILE *thandle = (FILE*)handle;
    return fread(buffer, sizeof(char), size, thandle);
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

char *xtb_os_read_entire_file(const char *filepath, size_t *out_size)
{
    XTB_File_Handle *handle = xtb_os_open_file(filepath, XTB_READ | XTB_BINARY);
    if (handle == NULL) return NULL;

    size_t file_size = xtb_os_get_file_size(handle);
    char *buffer = (char*)malloc(file_size);

    size_t bytes_read = xtb_os_read_file(handle, buffer, file_size);
    xtb_os_close_file(handle);

    if (bytes_read == file_size)
    {
        if (out_size != NULL)
        {
            *out_size = file_size;
        }
        return buffer;
    }
    else
    {
        free(buffer);
        return NULL;
    }
}

