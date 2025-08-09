#ifndef _XTB_BMP_H_
#define _XTB_BMP_H_

#include <xtb_allocator/allocator.h>

#include <stddef.h>

/// Compile-time customization ///
// #define XTB_BMP_DELTA_FILL
/// end Compile-time customization //

#ifdef __cplusplus
extern "C" {
#endif

typedef unsigned char XTB_Byte;

typedef enum XTB_BMP_Pixel_Format
{
    XTB_BMP_PF_ARGB8888
} XTB_BMP_Pixel_Format;

typedef enum XTB_BMP_Compression_Type
{
    XTB_BMP_CT_BI_RGB = 0,
    XTB_BMP_CT_BI_RLE8 = 1,
    XTB_BMP_CT_BI_RLE4 = 2,
    XTB_BMP_CT_BI_BITFIELDS = 3,
    XTB_BMP_CT_BI_JPEG = 4,
    XTB_BMP_CT_BI_PNG = 5,
    XTB_BMP_CT_BI_ALPHABITFIELDS = 6,
    XTB_BMP_CT_BI_CMYK = 11,
    XTB_BMP_CT_BI_CMYKRLE8 = 12,
    XTB_BMP_CT_BI_CMYKRLE4 = 13
} XTB_BMP_Compression_Type;

typedef struct XTB_BMP_File_Header XTB_BMP_File_Header;
struct XTB_BMP_File_Header
{
    int file_size;
    int data_offset;
};

typedef struct XTB_BMP_Info_Header XTB_BMP_Info_Header;
struct XTB_BMP_Info_Header
{
    int width;
    int height;
    short bits_per_pixel;
    XTB_BMP_Compression_Type compression;
    int image_size;
    int colors_used;
    int important_colors;
};

typedef struct XTB_BMP_Color XTB_BMP_Color;
struct XTB_BMP_Color
{
    XTB_Byte b;
    XTB_Byte g;
    XTB_Byte r;
    XTB_Byte a;
};

typedef struct XTB_BMP_DIB XTB_BMP_DIB;
struct XTB_BMP_DIB
{
    XTB_BMP_Info_Header info_header;
    XTB_BMP_Color *color_table;
    XTB_Byte *pixel_data;
};

typedef struct XTB_BMP_Memory_Requirements XTB_BMP_Memory_Requirements;
struct XTB_BMP_Memory_Requirements
{
    size_t bitmap_buffer_size;
    size_t color_table_buffer_size;
    size_t pixel_data_buffer_size;
};

typedef struct XTB_BMP_Prepass_Result XTB_BMP_Prepass_Result;
struct XTB_BMP_Prepass_Result
{
    XTB_BMP_File_Header file_header;
    XTB_BMP_Info_Header info_header;
    XTB_BMP_Memory_Requirements memory_requirements;
};

typedef struct XTB_BMP_Bitmap XTB_BMP_Bitmap;
struct XTB_BMP_Bitmap
{
    XTB_BMP_Color *pixel_data;
    int width;
    int height;
    int stride;
};

/*******************************
 * IO Stream
 *******************************/
typedef enum XTB_BMP_IO_Seek_Origin
{
    XTB_BMP_IO_SEEK_SET = 0,
    XTB_BMP_IO_SEEK_CUR = 1,
    XTB_BMP_IO_SEEK_END = 2
} XTB_BMP_IO_Seek_Origin;

typedef enum XTB_BMP_IO_Stream_Mode
{
    XTB_BMP_IO_STREAM_MODE_READ = 1 << 0,
    XTB_BMP_IO_STREAM_MODE_WRITE = 1 << 1,
    XTB_BMP_IO_STREAM_MODE_BINARY = 1 << 2
} XTB_BMP_IO_Stream_Mode;

typedef size_t(*XTB_BMP_IO_Stream_Read)(void *context, void *buffer, size_t bytes_to_read);
typedef size_t(*XTB_BMP_IO_Stream_Write)(void *context, const void *source_buffer, size_t bytes_to_write);
typedef int(*XTB_BMP_IO_Stream_Seek)(void *context, int offset, XTB_BMP_IO_Seek_Origin origin);
typedef int(*XTB_BMP_IO_Stream_Tell)(void* context);

typedef struct XTB_BMP_IO_Stream XTB_BMP_IO_Stream;
struct XTB_BMP_IO_Stream
{
    void *context;
    XTB_BMP_IO_Stream_Read read;
    XTB_BMP_IO_Stream_Write write;
    XTB_BMP_IO_Stream_Seek seek;
    XTB_BMP_IO_Stream_Tell tell;

};

/*******************************
 * Utilities
 *******************************/
XTB_BMP_Color xtb_bmp_color_create(XTB_Byte b, XTB_Byte g, XTB_Byte r, XTB_Byte a);

/*******************************
 * Zero Allocations API
 *******************************/
XTB_BMP_Prepass_Result xtb_bmp_prepass(const XTB_Byte *bytes);
XTB_BMP_DIB    xtb_bmp_dib_load(XTB_BMP_Prepass_Result prepass_result, const XTB_Byte *bytes, void *color_table_buffer, void *pixel_data_buffer);
XTB_BMP_Bitmap xtb_bmp_load_bitmap(XTB_BMP_Prepass_Result prepass_result, const XTB_Byte *bytes, void *in_bitmap_buffer);

/*******************************
 * Allocator API
 *******************************/
XTB_BMP_DIB xtb_bmp_dib_load_alloc(XTB_Allocator allocator, const XTB_Byte *bytes);
void        xtb_bmp_dib_dealloc(XTB_Allocator allocator, XTB_BMP_DIB *dib);
XTB_BMP_Bitmap xtb_bmp_bitmap_load_alloc(XTB_Allocator allocator, const XTB_Byte *bytes);
XTB_BMP_Bitmap xtb_bmp_bitmap_load_from_stream(XTB_BMP_IO_Stream stream, XTB_Allocator allocator);
void           xtb_bmp_bitmap_dealloc(XTB_Allocator allocator, XTB_BMP_Bitmap *bitmap);

/*******************************
 * Global Allocator API
 *******************************/
void xtb_bmp_set_global_allocator(XTB_Allocator allocator);
const XTB_Allocator *xtb_bmp_get_global_allocator();

XTB_BMP_DIB xtb_bmp_dib_load_galloc(const XTB_Byte *bytes);
void        xtb_bmp_dib_gdealloc(XTB_BMP_DIB *dib);
XTB_BMP_Bitmap xtb_bmp_bitmap_load_galloc(const XTB_Byte *bytes);
void           xtb_bmp_bitmap_gdealloc(XTB_BMP_Bitmap *bitmap);

/*******************************
 * Misc API
 *******************************/
XTB_BMP_Bitmap xtb_bmp_bitmap_create_from_dib_galloc(const XTB_BMP_DIB *dib);

size_t xtb_bmp_dib_color_table_count(const XTB_BMP_DIB *dib);
size_t xtb_bmp_dib_color_table_size_bytes(const XTB_BMP_DIB *dib);
void * xtb_bmp_dib_color_table_replace(XTB_BMP_DIB *dib, void *new_table);
void   xtb_bmp_dib_color_table_set_index(XTB_BMP_DIB *dib, size_t index, XTB_BMP_Color color);

/*******************************
 * Measure API
 *******************************/
size_t xtb_bmp_measure_color_table_count(int bits_per_pixel);
size_t xtb_bmp_measure_color_table_size_bytes(int bits_per_pixel);
size_t xtb_bmp_measure_bitmap_stride(int bpp, int width);
size_t xtb_bmp_measure_pixel_data_size_bytes(int bpp, int width, int height);
size_t xtb_bmp_measure_pixel_data_size_bytes_from_header(const XTB_BMP_Info_Header *info_header);

/*******************************
 * Write API
 *******************************/
void xtb_bmp_dib_write(const XTB_BMP_DIB *dib, const char *filepath);

// Maybe add managed and unmanaged versions

#ifdef __cplusplus
}
#endif

#endif // _XTB_BMP_H_
