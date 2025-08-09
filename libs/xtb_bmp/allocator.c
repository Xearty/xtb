XTB_Allocator xtb_bmp_global_allocator;

const XTB_Allocator *
xtb_bmp_get_global_allocator()
{
    return &xtb_bmp_global_allocator;
}

XTB_BMP_Bitmap
xtb_bmp_bitmap_load_galloc(const XTB_Byte *bytes)
{
    return xtb_bmp_bitmap_load_alloc(xtb_bmp_global_allocator, bytes);
}
