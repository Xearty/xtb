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

    char buffer[] = "Tova e text";
    int bytes_written = xtb_os_write_entire_file("./test2", buffer, sizeof(buffer) - 1);
    printf("bytes_written = %d\n", bytes_written);

    return 0;
}
