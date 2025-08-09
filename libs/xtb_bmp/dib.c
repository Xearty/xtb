XTB_BMP_DIB
xtb_bmp_dib_load(XTB_BMP_Prepass_Result prepass_result,
                 const XTB_Byte *bytes,
                 void *color_table_buffer,
                 void *pixel_data_buffer)
{
    XTB_BMP_DIB result = {};
    result.info_header = prepass_result.info_header;
    result.color_table = color_table_buffer;
    result.pixel_data = pixel_data_buffer;

    if (prepass_result.info_header.bits_per_pixel <= 8)
    {
        const void *color_table_data = bytes + XTB_BMP_COLOR_TABLE_OFFSET;
        int bpp = prepass_result.info_header.bits_per_pixel;
        size_t color_table_size = xtb_bmp_measure_color_table_size_bytes(bpp);
        memcpy(result.color_table, color_table_data, color_table_size);
    }

    const XTB_Byte *pixel_data = bytes + prepass_result.file_header.data_offset;
    int pixel_data_size = xtb_bmp_measure_pixel_data_size_bytes_from_header(&prepass_result.info_header);
    memcpy(result.pixel_data, pixel_data, pixel_data_size);

    return result;
}

XTB_BMP_DIB
xtb_bmp_dib_load_alloc(XTB_Allocator allocator, const XTB_Byte *bytes)
{
    XTB_BMP_Prepass_Result prepass_result = xtb_bmp_prepass(bytes);
    XTB_BMP_Memory_Requirements mr = prepass_result.memory_requirements;
    void *color_table_buffer = allocator.allocate(allocator.context, mr.color_table_buffer_size);
    void *pixel_data_buffer = allocator.allocate(allocator.context, mr.pixel_data_buffer_size);
    return xtb_bmp_dib_load(prepass_result, bytes, color_table_buffer, pixel_data_buffer);
}

void
xtb_bmp_dib_dealloc(XTB_Allocator allocator, XTB_BMP_DIB *dib)
{
    allocator.deallocate(allocator.context, dib->color_table);
    allocator.deallocate(allocator.context, dib->pixel_data);
}

XTB_BMP_DIB
xtb_bmp_dib_load_galloc(const XTB_Byte *bytes)
{
    return xtb_bmp_dib_load_alloc(xtb_bmp_global_allocator, bytes);
}

void
xtb_bmp_dib_gdealloc(XTB_BMP_DIB *dib)
{
    xtb_bmp_dib_dealloc(xtb_bmp_global_allocator, dib);
}

XTB_BMP_Bitmap
xtb_bmp_bitmap_create_from_dib_galloc(const XTB_BMP_DIB *dib)
{
    XTB_BMP_Bitmap result = {};
    result.width = dib->info_header.width;
    result.height = absolute_value(dib->info_header.height);
    result.stride = result.width * sizeof(XTB_BMP_Color); // TODO(xearty): I think this is unused at the moment (but should not be)

    size_t bitmap_buffer_size = 4 * result.width * result.height;
    void *bitmap_buffer = xtb_bmp_global_allocator.allocate(xtb_bmp_global_allocator.context,
                                                            bitmap_buffer_size);
    parse_pixel_data(dib->pixel_data,
                     dib->color_table,
                     &dib->info_header,
                     (Bitfields){},
                     bitmap_buffer);

    result.pixel_data = bitmap_buffer;
    return result;
}

size_t
xtb_bmp_dib_color_table_count(const XTB_BMP_DIB *dib)
{
    return xtb_bmp_measure_color_table_count(dib->info_header.bits_per_pixel);
}

size_t
xtb_bmp_dib_color_table_size_bytes(const XTB_BMP_DIB *dib)
{
    return xtb_bmp_measure_color_table_size_bytes(dib->info_header.bits_per_pixel);
}

void *
xtb_bmp_dib_color_table_replace(XTB_BMP_DIB *dib, void *new_table)
{
    void *old_table = dib->color_table;
    dib->color_table = new_table;
    return old_table;
}

void
xtb_bmp_dib_color_table_set_index(XTB_BMP_DIB *dib, size_t index, XTB_BMP_Color color)
{
    assert(index < xtb_bmp_dib_color_table_count(dib));
    dib->color_table[index] = color;
}
