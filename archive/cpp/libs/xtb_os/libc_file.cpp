#include "os.h"
#include "xtb_core/core.h"
#include "xtb_core/string.h"
#include <xtb_core/thread_context.h>
#include <xtb_core/contract.h>
#include <stdio.h>
#include <stdlib.h>
#include <errno.h>

namespace xtb::os
{
static const char *file_mode_to_stdio_mode(FileModeFlags mode)
{
    if (mode & FileMode::Binary)
    {
        if (mode & FileMode::Read) return "rb";
        if (mode & FileMode::Write) return "wb";
    }
    else
    {
        if (mode & FileMode::Read) return "r";
        if (mode & FileMode::Write) return "w";
    }

    Unreachable;
}

FileHandle *open_file(String filepath, FileModeFlags mode)
{
    ScratchScope scratch;
    filepath = filepath.copy(&scratch->allocator);

    FileHandle *handle = (FileHandle*)fopen((const char *)filepath.data(), file_mode_to_stdio_mode(mode));
    if (!handle)
    {
        printf("Error code opening file: %d\n", errno);
        printf("Error opening file: %s\n", strerror(errno));
    }
    return handle;
}

void close_file(FileHandle *handle)
{
    fclose((FILE*)handle);
}

size_t read_file(FileHandle *handle, const u8 *buffer, size_t size)
{
    FILE *thandle = (FILE*)handle;
    return fread((char*)buffer, sizeof(char), size, thandle);
}

size_t get_file_size(FileHandle *handle)
{
    FILE *thandle = (FILE *)handle;

    size_t offset = ftell(thandle);

    fseek(thandle, 0, SEEK_END);
    size_t size = ftell(thandle);

    fseek(thandle, offset, SEEK_SET);
    return size;
}

String read_entire_file(Allocator *allocator, String filepath)
{
    FileHandle *handle = open_file(filepath, FileMode::Read | FileMode::Binary);
    if (handle == NULL) return String::invalid();

    size_t file_size = get_file_size(handle);
    u8 *buffer = allocate_bytes(allocator, file_size + 1);

    size_t bytes_read = read_file(handle, (u8*)buffer, file_size);
    close_file(handle);

    if (bytes_read == file_size)
    {
        buffer[bytes_read] = '\0';
        return String(buffer, file_size);
    }
    else
    {
        deallocate(allocator, buffer);
        return String::invalid();
    }
}

size_t write_file(FileHandle *handle, const u8 *buffer, size_t size)
{
    return fwrite(buffer, sizeof(char), size, (FILE*)handle);
}

size_t write_entire_file(String filepath, const u8 *buffer, size_t size)
{
    FileHandle *handle = open_file(filepath, FileMode::Write | FileMode::Binary);
    if (handle == NULL) return 0;

    size_t bytes_written = write_file(handle, buffer, size);
    close_file(handle);

    return bytes_written;
}

bool delete_file(String filepath)
{
    ScratchScope scratch;
    filepath = filepath.copy(&scratch->allocator);
    return remove((const char *)filepath.data()) == 0;
}

bool move_file(String old_path, String new_path)
{
    ScratchScope scratch;
    old_path = old_path.copy(&scratch->allocator);
    new_path = new_path.copy(&scratch->allocator);
    return rename((const char *)old_path.data(), (const char *)new_path.data()) == 0;
}

bool copy_file(String filepath, String new_path)
{
    ScratchScope scratch;

    String content = read_entire_file(&scratch->allocator, filepath);
    if (content.is_invalid())
    {
        return false;
    }

    return write_entire_file(new_path, (u8*)content.data(), content.len());
}

String real_path(Allocator* allocator, String filepath)
{
    ScratchScope scratch(allocator);
    filepath = filepath.copy(&scratch->allocator);
    char *realpath_result = realpath((char*)filepath.data(), NULL);

    String copy = String::from_cstr(realpath_result).copy(allocator);
    free(realpath_result);

    return copy;
}

String path_join(Allocator* allocator, String *parts, size_t count)
{
    ScratchScope scratch(allocator);

    StringBuf str_buffer = StringBuf::init(&scratch->allocator);

    for (size_t i = 0; i < count; ++i)
    {
        String str = parts[i];

        if (str.back() == '/')
        {
            str = str.trunc_left(1);
        }

        str_buffer.append(str);

        if (i != count - 1)
        {
            str_buffer.append('/');
        }
    }

    return str_buffer.view().copy(allocator);
}
}
