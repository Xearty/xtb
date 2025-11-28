#include <xtb_core/arena.h>
#include <xtb_core/thread_context.h>

#include <xtb_bmp/bmp.h>

#include <xtbm/xtbm.h>
#include <xtb_os/os.h>
#include <xtb_core/core.h>

#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <assert.h>
#include <raylib.h>

#include "window_state.c"
#include "rect_selection.c"
#include "filters.c"

void
render_bitmap(BMP_Bitmap bitmap, const RectangleSelections* selections)
{
    static Rainbow_State rainbow_state;
    static bool initialized = false;
    if (!initialized)
    {
        initialized = true;
        rainbow_state = create_rainbow_state(0.25f, 0.32f);
    }

    for (int h = 0; h < bitmap.height; ++h)
    {
        for (int w = 0; w < bitmap.width; ++w)
        {
            int index = h * bitmap.width + w;
            BMP_Color color = bitmap.pixel_data[index];

            if (is_inside_selection(selections, w, h))
            {
                color = layer_filter_negative(color);
                color = layer_filter_rainbow(color, 1, rainbow_state);
            }

            Color raylib_color = (Color){ color.r, color.g, color.b, 255 };
            DrawPixel(w, h, raylib_color);
        }
    }

    update_rainbow_state(&rainbow_state);
}

void
setup_window_for_bmp(BMP_Bitmap *bitmap, const char *path)
{
    bmp_bitmap_gdealloc(bitmap);

    printf("Loading %s...\n", path);

    // Load bitmap
    #if 1
    String content = os_read_entire_file(allocator_get_heap(), cstr(path));

    #ifdef USE_DIB
    BMP_DIB dib = bmp_dib_load_galloc(result.content);
    bmp_dib_write(&dib, "test_write.bmp");
    *bitmap = bmp_bitmap_create_from_dib_galloc(&dib);
    #else
    *bitmap = bmp_bitmap_load_galloc((u8*)content.str);
    #endif

    str_free(bmp_get_global_allocator(), content);
    #else
    BMP_IO_Stream stream = libc_file_read_binary_stream_open(path);
    /* BMP_IO_Stream stream = libc_file_read_text_stream_open(path); */
    *bitmap = bmp_bitmap_load_from_stream(stream, malloc_allocator());
    libc_file_read_stream_close(stream);
    #endif

    printf("Loaded %s\n", path);

    /* SetWindowSize(bitmap->width, bitmap->height); */

    if (IsWindowReady())
    {
        CloseWindow();
    }

    InitWindow(bitmap->width, bitmap->height, path);

    Vector2 scale = GetWindowScaleDPI();
    Vector2 virtual_screen_size = {bitmap->width * scale.x, bitmap->height * scale.y};
    window_state = create_window_state((Vector2){bitmap->width, bitmap->height},
                                       virtual_screen_size);
}

void
bmp_directory_viewer_app(const char *dirpath)
{
    RectangleSelections selections = {};

    if (!DirectoryExists(dirpath))
    {
        printf("Directory doesn't exist\n");
        exit(1);
    }

    FilePathList path_list = LoadDirectoryFiles(dirpath);
    int current_file_idx = 0;

    if (path_list.count == 0)
    {
        printf("Directory is empty. Nothing to show\n");
        exit(2);
    }

    BMP_Bitmap bitmap = {};
    setup_window_for_bmp(&bitmap, path_list.paths[0]);

    while (!WindowShouldClose())
    {
        if (IsKeyPressed(KEY_RIGHT) && current_file_idx < path_list.count - 1)
        {
            current_file_idx += 1;
            const char *filepath = path_list.paths[current_file_idx];
            setup_window_for_bmp(&bitmap, filepath);
        }
        else if (IsKeyPressed(KEY_LEFT) && current_file_idx > 0)
        {
            current_file_idx -= 1;
            const char *filepath = path_list.paths[current_file_idx];
            setup_window_for_bmp(&bitmap, filepath);
        }
        else if (IsFileDropped())
        {
            FilePathList dropped_files = LoadDroppedFiles();
            const char *dropped_file = dropped_files.paths[0];
            setup_window_for_bmp(&bitmap, dropped_file);

            UnloadDroppedFiles(dropped_files);
        }

        update_rect_selections(&selections);

        BeginDrawing();
        ClearBackground(BLACK);
        render_bitmap(bitmap, &selections);
        if (selections.is_creating_rect)
        {
            render_selection_visual_rect(&selections);
        }
        EndDrawing();
    }
    CloseWindow();
    UnloadDirectoryFiles(path_list);
    bmp_bitmap_gdealloc(&bitmap);
}

void
bmp_single_file_viewer_app(int argc, char **argv, const char *filepath)
{
    if (!filepath && argc == 2)
    {
        filepath = argv[1];
    }

    RectangleSelections selections = {};

    // Broken
    /* BMP_Bitmap bm = {}; */
    /* InitWindow(bm.width, bm.height, "BMP Loader"); */
    /* setup_bmp_for_drawing_into_window(&bm, filepath); */

    // Working
    BMP_Bitmap bitmap = {};
    if (filepath)
    {
        setup_window_for_bmp(&bitmap, filepath);
    }
    else
    {
        InitWindow(800, 800, "BMP Loader: Drop your image");
    }

    while (!WindowShouldClose())
    {
        update_mouse_position(&window_state);

        if (IsFileDropped())
        {
            FilePathList dropped_files = LoadDroppedFiles();
            const char *dropped_file = dropped_files.paths[0];
            setup_window_for_bmp(&bitmap, dropped_file);

            UnloadDroppedFiles(dropped_files);
        }

        update_rect_selections(&selections);

        BeginDrawing();
        ClearBackground(BLACK);
        render_bitmap(bitmap, &selections);
        if (selections.is_creating_rect)
        {
            render_selection_visual_rect(&selections);
        }
        EndDrawing();
    }
    CloseWindow();
    bmp_bitmap_gdealloc(&bitmap);
}

int main(int argc, char **argv)
{
    xtb_init(argc, argv);
    ThreadContext tctx;
    tctx_init_and_equip(&tctx);

    SetTraceLogLevel(LOG_ERROR);

    bmp_set_global_allocator(allocator_get_heap());

    SetConfigFlags(FLAG_VSYNC_HINT | FLAG_WINDOW_HIGHDPI);
    EnableEventWaiting();

    // bmp_single_file_viewer_app(argc, argv, NULL);
    bmp_directory_viewer_app("./apps/bmp_test/tests/valid");

    tctx_release();

    return 0;
}

