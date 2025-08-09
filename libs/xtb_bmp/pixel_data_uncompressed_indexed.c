inline void
parse_pixel_data_indexed(Traversal_Info ti,
                         const XTB_BMP_Info_Header *info_header,
                         const XTB_Byte *pixel_data,
                         const XTB_BMP_Color *color_table,
                         XTB_BMP_Color *out_bitmap)
{
    int bpp = info_header->bits_per_pixel;
    int bitmask = xtb_pow(2, bpp) - 1;
    int pixels_per_byte = 8 / bpp;

    unsigned int out_index = 0;

    for (int h = ti.start_row_idx; h != ti.end_row_idx; h += ti.direction)
    {
        const XTB_Byte *row = &pixel_data[h * ti.stride];
        for (int w = 0; w < info_header->width; ++w)
        {
            int byte_index = w / pixels_per_byte;
            int inner_index = w % pixels_per_byte;

            int shift_value = ((pixels_per_byte - 1 - inner_index) * bpp);
            int actual_bitmask = bitmask << shift_value;

            int byte = row[byte_index];
            int color_index = (byte & actual_bitmask) >> shift_value; 

            out_bitmap[out_index++] = color_table[color_index];
        }
    }
}
