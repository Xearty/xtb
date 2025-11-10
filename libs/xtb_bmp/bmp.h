#ifndef _XTB_BMP_H_
#define _XTB_BMP_H_

#include <xtb_core/allocator.h>

#include <stddef.h>

/// Compile-time customization ///
// #define XTB_BMP_DELTA_FILL
/// end Compile-time customization //

#ifdef __cplusplus
extern "C" {
#endif

typedef enum BMP_Pixel_Format
{
    BMP_PF_ARGB8888
} BMP_Pixel_Format;

typedef enum BMP_Compression_Type
{
    BMP_CT_BI_RGB = 0,
    BMP_CT_BI_RLE8 = 1,
    BMP_CT_BI_RLE4 = 2,
    BMP_CT_BI_BITFIELDS = 3,
    BMP_CT_BI_JPEG = 4,
    BMP_CT_BI_PNG = 5,
    BMP_CT_BI_ALPHABITFIELDS = 6,
    BMP_CT_BI_CMYK = 11,
    BMP_CT_BI_CMYKRLE8 = 12,
    BMP_CT_BI_CMYKRLE4 = 13
} BMP_Compression_Type;

typedef struct BMP_File_Header BMP_File_Header;
struct BMP_File_Header
{
    int file_size;
    int data_offset;
};

typedef struct BMP_Info_Header BMP_Info_Header;
struct BMP_Info_Header
{
    int width;
    int height;
    short bits_per_pixel;
    BMP_Compression_Type compression;
    int image_size;
    int colors_used;
    int important_colors;
};

typedef struct BMP_Color BMP_Color;
struct BMP_Color
{
    u8 b;
    u8 g;
    u8 r;
    u8 a;
};

typedef struct BMP_DIB BMP_DIB;
struct BMP_DIB
{
    BMP_Info_Header info_header;
    BMP_Color *color_table;
    u8 *pixel_data;
};

typedef struct BMP_Memory_Requirements BMP_Memory_Requirements;
struct BMP_Memory_Requirements
{
    size_t bitmap_buffer_size;
    size_t color_table_buffer_size;
    size_t pixel_data_buffer_size;
};

typedef struct BMP_Prepass_Result BMP_Prepass_Result;
struct BMP_Prepass_Result
{
    BMP_File_Header file_header;
    BMP_Info_Header info_header;
    BMP_Memory_Requirements memory_requirements;
};

typedef struct BMP_Bitmap BMP_Bitmap;
struct BMP_Bitmap
{
    BMP_Color *pixel_data;
    int width;
    int height;
    int stride;
};

/*******************************
 * Utilities
 *******************************/
BMP_Color bmp_color_create(u8 b, u8 g, u8 r, u8 a);

/*******************************
 * Zero Allocations API
 *******************************/
BMP_Prepass_Result bmp_prepass(const u8 *bytes);
BMP_DIB    bmp_dib_load(BMP_Prepass_Result prepass_result, const u8 *bytes, void *color_table_buffer, void *pixel_data_buffer);
BMP_Bitmap bmp_load_bitmap(BMP_Prepass_Result prepass_result, const u8 *bytes, void *in_bitmap_buffer);

/*******************************
 * Allocator API
 *******************************/
BMP_DIB bmp_dib_load_alloc(Allocator* allocator, const u8 *bytes);
void        bmp_dib_dealloc(Allocator* allocator, BMP_DIB *dib);
BMP_Bitmap bmp_bitmap_load_alloc(Allocator* allocator, const u8 *bytes);
void           bmp_bitmap_dealloc(Allocator* allocator, BMP_Bitmap *bitmap);

/*******************************
 * Global Allocator API
 *******************************/
void bmp_set_global_allocator(Allocator* allocator);
Allocator* bmp_get_global_allocator();

BMP_DIB bmp_dib_load_galloc(const u8 *bytes);
void        bmp_dib_gdealloc(BMP_DIB *dib);
BMP_Bitmap bmp_bitmap_load_galloc(const u8 *bytes);
void           bmp_bitmap_gdealloc(BMP_Bitmap *bitmap);

/*******************************
 * Misc API
 *******************************/
BMP_Bitmap bmp_bitmap_create_from_dib_galloc(const BMP_DIB *dib);

size_t bmp_dib_color_table_count(const BMP_DIB *dib);
size_t bmp_dib_color_table_size_bytes(const BMP_DIB *dib);
void * bmp_dib_color_table_replace(BMP_DIB *dib, void *new_table);
void   bmp_dib_color_table_set_index(BMP_DIB *dib, size_t index, BMP_Color color);

/*******************************
 * Measure API
 *******************************/
size_t bmp_measure_color_table_count(int bits_per_pixel);
size_t bmp_measure_color_table_size_bytes(int bits_per_pixel);
size_t bmp_measure_bitmap_stride(int bpp, int width);
size_t bmp_measure_pixel_data_size_bytes(int bpp, int width, int height);
size_t bmp_measure_pixel_data_size_bytes_from_header(const BMP_Info_Header *info_header);

/*******************************
 * Write API
 *******************************/
void bmp_dib_write(const BMP_DIB *dib, const char *filepath);

// Maybe add managed and unmanaged versions

#ifdef __cplusplus
}
#endif

#endif // _XTB_BMP_H_
