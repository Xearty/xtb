#include <stdbool.h>
#include <unistd.h>

bool xtb_os_file_exists(const char *filepath)
{
    return access(filepath, F_OK) == 0;
}

bool xtb_os_file_has_read_permission(const char *filepath)
{
    return access(filepath, R_OK) == 0;
}

bool xtb_os_file_has_write_permission(const char *filepath)
{
    return access(filepath, W_OK) == 0;
}

bool xtb_os_file_has_execute_permission(const char *filepath)
{
    return access(filepath, X_OK) == 0;
}

