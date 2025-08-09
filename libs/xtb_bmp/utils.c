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
