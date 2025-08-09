const char *libc_file_mode(XTB_BMP_IO_Stream_Mode mode)
{
    if (mode & XTB_BMP_IO_STREAM_MODE_BINARY)
    {
        if (mode & XTB_BMP_IO_STREAM_MODE_READ)  return "rb";
        if (mode & XTB_BMP_IO_STREAM_MODE_WRITE) return "wb";
    }
    else
    {
        if (mode & XTB_BMP_IO_STREAM_MODE_READ)  return "r";
        if (mode & XTB_BMP_IO_STREAM_MODE_WRITE) return "w";
    }

    assert(false);
    return "";
}

size_t
libc_file_stream_read(void *context, void *buffer, size_t bytes_to_read)
{
    FILE *file = (FILE*)context;
    return fread(buffer, sizeof(char), bytes_to_read, file);
}

int
libc_seek_origin(XTB_BMP_IO_Seek_Origin origin)
{
    switch (origin)
    {
        case XTB_BMP_IO_SEEK_SET: return SEEK_SET;
        case XTB_BMP_IO_SEEK_CUR: return SEEK_CUR;
        case XTB_BMP_IO_SEEK_END: return SEEK_END;
    }
}

int
libc_file_stream_seek(void *context,
                      int offset,
                      XTB_BMP_IO_Seek_Origin origin)
{
    FILE *file = (FILE*)context;

    int libc_origin = libc_seek_origin(origin);
    return fseek(file, offset, libc_origin);
}

int
libc_file_stream_tell(void* context)
{
    FILE *file = (FILE*)context;
    return ftell(file);
}

size_t
libc_file_stream_write(void *context, const void *source_buffer, size_t bytes_to_write)
{
    FILE *file = (FILE*)context;
    return fwrite(source_buffer, sizeof(char), bytes_to_write, file);
}

XTB_BMP_IO_Stream libc_file_read_stream_open(const char *path, XTB_BMP_IO_Stream_Mode mode)
{
    const char *libc_mode = libc_file_mode(mode);
    FILE *file = fopen(path, libc_mode);
    assert(file);

    XTB_BMP_IO_Stream stream = {
        .context = file,
        .read = libc_file_stream_read,
        .write = libc_file_stream_write,
        .seek = libc_file_stream_seek,
        .tell = libc_file_stream_tell,
    };

    return stream;
}

XTB_BMP_IO_Stream libc_file_read_text_stream_open(const char *path)
{
    int mode = XTB_BMP_IO_STREAM_MODE_READ;
    return libc_file_read_stream_open(path, mode);
}

XTB_BMP_IO_Stream libc_file_read_binary_stream_open(const char *path)
{
    int mode = XTB_BMP_IO_STREAM_MODE_READ | XTB_BMP_IO_STREAM_MODE_BINARY;
    return libc_file_read_stream_open(path, mode);
}

void libc_file_read_stream_close(XTB_BMP_IO_Stream stream)
{
    FILE *file = (FILE*)stream.context;
    fclose(file);
}
