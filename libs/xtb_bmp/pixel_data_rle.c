internal void
parse_pixel_data_rle(Traversal_Info traversal_info,
                     const XTB_BMP_Info_Header *info_header,
                     const XTB_Byte *pixel_data,
                     const XTB_BMP_Color *color_table,
                     XTB_BMP_Color *out_bitmap)
{
    enum
    {
        RLE_EC_END_OF_LINE = 0x00,
        RLE_EC_END_OF_BITMAP = 0x01,
        RLE_EC_DELTA = 0x02
    };

    int h = traversal_info.start_row_idx;
    int w = 0;
    int offset = 0;

    bool is_end_of_bitmap = false;
    while (!is_end_of_bitmap)
    {
        while (true)
        {
            XTB_Byte fbyte = pixel_data[offset];
            XTB_Byte sbyte = pixel_data[offset + 1];
            offset += 2;

            if (fbyte == 0x00)
            {
                if (sbyte == RLE_EC_END_OF_LINE)
                {
                    w = 0;
                    h += traversal_info.direction;
                    break;
                }
                else if (sbyte == RLE_EC_END_OF_BITMAP)
                {
                    is_end_of_bitmap = true;
                    break;
                }
                else if (sbyte == RLE_EC_DELTA)
                {
                    // Delta
                    XTB_Byte x_delta = pixel_data[offset];
                    XTB_Byte y_delta = pixel_data[offset + 1];
                    offset += 2;

#ifdef XTB_BMP_DELTA_FILL
                    int pixels_fill_count = y_delta * info_header->width + x_delta;

                    int iter_index = h * info_header->width + w;
                    for (int i = 0; i < pixels_fill_count; ++i)
                    {
                        out_bitmap[iter_index++] = color_table[0];
                    }
#endif

                    h += y_delta * traversal_info.direction;
                    w += x_delta;
                }
                else
                {
                    // Absolute mode
                    XTB_Byte pixels_count = sbyte;

                    for (int i = 0; i < pixels_count; ++i)
                    {
                        int index = h * info_header->width + w;

                        XTB_Byte pixel_byte_index = i / 2;
                        XTB_Byte pixel_byte = pixel_data[offset + pixel_byte_index];

                        XTB_Byte color_index;
                        if (info_header->compression == XTB_BMP_CT_BI_RLE4)
                        {
                            color_index = (i % 2 == 0)
                                ? hi_nibble(pixel_byte)
                                : lo_nibble(pixel_byte);
                        }
                        else
                        {
                            color_index = pixel_data[offset + i];
                        }

                        out_bitmap[index] = color_table[color_index];
                        w++;
                    }


                    if (info_header->compression == XTB_BMP_CT_BI_RLE4)
                    {
                        offset += (pixels_count + 1) / 2;
                    }
                    else
                    {
                        offset += pixels_count;
                    }

                    offset += offset % 2;
                }
            }
            else
            {
                // Replicate value run_count number of times
                XTB_Byte run_count = fbyte;
                XTB_Byte value = sbyte;

                if (info_header->compression == XTB_BMP_CT_BI_RLE4)
                {
                    for (int i = 0; i < run_count; ++i)
                    {
                        int index = h * info_header->width + w;
                        XTB_Byte color_index = (i % 2 == 0)
                            ? hi_nibble(value)
                            : lo_nibble(value);
                        out_bitmap[index] = color_table[color_index];
                        w++;
                    }
                }
                else
                {
                    while (run_count--)
                    {
                        int index = h * info_header->width + w;
                        out_bitmap[index] = color_table[value];
                        w++;
                    }
                }

            }
        }
    }
}
