#include <xtb_core/core.h>
#include <xtb_os/os.h>
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char **argv)
{
    xtb_init(argc, argv);

    const char *in_file = "./CMakeLists.txt";
    const char *out_file = "./test2.txt";

    // char *content = xtb_os_read_entire_file(in_file, NULL);
    // if (content != NULL)
    // {
    //     puts(content);
    // }
    // free(content);

    // char buffer[] = "Tova e text";
    // int bytes_written = xtb_os_write_entire_file(out_file, buffer, sizeof(buffer) - 1);
    // printf("bytes_written = %d\n", bytes_written);

    // if (xtb_os_delete_file(out_file))
    // {
    //     puts("Deleted file successfully");
    // }

    if (xtb_os_delete_directory("libs2"))
    {
        puts("Deleted");
    }
    else
    {
        puts("Could not delete");
    }

    return 0;

    if (xtb_os_move_file("edno", "dve"))
    {
        puts("File moved successfully");
    }
    else
    {
        puts("File couldn't be moved");
    }

    return 0;

    if (xtb_os_file_exists(out_file))
    {
        puts("File exists");
    }
    else
    {
        puts("File doesn't exists");
    }

    if (xtb_os_file_has_read_permission(out_file))
    {
        puts("File has read permission");
    }
    else
    {
        puts("File doesn't have read permission");
    }

    if (xtb_os_file_has_write_permission(out_file))
    {
        puts("File has write permission");
    }
    else
    {
        puts("File doesn't have write permission");
    }

    if (xtb_os_file_has_execute_permission(out_file))
    {
        puts("File has execute permission");
    }
    else
    {
        puts("File doesn't have execute permission");
    }

    const char *path2 = "test3";

    if (xtb_os_is_regular_file(path2))
    {
        puts("File is regular");
    }

    if (xtb_os_is_directory(path2))
    {
        puts("File is directory");
    }

    if (xtb_os_is_symbolic_link(path2))
    {
        puts("File is symlink");
    }

    if (xtb_os_is_regular_file_nofollow(path2))
    {
        puts("File is regular file no follow");
    }

    if (xtb_os_is_directory_nofollow(path2))
    {
        puts("File is regular file no follow");
    }

    printf("file type: %d\n", xtb_os_get_file_type_nofollow(path2));
    printf("file type follow: %d\n", xtb_os_get_file_type(path2));

    char *real_path = xtb_os_real_path(path2);
    printf("real path: %s\n", real_path);

    return 0;
}
