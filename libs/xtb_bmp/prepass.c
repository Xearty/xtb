XTB_BMP_Prepass_Result
xtb_bmp_prepass(const XTB_Byte *bytes)
{
    XTB_BMP_Prepass_Result result = {};

    const XTB_Byte *ptr = bytes;

    // Parse file header
    if (ptr[0] != 'B' || ptr[1] != 'M')

    {
        printf("Invalid format. BMP file doesn't contain \"BM\" prefix");
        return result;
    }
    ptr += 2;

    result.file_header.file_size = parse_4_bytes(ptr);
    ptr += 4;

    printf("file_size = %d\n", result.file_header.file_size);

    // Skip reserved
    ptr += 4;

    result.file_header.data_offset = parse_4_bytes(ptr);
    printf("data_offset = %d\n", result.file_header.data_offset);
    ptr += 4;

    // Parse info header

    // skip size
    ptr += 4;

    result.info_header.width = parse_4_bytes(ptr);
    ptr += 4;

    result.info_header.height = parse_4_bytes(ptr);
    ptr += 4;
    /* if (result.info_header.height < 0) */
    /* { */
    /*     result.info_header.height *= -1; */
    /* } */

    printf("width, height = %d, %d\n", result.info_header.width, result.info_header.height);

    // skip planes
    ptr += 2;

    result.info_header.bits_per_pixel = parse_2_bytes(ptr);
    ptr += 2;


    /* int bitmap_buffer_size_in_bits = result.info.bits_per_pixel * result.info.width * result.info.height; */
    /* result.bitmap_buffer_size = (bitmap_buffer_size_in_bits + 7) / 8; */

    /* int row_size = 4 * ((result.bits_per_pixel * result.width + 31) / 32) */

    printf("bits_per_pixel = %d\n", (int)result.info_header.bits_per_pixel);

    result.info_header.compression = parse_4_bytes(ptr);
    ptr += 4;
    printf("compression = %d\n", result.info_header.compression);

    result.info_header.image_size = parse_4_bytes(ptr);
    ptr += 4;
    printf("image_size = %d\n", result.info_header.image_size);

    // Skip XpixelsPerM, YpixelsPerM
    ptr += 4 + 4;

    result.info_header.colors_used = parse_4_bytes(ptr);
    ptr += 4;
    printf("colors_used = %d\n", result.info_header.colors_used);

    result.info_header.important_colors = parse_4_bytes(ptr);
    ptr += 4;
    printf("important_colors = %d\n", result.info_header.important_colors);

    int num_colors = xtb_bmp_measure_color_table_count(result.info_header.bits_per_pixel);
    printf("num_colors = %d\n", num_colors);

    // Buffer sizes
    result.memory_requirements.bitmap_buffer_size = 4 * result.info_header.width * absolute_value(result.info_header.height);
    result.memory_requirements.color_table_buffer_size = num_colors * sizeof(XTB_BMP_Color);

    if (result.info_header.compression == XTB_BMP_CT_BI_RGB)
    {
            result.memory_requirements.pixel_data_buffer_size =
                xtb_bmp_measure_pixel_data_size_bytes_from_header(&result.info_header);
    }
    else
    {
        result.memory_requirements.pixel_data_buffer_size = result.info_header.image_size;
    }

    return result;
}
