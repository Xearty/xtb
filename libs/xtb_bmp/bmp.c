#include "bmp.h"

#include <stdio.h>
#include <assert.h>
#include <stdbool.h>
#include <string.h>
#include <stdint.h>

#define internal static
#define NOT_IMPLEMENTED do assert(0 && "NOT IMPLEMENTED"); while (0)

/****************************************************************
 * utils.c
****************************************************************/
internal unsigned int
parse_bytes(const XTB_Byte *bytes, int count)
{
    unsigned int result = 0;
    for (int i = 0; i < count; ++i)
    {
        result += bytes[i] << (i * 8);

    }
    return result;
}

internal int
parse_4_bytes(const XTB_Byte *bytes)
{
    return (bytes[0] << 0)
        | (bytes[1] << 8)
        | (bytes[2] << 16)
        | (bytes[3] << 24);
}

internal int
parse_2_bytes(const XTB_Byte *bytes)
{
    return (bytes[0] << 0) | (bytes[1] << 8);
}

internal int
absolute_value(int value)
{
    if (value < 0)
    {
        return -value;
    }
    else
    {
        return value;
    }
}

// TODO: to shift the mask and get the shift value
internal unsigned int
count_trailing_zeroes(unsigned int in)
{
    if (in == 0)
    {
        return in;
    }

    unsigned int shift_value = 0;

    while ((in & 1) == 0)
    {
        in >>= 1;
        shift_value += 1;
    }

    return shift_value;
}

internal unsigned int
map_range(unsigned int value,
          unsigned int from_min, unsigned int from_max,
          unsigned int to_min, unsigned int to_max)
{
    if (from_max == from_min)
    {
        return to_min;
    }
    else
    {
        return to_min + ((value - from_min) * (to_max - to_min)) / (from_max - from_min);
    }
}

internal int
count_set_bits(unsigned int value)
{
    int count = 0;
    for (int i = 0; i < 32; ++i)
    {
        unsigned int mask = (1 << i);
        count += !!(value & mask);
    }

    return count;
}

internal unsigned int
int_trim_trailing_zeroes(unsigned int in)
{
    if (in == 0)
    {
        return in;
    }

    while ((in & 1) == 0)
    {
        in >>= 1;
    }

    return in;
}

int xtb_pow(int base, int power)
{
    int result = 1;
    for (int i = 0; i < power; ++i)
    {
        result *= base;
    }
    return result;
}

internal XTB_Byte
lo_nibble(XTB_Byte byte)
{
    return byte & 0x0f;
}

internal XTB_Byte
hi_nibble(XTB_Byte byte)
{
    return (byte & 0xf0) >> 4;
}



/****************************************************************
 * measure.c
****************************************************************/
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

/****************************************************************
 * prepass.c
****************************************************************/
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
/****************************************************************
 * bitfields.c
****************************************************************/
typedef struct Bitfields_Channel_Info Bitfields_Channel_Info;
struct Bitfields_Channel_Info
{
    unsigned int mask;
    unsigned int depth;
    unsigned int shift;
};

typedef struct Bitfields Bitfields;
struct Bitfields
{
    Bitfields_Channel_Info blue_chan;
    Bitfields_Channel_Info green_chan;
    Bitfields_Channel_Info red_chan;
    Bitfields_Channel_Info alpha_chan;
};

Bitfields_Channel_Info
bitmask_to_bitfields_channel_info(unsigned int bitmask)
{
    Bitfields_Channel_Info result = {};
    result.mask = bitmask;
    result.shift = count_trailing_zeroes(bitmask);
    result.depth = count_set_bits(bitmask);

    return result;
}

internal XTB_Byte
extract_and_normalize_channel_bits(unsigned int pixel, Bitfields_Channel_Info bitfields)
{
    unsigned int channel_bits = (pixel & bitfields.mask) >> bitfields.shift;
    unsigned int range_size = 1 << bitfields.depth;
    return map_range(channel_bits, 0, range_size - 1, 0, 255);
}

internal Bitfields
get_default_bitfields_for_bpp(int bpp)
{
    Bitfields bitfields = {};

    switch (bpp)
    {
        case 16:
        {
            bitfields.blue_chan = bitmask_to_bitfields_channel_info(0x1f);
            bitfields.green_chan = bitmask_to_bitfields_channel_info(0x1f << 5);
            bitfields.red_chan = bitmask_to_bitfields_channel_info(0x1f << 10);
        } break;

        case 24:
        {
            bitfields.blue_chan = bitmask_to_bitfields_channel_info(0xff);
            bitfields.green_chan = bitmask_to_bitfields_channel_info(0xff << 8);
            bitfields.red_chan = bitmask_to_bitfields_channel_info(0xff << 16);
        } break;

        case 32:
        {
            bitfields.blue_chan = bitmask_to_bitfields_channel_info(0xff);
            bitfields.green_chan = bitmask_to_bitfields_channel_info(0xff << 8);
            bitfields.red_chan = bitmask_to_bitfields_channel_info(0xff << 16);
            bitfields.alpha_chan = bitmask_to_bitfields_channel_info(0xff << 24);
        } break;
    }

    return bitfields;
}

internal Bitfields
parse_bitfields(const XTB_Byte **bytes, XTB_BMP_Info_Header *info_header)
{
#define PARSE_BITMASK(CHAN)                                             \
    bitfields.CHAN##_chan = bitmask_to_bitfields_channel_info(parse_4_bytes(*bytes)); \
    *bytes += 4;

    Bitfields bitfields = {};
    if (info_header->compression == XTB_BMP_CT_BI_BITFIELDS)
    {
        PARSE_BITMASK(red);
        PARSE_BITMASK(green);
        PARSE_BITMASK(blue);
    }
    else if (info_header->compression == XTB_BMP_CT_BI_ALPHABITFIELDS)
    {
        PARSE_BITMASK(red);
        PARSE_BITMASK(green);
        PARSE_BITMASK(blue);
        PARSE_BITMASK(alpha);
    }

    return bitfields;
}
/****************************************************************
 * pixel_data.c
****************************************************************/
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
/****************************************************************
 * allocator.c
****************************************************************/
Allocator* xtb_bmp_global_allocator;

Allocator*
xtb_bmp_get_global_allocator()
{
    return xtb_bmp_global_allocator;
}

XTB_BMP_Bitmap
xtb_bmp_bitmap_load_galloc(const XTB_Byte *bytes)
{
    return xtb_bmp_bitmap_load_alloc(xtb_bmp_global_allocator, bytes);
}

/****************************************************************
 * bitmap.c
****************************************************************/
#define XTB_BMP_COLOR_TABLE_OFFSET 0x36
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
    void *bitmap_buffer = AllocateBytes(allocator, mr.bitmap_buffer_size);
    return xtb_bmp_bitmap_load(prepass_result, bytes, bitmap_buffer);
}

void
xtb_bmp_bitmap_dealloc(Allocator* allocator, XTB_BMP_Bitmap *bitmap)
{
    Deallocate(allocator, bitmap->pixel_data);
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

    char *buffer = AllocateBytes(allocator, size + 1);
    int bytes_read = stream.read(stream.context, buffer, size);

    if (bytes_read == size)
    {
        buffer[size] = '\0';
        puts(buffer);
    }
    else
    {
        puts("Could not read stream");
        Deallocate(allocator, buffer);
    }

    return xtb_bmp_bitmap_load_alloc(allocator, buffer);
}
/****************************************************************
 * dib.c
****************************************************************/
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
xtb_bmp_dib_load_alloc(Allocator* allocator, const XTB_Byte *bytes)
{
    XTB_BMP_Prepass_Result prepass_result = xtb_bmp_prepass(bytes);
    XTB_BMP_Memory_Requirements mr = prepass_result.memory_requirements;
    void *color_table_buffer = AllocateBytes(allocator, mr.color_table_buffer_size);
    void *pixel_data_buffer = AllocateBytes(allocator, mr.pixel_data_buffer_size);
    return xtb_bmp_dib_load(prepass_result, bytes, color_table_buffer, pixel_data_buffer);
}

void
xtb_bmp_dib_dealloc(Allocator* allocator, XTB_BMP_DIB *dib)
{
    Deallocate(allocator, dib->color_table);
    Deallocate(allocator, dib->pixel_data);
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
    void *bitmap_buffer = AllocateBytes(xtb_bmp_global_allocator, bitmap_buffer_size);

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

/****************************************************************
 * dib.c
****************************************************************/
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

/****************************************************************
 * bmp.c
****************************************************************/
XTB_BMP_Color
xtb_bmp_color_create(XTB_Byte b, XTB_Byte g, XTB_Byte r, XTB_Byte a)
{
    XTB_BMP_Color color;
    color.b = b;
    color.g = g;
    color.r = r;
    color.a = a;

    return color;
}
