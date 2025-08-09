size_t
xtb_bmp_measure_color_table_count(int bits_per_pixel)
{
    switch (bits_per_pixel)
    {
        case 1: return 2;
        case 2: return 4;
        case 4: return 16;
        case 8: return 256;
        default: return 0;
    }
}

size_t
xtb_bmp_measure_color_table_size_bytes(int bits_per_pixel)
{
    return xtb_bmp_measure_color_table_count(bits_per_pixel) * sizeof(XTB_BMP_Color);
}

size_t
xtb_bmp_measure_bitmap_stride(int bpp, int width)
{
    return ((bpp * width + 31) / 32) * 4;
}

size_t
xtb_bmp_measure_pixel_data_size(int bpp, int width, int height)
{
    return height * xtb_bmp_measure_bitmap_stride(bpp, width);
}

size_t
xtb_bmp_measure_pixel_data_size_bytes_from_header(const XTB_BMP_Info_Header *info_header)
{
    size_t stride = xtb_bmp_measure_bitmap_stride(info_header->bits_per_pixel, info_header->width);
    return absolute_value(info_header->height) * stride;
}
