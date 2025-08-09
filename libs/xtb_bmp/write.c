internal XTB_BMP_File_Header
compute_file_header(const XTB_BMP_DIB *dib)
{
    int pixel_data_offset = XTB_BMP_COLOR_TABLE_OFFSET + xtb_bmp_dib_color_table_size_bytes(dib);
    size_t pixel_data_size = xtb_bmp_measure_pixel_data_size_bytes_from_header(&dib->info_header);

    XTB_BMP_File_Header file_header = {};
    file_header.file_size = pixel_data_offset + pixel_data_size;
    file_header.data_offset = pixel_data_offset;
    return file_header;
}

internal void
write_file_header(FILE *file, XTB_BMP_File_Header file_header)
{
    // Signature
    fwrite("BM", sizeof(char), 2, file);
    fwrite(&file_header.file_size, sizeof(uint32_t), 1, file); // file size
    fwrite("\0\0\0\0", sizeof(char), 4, file); // reserved
    fwrite(&file_header.data_offset, sizeof(uint32_t), 1, file); // data offset
}

#define BITWISE_SERIALIZE(VAR) fwrite(&(VAR), sizeof(VAR), 1, file);

internal void
write_info_header(FILE *file, const XTB_BMP_Info_Header *info_header)
{
    uint32_t size = 40;
    uint16_t planes = 1;
    uint32_t padding4 = 0;

    BITWISE_SERIALIZE(size);
    BITWISE_SERIALIZE(info_header->width);
    BITWISE_SERIALIZE(info_header->height);
    BITWISE_SERIALIZE(planes);
    BITWISE_SERIALIZE(info_header->bits_per_pixel);
    BITWISE_SERIALIZE(info_header->compression);
    BITWISE_SERIALIZE(info_header->image_size);
    BITWISE_SERIALIZE(padding4);
    BITWISE_SERIALIZE(padding4);
    BITWISE_SERIALIZE(info_header->colors_used);
    BITWISE_SERIALIZE(info_header->important_colors);
}

void
xtb_bmp_dib_write(const XTB_BMP_DIB *dib, const char *filepath)
{
    XTB_BMP_File_Header file_header = compute_file_header(dib);

    FILE *file = fopen(filepath, "w");

    write_file_header(file, file_header);
    write_info_header(file, &dib->info_header);
    fwrite(dib->color_table, sizeof(char), xtb_bmp_dib_color_table_size_bytes(dib), file);

    size_t pixel_data_size = xtb_bmp_measure_pixel_data_size_bytes_from_header(&dib->info_header);
    fwrite(dib->pixel_data, sizeof(char), pixel_data_size, file);

    fclose(file);
}
