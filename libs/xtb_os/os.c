#include "os.h"

#include <stdio.h>
#include <stdlib.h>

static char *xtb_os_read_entire_file(const char *filepath, const char *mode)
{
    FILE *file = fopen(filepath, mode);
    if (!file)
    {
        return NULL;
    }

    fseek(file, 0, SEEK_END);
    size_t filesize = ftell(file);
    rewind(file);
    char *buffer = (char *)malloc(filesize + 1);

    size_t read = fread(buffer, sizeof(char), filesize, file);
    if (read != filesize)
    {
        fclose(file);
        free(buffer);
        return NULL;
    }

    fclose(file);
    buffer[read] = 0;

    return buffer;
}

char *xtb_os_read_entire_text_file(const char *filepath)
{
    return xtb_os_read_entire_file(filepath, "r");
}

char *xtb_os_read_entire_binary_file(const char *filepath)
{
    return xtb_os_read_entire_file(filepath, "rb");
}
