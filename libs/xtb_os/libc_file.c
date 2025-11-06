#include "os.h"
#include "xtb_allocator/malloc.h"
#include "xtb_core/core.h"
#include "xtb_core/str.h"
#include <xtb_core/str_buffer.h>
#include <xtb_core/thread_context.h>
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
    XTB_Temp_Arena scratch = xtb_scratch_begin_no_conflicts();
    filepath = xtb_str8_push_copy(scratch.arena, filepath);
    XTB_File_Handle *handle = (XTB_File_Handle*)fopen(filepath.str, xtb_file_mode_to_stdio_mode(mode));
    xtb_scratch_end(scratch);
    return handle;
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
    XTB_Temp_Arena scratch = xtb_scratch_begin_no_conflicts();
    filepath = xtb_str8_push_copy(scratch.arena, filepath);
    bool result = remove(filepath.str) == 0;
    xtb_scratch_end(scratch);
    return result;
}

bool xtb_os_move_file(XTB_String8 old_path, XTB_String8 new_path)
{
    XTB_Temp_Arena scratch = xtb_scratch_begin_no_conflicts();
    old_path = xtb_str8_push_copy(scratch.arena, old_path);
    new_path = xtb_str8_push_copy(scratch.arena, new_path);
    xtb_scratch_end(scratch);
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

XTB_String8 xtb_os_real_path(XTB_Allocator allocator, XTB_String8 filepath)
{
    XTB_Temp_Arena scratch = xtb_scratch_begin_no_conflicts();
    filepath = xtb_str8_push_copy(scratch.arena, filepath);
    char *realpath_result = realpath(filepath.str, NULL);
    xtb_scratch_end(scratch);

    XTB_String8 copy = xtb_str8_cstring_copy(allocator, realpath_result);
    free(realpath_result);

    return copy;
}

XTB_String8 xtb_os_path_join(XTB_Allocator allocator, XTB_String8 *parts, size_t count)
{
    XTB_Temp_Arena scratch = xtb_scratch_begin_conflict(allocator);
    XTB_Allocator scratch_allocator = xtb_arena_allocator(scratch.arena);

    XTB_String8_Buffer str_buffer = xtb_str8_buffer_new(scratch_allocator, 0);

    for (size_t i = 0; i < count; ++i)
    {
        XTB_String8 str = parts[i];

        if (xtb_str8_back(str) == '/')
        {
            str = xtb_str8_trunc_right(str, 1);
        }

        xtb_str8_buffer_push_back(&str_buffer, str);

        if (i != count - 1)
        {
            xtb_str8_buffer_push_back_lit(&str_buffer, "/");
        }
    }

    XTB_String8 path = xtb_str8_buffer_view_copy(allocator, &str_buffer);
    xtb_scratch_end(scratch);

    return path;
}

