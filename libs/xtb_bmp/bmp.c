#include "bmp.h"

#include <stdio.h>
#include <assert.h>
#include <stdbool.h>
#include <string.h>
#include <stdint.h>
#include <math.h>

#define internal static
#define NOT_IMPLEMENTED do assert(0 && "NOT IMPLEMENTED"); while (0)

/****************************************************************
 * utils.c
****************************************************************/
internal unsigned int
parse_bytes(const u8 *bytes, int count)
{
    unsigned int result = 0;
    for (int i = 0; i < count; ++i)
    {
        result += bytes[i] << (i * 8);

    }
    return result;
}

internal int
parse_4_bytes(const u8 *bytes)
{
    return (bytes[0] << 0)
        | (bytes[1] << 8)
        | (bytes[2] << 16)
        | (bytes[3] << 24);
}

internal int
parse_2_bytes(const u8 *bytes)
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

internal u8
lo_nibble(u8 byte)
{
    return byte & 0x0f;
}

internal u8
hi_nibble(u8 byte)
{
    return (byte & 0xf0) >> 4;
}



/****************************************************************
 * measure.c
****************************************************************/
size_t
bmp_measure_color_table_count(int bits_per_pixel)
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
bmp_measure_color_table_size_bytes(int bits_per_pixel)
{
    return bmp_measure_color_table_count(bits_per_pixel) * sizeof(BMP_Color);
}

size_t
bmp_measure_bitmap_stride(int bpp, int width)
{
    return ((bpp * width + 31) / 32) * 4;
}

size_t
bmp_measure_pixel_data_size(int bpp, int width, int height)
{
    return height * bmp_measure_bitmap_stride(bpp, width);
}

size_t
bmp_measure_pixel_data_size_bytes_from_header(const BMP_Info_Header *info_header)
{
    size_t stride = bmp_measure_bitmap_stride(info_header->bits_per_pixel, info_header->width);
    return absolute_value(info_header->height) * stride;
}

/****************************************************************
 * prepass.c
****************************************************************/
BMP_Prepass_Result
bmp_prepass(const u8 *bytes)
{
    BMP_Prepass_Result result = {};

    const u8 *ptr = bytes;

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

    int num_colors = bmp_measure_color_table_count(result.info_header.bits_per_pixel);
    printf("num_colors = %d\n", num_colors);

    // Buffer sizes
    result.memory_requirements.bitmap_buffer_size = 4 * result.info_header.width * absolute_value(result.info_header.height);
    result.memory_requirements.color_table_buffer_size = num_colors * sizeof(BMP_Color);

    if (result.info_header.compression == BMP_CT_BI_RGB)
    {
            result.memory_requirements.pixel_data_buffer_size =
                bmp_measure_pixel_data_size_bytes_from_header(&result.info_header);
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

internal u8
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
parse_bitfields(const u8 **bytes, BMP_Info_Header *info_header)
{
#define PARSE_BITMASK(CHAN)                                             \
    bitfields.CHAN##_chan = bitmask_to_bitfields_channel_info(parse_4_bytes(*bytes)); \
    *bytes += 4;

    Bitfields bitfields = {};
    if (info_header->compression == BMP_CT_BI_BITFIELDS)
    {
        PARSE_BITMASK(red);
        PARSE_BITMASK(green);
        PARSE_BITMASK(blue);
    }
    else if (info_header->compression == BMP_CT_BI_ALPHABITFIELDS)
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
compute_traversal_info(const BMP_Info_Header *info_header)
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
                         const BMP_Info_Header *info_header,
                         const u8 *pixel_data,
                         const BMP_Color *color_table,
                         BMP_Color *out_bitmap)
{
    int bpp = info_header->bits_per_pixel;
    int bitmask = pow(2, bpp) - 1;
    int pixels_per_byte = 8 / bpp;

    unsigned int out_index = 0;

    for (int h = ti.start_row_idx; h != ti.end_row_idx; h += ti.direction)
    {
        const u8 *row = &pixel_data[h * ti.stride];
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

internal BMP_Color
parse_pixel_non_indexed(const u8 *bytes, int bytes_per_pixel, Bitfields bitfields)
{
    unsigned int pixel = parse_bytes(bytes, bytes_per_pixel);

    u8 b = extract_and_normalize_channel_bits(pixel, bitfields.blue_chan);
    u8 g = extract_and_normalize_channel_bits(pixel, bitfields.green_chan);
    u8 r = extract_and_normalize_channel_bits(pixel, bitfields.red_chan);
    u8 a = extract_and_normalize_channel_bits(pixel, bitfields.alpha_chan);

    return bmp_color_create(b, g, r, 255);
}

internal void
parse_pixel_data_non_indexed(Traversal_Info ti,
                             const BMP_Info_Header *info_header,
                             const u8 *pixel_data,
                             Bitfields bitfields,
                             BMP_Color *out_bitmap)
{
    int bytes_per_pixel = info_header->bits_per_pixel / 8;

    int out_index = 0;

    for (int h = ti.start_row_idx; h != ti.end_row_idx; h += ti.direction)
    {
        const u8 *row = &pixel_data[h * ti.stride];
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
                     const BMP_Info_Header *info_header,
                     const u8 *pixel_data,
                     const BMP_Color *color_table,
                     BMP_Color *out_bitmap)
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
            u8 fbyte = pixel_data[offset];
            u8 sbyte = pixel_data[offset + 1];
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
                    u8 x_delta = pixel_data[offset];
                    u8 y_delta = pixel_data[offset + 1];
                    offset += 2;

#ifdef BMP_DELTA_FILL
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
                    u8 pixels_count = sbyte;

                    for (int i = 0; i < pixels_count; ++i)
                    {
                        int index = h * info_header->width + w;

                        u8 pixel_byte_index = i / 2;
                        u8 pixel_byte = pixel_data[offset + pixel_byte_index];

                        u8 color_index;
                        if (info_header->compression == BMP_CT_BI_RLE4)
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


                    if (info_header->compression == BMP_CT_BI_RLE4)
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
                u8 run_count = fbyte;
                u8 value = sbyte;

                if (info_header->compression == BMP_CT_BI_RLE4)
                {
                    for (int i = 0; i < run_count; ++i)
                    {
                        int index = h * info_header->width + w;
                        u8 color_index = (i % 2 == 0)
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
parse_pixel_data(const u8 *pixel_data,
                 const BMP_Color *color_table,
                 const BMP_Info_Header *info_header,
                 Bitfields bitfields, // Only read for compression type (alpha)bitfields
                 BMP_Color *out_bitmap)
{

    Traversal_Info traversal_info = compute_traversal_info(info_header);

    switch (info_header->compression)
    {
        case BMP_CT_BI_RGB:
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

        case BMP_CT_BI_BITFIELDS:
        {
            parse_pixel_data_non_indexed(traversal_info, info_header, pixel_data, bitfields, out_bitmap);
        } break;

        case BMP_CT_BI_RLE4:
        case BMP_CT_BI_RLE8:
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
Allocator* bmp_global_allocator;

Allocator*
bmp_get_global_allocator()
{
    return bmp_global_allocator;
}

BMP_Bitmap
bmp_bitmap_load_galloc(const u8 *bytes)
{
    return bmp_bitmap_load_alloc(bmp_global_allocator, bytes);
}

/****************************************************************
 * bitmap.c
****************************************************************/
#define BMP_COLOR_TABLE_OFFSET 0x36
BMP_Bitmap
bmp_bitmap_load(BMP_Prepass_Result prepass_result,
                    const u8 *bytes,
                    void *in_bitmap_buffer)
{
    BMP_Bitmap result = {};

    BMP_File_Header *file_header = &prepass_result.file_header;
    BMP_Info_Header *info_header = &prepass_result.info_header;

    const u8 *color_table_data = bytes + BMP_COLOR_TABLE_OFFSET;

    Bitfields bitfields = parse_bitfields(&color_table_data, info_header);

    const u8 *pixel_data = bytes + file_header->data_offset;

    parse_pixel_data(pixel_data,
                     (BMP_Color*)color_table_data,
                     info_header,
                     bitfields,
                     in_bitmap_buffer);

    result.width = prepass_result.info_header.width;
    result.height = absolute_value(prepass_result.info_header.height);
    result.stride = prepass_result.info_header.width * sizeof(BMP_Color);
    result.pixel_data = in_bitmap_buffer;

    return result;
}

BMP_Bitmap
bmp_bitmap_load_alloc(Allocator* allocator, const u8 *bytes)
{
    BMP_Prepass_Result prepass_result = bmp_prepass(bytes);
    BMP_Memory_Requirements mr = prepass_result.memory_requirements;
    printf("allocation size: %lu\n", mr.bitmap_buffer_size);
    void *bitmap_buffer = AllocateBytes(allocator, mr.bitmap_buffer_size);
    return bmp_bitmap_load(prepass_result, bytes, bitmap_buffer);
}

void
bmp_bitmap_dealloc(Allocator* allocator, BMP_Bitmap *bitmap)
{
    Deallocate(allocator, bitmap->pixel_data);
}

void
bmp_set_global_allocator(Allocator* allocator)
{
    bmp_global_allocator = allocator;
}

void
bmp_bitmap_gdealloc(BMP_Bitmap *bitmap)
{
    bmp_bitmap_dealloc(bmp_global_allocator, bitmap);
}

/****************************************************************
 * dib.c
****************************************************************/
BMP_DIB
bmp_dib_load(BMP_Prepass_Result prepass_result,
                 const u8 *bytes,
                 void *color_table_buffer,
                 void *pixel_data_buffer)
{
    BMP_DIB result = {};
    result.info_header = prepass_result.info_header;
    result.color_table = color_table_buffer;
    result.pixel_data = pixel_data_buffer;

    if (prepass_result.info_header.bits_per_pixel <= 8)
    {
        const void *color_table_data = bytes + BMP_COLOR_TABLE_OFFSET;
        int bpp = prepass_result.info_header.bits_per_pixel;
        size_t color_table_size = bmp_measure_color_table_size_bytes(bpp);
        memcpy(result.color_table, color_table_data, color_table_size);
    }

    const u8 *pixel_data = bytes + prepass_result.file_header.data_offset;
    int pixel_data_size = bmp_measure_pixel_data_size_bytes_from_header(&prepass_result.info_header);
    memcpy(result.pixel_data, pixel_data, pixel_data_size);

    return result;
}

BMP_DIB
bmp_dib_load_alloc(Allocator* allocator, const u8 *bytes)
{
    BMP_Prepass_Result prepass_result = bmp_prepass(bytes);
    BMP_Memory_Requirements mr = prepass_result.memory_requirements;
    void *color_table_buffer = AllocateBytes(allocator, mr.color_table_buffer_size);
    void *pixel_data_buffer = AllocateBytes(allocator, mr.pixel_data_buffer_size);
    return bmp_dib_load(prepass_result, bytes, color_table_buffer, pixel_data_buffer);
}

void
bmp_dib_dealloc(Allocator* allocator, BMP_DIB *dib)
{
    Deallocate(allocator, dib->color_table);
    Deallocate(allocator, dib->pixel_data);
}

BMP_DIB
bmp_dib_load_galloc(const u8 *bytes)
{
    return bmp_dib_load_alloc(bmp_global_allocator, bytes);
}

void
bmp_dib_gdealloc(BMP_DIB *dib)
{
    bmp_dib_dealloc(bmp_global_allocator, dib);
}

BMP_Bitmap
bmp_bitmap_create_from_dib_galloc(const BMP_DIB *dib)
{
    BMP_Bitmap result = {};
    result.width = dib->info_header.width;
    result.height = absolute_value(dib->info_header.height);
    result.stride = result.width * sizeof(BMP_Color); // TODO(xearty): I think this is unused at the moment (but should not be)

    size_t bitmap_buffer_size = 4 * result.width * result.height;
    void *bitmap_buffer = AllocateBytes(bmp_global_allocator, bitmap_buffer_size);

    parse_pixel_data(dib->pixel_data,
                     dib->color_table,
                     &dib->info_header,
                     (Bitfields){},
                     bitmap_buffer);

    result.pixel_data = bitmap_buffer;
    return result;
}

size_t
bmp_dib_color_table_count(const BMP_DIB *dib)
{
    return bmp_measure_color_table_count(dib->info_header.bits_per_pixel);
}

size_t
bmp_dib_color_table_size_bytes(const BMP_DIB *dib)
{
    return bmp_measure_color_table_size_bytes(dib->info_header.bits_per_pixel);
}

void *
bmp_dib_color_table_replace(BMP_DIB *dib, void *new_table)
{
    void *old_table = dib->color_table;
    dib->color_table = new_table;
    return old_table;
}

void
bmp_dib_color_table_set_index(BMP_DIB *dib, size_t index, BMP_Color color)
{
    assert(index < bmp_dib_color_table_count(dib));
    dib->color_table[index] = color;
}

/****************************************************************
 * dib.c
****************************************************************/
internal BMP_File_Header
compute_file_header(const BMP_DIB *dib)
{
    int pixel_data_offset = BMP_COLOR_TABLE_OFFSET + bmp_dib_color_table_size_bytes(dib);
    size_t pixel_data_size = bmp_measure_pixel_data_size_bytes_from_header(&dib->info_header);

    BMP_File_Header file_header = {};
    file_header.file_size = pixel_data_offset + pixel_data_size;
    file_header.data_offset = pixel_data_offset;
    return file_header;
}

internal void
write_file_header(FILE *file, BMP_File_Header file_header)
{
    // Signature
    fwrite("BM", sizeof(char), 2, file);
    fwrite(&file_header.file_size, sizeof(uint32_t), 1, file); // file size
    fwrite("\0\0\0\0", sizeof(char), 4, file); // reserved
    fwrite(&file_header.data_offset, sizeof(uint32_t), 1, file); // data offset
}

#define BITWISE_SERIALIZE(VAR) fwrite(&(VAR), sizeof(VAR), 1, file);

internal void
write_info_header(FILE *file, const BMP_Info_Header *info_header)
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
bmp_dib_write(const BMP_DIB *dib, const char *filepath)
{
    BMP_File_Header file_header = compute_file_header(dib);

    FILE *file = fopen(filepath, "w");

    write_file_header(file, file_header);
    write_info_header(file, &dib->info_header);
    fwrite(dib->color_table, sizeof(char), bmp_dib_color_table_size_bytes(dib), file);

    size_t pixel_data_size = bmp_measure_pixel_data_size_bytes_from_header(&dib->info_header);
    fwrite(dib->pixel_data, sizeof(char), pixel_data_size, file);

    fclose(file);
}

/****************************************************************
 * bmp.c
****************************************************************/
BMP_Color
bmp_color_create(u8 b, u8 g, u8 r, u8 a)
{
    BMP_Color color;
    color.b = b;
    color.g = g;
    color.r = r;
    color.a = a;

    return color;
}
