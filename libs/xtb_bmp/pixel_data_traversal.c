typedef struct Traversal_Info Traversal_Info;
struct Traversal_Info
{
    int start_row_idx;
    int end_row_idx;
    int direction;

    int stride;
    int abs_height;

    int width;
};

internal Traversal_Info
compute_traversal_info(const XTB_BMP_Info_Header *info_header)
{
    Traversal_Info traversal_info = {};

    int abs_height = absolute_value(info_header->height);

    if (info_header->height >= 0)
    {
        traversal_info.start_row_idx = abs_height - 1;
        traversal_info.end_row_idx = -1;
        traversal_info.direction = -1;
    }
    else
    {
        traversal_info.start_row_idx = 0;
        traversal_info.end_row_idx = abs_height;
        traversal_info.direction = 1;
    }
    traversal_info.stride = ((info_header->bits_per_pixel * info_header->width + 31) / 32) * 4;

    return traversal_info;
}
