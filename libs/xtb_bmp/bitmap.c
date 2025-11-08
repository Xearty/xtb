XTB_BMP_Bitmap
xtb_bmp_bitmap_load(XTB_BMP_Prepass_Result prepass_result,
                    const XTB_Byte *bytes,
                    void *in_bitmap_buffer)
{
    XTB_BMP_Bitmap result = {};

    XTB_BMP_File_Header *file_header = &prepass_result.file_header;
    XTB_BMP_Info_Header *info_header = &prepass_result.info_header;

    const XTB_Byte *color_table_data = bytes + XTB_BMP_COLOR_TABLE_OFFSET;

    Bitfields bitfields = parse_bitfields(&color_table_data, info_header);

    const XTB_Byte *pixel_data = bytes + file_header->data_offset;

    parse_pixel_data(pixel_data,
                     (XTB_BMP_Color*)color_table_data,
                     info_header,
                     bitfields,
                     in_bitmap_buffer);

    result.width = prepass_result.info_header.width;
    result.height = absolute_value(prepass_result.info_header.height);
    result.stride = prepass_result.info_header.width * sizeof(XTB_BMP_Color);
    result.pixel_data = in_bitmap_buffer;

    return result;
}

XTB_BMP_Bitmap
xtb_bmp_bitmap_load_alloc(Allocator* allocator, const XTB_Byte *bytes)
{
    XTB_BMP_Prepass_Result prepass_result = xtb_bmp_prepass(bytes);
    XTB_BMP_Memory_Requirements mr = prepass_result.memory_requirements;
    printf("allocation size: %lu\n", mr.bitmap_buffer_size);
    void *bitmap_buffer = XTB_AllocateBytes(allocator, mr.bitmap_buffer_size);
    return xtb_bmp_bitmap_load(prepass_result, bytes, bitmap_buffer);
}

void
xtb_bmp_bitmap_dealloc(Allocator* allocator, XTB_BMP_Bitmap *bitmap)
{
    XTB_Deallocate(allocator, bitmap->pixel_data);
}

void
xtb_bmp_set_global_allocator(Allocator* allocator)
{
    xtb_bmp_global_allocator = allocator;
}

void
xtb_bmp_bitmap_gdealloc(XTB_BMP_Bitmap *bitmap)
{
    xtb_bmp_bitmap_dealloc(xtb_bmp_global_allocator, bitmap);
}

XTB_BMP_Bitmap
xtb_bmp_bitmap_load_from_stream(XTB_BMP_IO_Stream stream,
                                Allocator* allocator)
{
    stream.seek(stream.context, 0, XTB_BMP_IO_SEEK_END);
    int size = stream.tell(stream.context);
    stream.seek(stream.context, 0, XTB_BMP_IO_SEEK_SET);

    char *buffer = XTB_AllocateBytes(allocator, size + 1);
    int bytes_read = stream.read(stream.context, buffer, size);

    if (bytes_read == size)
    {
        buffer[size] = '\0';
        puts(buffer);
    }
    else
    {
        puts("Could not read stream");
        XTB_Deallocate(allocator, buffer);
    }

    return xtb_bmp_bitmap_load_alloc(allocator, buffer);
}
