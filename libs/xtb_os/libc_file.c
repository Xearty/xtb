#include "os.h"
#include "xtb_core/core.h"
#include "xtb_core/str.h"
#include <xtb_core/str_buffer.h>
#include <xtb_core/thread_context.h>
#include <xtb_core/contract.h>
#include <stdio.h>
#include <stdlib.h>

static const char *file_mode_to_stdio_mode(FileMode mode)
{
    if (mode & FM_BINARY)
    {
        if (mode & FM_READ) return "rb";
        if (mode & FM_WRITE) return "wb";
    }
    else
    {
        if (mode & FM_READ) return "r";
        if (mode & FM_WRITE) return "w";
    }

    Unreachable;
}

FileHandle *os_open_file(String filepath, FileMode mode)
{
    TempArena scratch = scratch_begin_no_conflicts();
    filepath = str_push_copy(scratch.arena, filepath);
    FileHandle *handle = (FileHandle*)fopen((const char *)filepath.str, file_mode_to_stdio_mode(mode));
    scratch_end(scratch);
    return handle;
}

void os_close_file(FileHandle *handle)
{
    fclose((FILE*)handle);
}

size_t os_read_file(FileHandle *handle, const u8 *buffer, size_t size)
{
    FILE *thandle = (FILE*)handle;
    return fread((char*)buffer, sizeof(char), size, thandle);
}

size_t os_get_file_size(FileHandle *handle)
{
    FILE *thandle = (FILE *)handle;

    size_t offset = ftell(thandle);

    fseek(thandle, 0, SEEK_END);
    size_t size = ftell(thandle);

    fseek(thandle, offset, SEEK_SET);
    return size;
}

String os_read_entire_file(Allocator *allocator, String filepath)
{
    FileHandle *handle = os_open_file(filepath, FM_READ | FM_BINARY);
    if (handle == NULL) return str_invalid;

    size_t file_size = os_get_file_size(handle);
    u8 *buffer = AllocateBytes(allocator, file_size + 1);

    size_t bytes_read = os_read_file(handle, (u8*)buffer, file_size);
    os_close_file(handle);

    if (bytes_read == file_size)
    {
        buffer[bytes_read] = '\0';
        return str_from(buffer, file_size);
    }
    else
    {
        Deallocate(allocator, buffer);
        return str_invalid;
    }
}

size_t os_write_file(FileHandle *handle, const u8 *buffer, size_t size)
{
    return fwrite(buffer, sizeof(char), size, (FILE*)handle);
}

size_t os_write_entire_file(String filepath, const u8 *buffer, size_t size)
{
    FileHandle *handle = os_open_file(filepath, FM_WRITE | FM_BINARY);
    if (handle == NULL) return 0;

    size_t bytes_written = os_write_file(handle, buffer, size);
    os_close_file(handle);

    return bytes_written;
}

bool os_delete_file(String filepath)
{
    TempArena scratch = scratch_begin_no_conflicts();
    filepath = str_push_copy(scratch.arena, filepath);
    bool result = remove((const char *)filepath.str) == 0;
    scratch_end(scratch);
    return result;
}

bool os_move_file(String old_path, String new_path)
{
    TempArena scratch = scratch_begin_no_conflicts();
    old_path = str_push_copy(scratch.arena, old_path);
    new_path = str_push_copy(scratch.arena, new_path);
    scratch_end(scratch);
    return rename((const char *)old_path.str, (const char *)new_path.str) == 0;
}

bool os_copy_file(String filepath, String new_path)
{
    TempArena scratch = scratch_begin_no_conflicts();

    String content = os_read_entire_file(&scratch.arena->allocator, filepath);
    if (str_is_invalid(content))
    {
        scratch_end(scratch);
        return false;
    }

    bool succ = os_write_entire_file(new_path, (u8*)content.str, content.len);
    scratch_end(scratch);
    return succ;
}

String os_real_path(Allocator* allocator, String filepath)
{
    TempArena scratch = scratch_begin_no_conflicts();
    filepath = str_push_copy(scratch.arena, filepath);
    char *realpath_result = realpath(filepath.str, NULL);
    scratch_end(scratch);

    String copy = cstr_copy(allocator, realpath_result);
    free(realpath_result);

    return copy;
}

String os_path_join(Allocator* allocator, String *parts, size_t count)
{
    TempArena scratch = scratch_begin_conflict(allocator);

    StringBuffer str_buffer = str_buffer_new(&scratch.arena->allocator, 0);

    for (size_t i = 0; i < count; ++i)
    {
        String str = parts[i];

        if (str_back(str) == '/')
        {
            str = str_trunc_right(str, 1);
        }

        str_buffer_push_back(&str_buffer, str);

        if (i != count - 1)
        {
            str_buffer_push_back_lit(&str_buffer, "/");
        }
    }

    String path = str_buffer_view_copy(allocator, &str_buffer);
    scratch_end(scratch);

    return path;
}

