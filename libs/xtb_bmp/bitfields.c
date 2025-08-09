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
