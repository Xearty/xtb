#include "pixel_data_traversal.c"
#include "pixel_data_uncompressed_indexed.c"
#include "pixel_data_uncompressed_non_indexed.c"
#include "pixel_data_rle.c"

internal void
parse_pixel_data(const XTB_Byte *pixel_data,
                 const XTB_BMP_Color *color_table,
                 const XTB_BMP_Info_Header *info_header,
                 Bitfields bitfields, // Only read for compression type (alpha)bitfields
                 XTB_BMP_Color *out_bitmap)
{

    Traversal_Info traversal_info = compute_traversal_info(info_header);

    switch (info_header->compression)
    {
        case XTB_BMP_CT_BI_RGB:
        {
            if (info_header->bits_per_pixel <= 8)
            {
                parse_pixel_data_indexed(traversal_info, info_header, pixel_data, color_table, out_bitmap);
            }
            else
            {
                Bitfields default_bitfields = get_default_bitfields_for_bpp(info_header->bits_per_pixel);
                parse_pixel_data_non_indexed(traversal_info, info_header, pixel_data, default_bitfields, out_bitmap);
            }
        } break;

        case XTB_BMP_CT_BI_BITFIELDS:
        {
            parse_pixel_data_non_indexed(traversal_info, info_header, pixel_data, bitfields, out_bitmap);
        } break;

        case XTB_BMP_CT_BI_RLE4:
        case XTB_BMP_CT_BI_RLE8:
        {
            parse_pixel_data_rle(traversal_info, info_header, pixel_data, color_table, out_bitmap);
        } break;

        default:
        {
            assert(false && "Compression format is unsupported");
        } break;
    }
}
