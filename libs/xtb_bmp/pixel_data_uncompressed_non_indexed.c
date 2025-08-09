internal XTB_BMP_Color
parse_pixel_non_indexed(const XTB_Byte *bytes, int bytes_per_pixel, Bitfields bitfields)
{
    unsigned int pixel = parse_bytes(bytes, bytes_per_pixel);

    XTB_Byte b = extract_and_normalize_channel_bits(pixel, bitfields.blue_chan);
    XTB_Byte g = extract_and_normalize_channel_bits(pixel, bitfields.green_chan);
    XTB_Byte r = extract_and_normalize_channel_bits(pixel, bitfields.red_chan);
    XTB_Byte a = extract_and_normalize_channel_bits(pixel, bitfields.alpha_chan);

    return xtb_bmp_color_create(b, g, r, 255);
}

internal void
parse_pixel_data_non_indexed(Traversal_Info ti,
                             const XTB_BMP_Info_Header *info_header,
                             const XTB_Byte *pixel_data,
                             Bitfields bitfields,
                             XTB_BMP_Color *out_bitmap)
{
    int bytes_per_pixel = info_header->bits_per_pixel / 8;

    int out_index = 0;

    for (int h = ti.start_row_idx; h != ti.end_row_idx; h += ti.direction)
    {
        const XTB_Byte *row = &pixel_data[h * ti.stride];
        for (int w = 0; w < info_header->width; ++w)
        {
            int offset = w * bytes_per_pixel;
            out_bitmap[out_index++] =
                parse_pixel_non_indexed(row + offset, bytes_per_pixel, bitfields);
        }
    }
}
