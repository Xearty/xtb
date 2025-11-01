#include <xtb_core/core.h>
#include <xtb_os/os.h>
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char **argv)
{
    xtb_init(argc, argv);

    char *content = xtb_os_read_entire_file("./CMakeLists.txt", NULL);
    if (content != NULL)
    {
        puts(content);
    }
    free(content);

    return 0;
}
