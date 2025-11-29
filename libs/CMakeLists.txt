option(XTB_BUILD_CORE "Build the core module" ON)
option(XTB_BUILD_ANSI "Build the ansi module" ON)
option(XTB_BUILD_OS "Build the os module" ON)
option(XTB_BUILD_BMP "Build the bmp module" ON)
option(XTB_BUILD_M "Build the xtbm module" ON)
option(XTB_BUILD_JSON "Build the json module" ON)
option(XTB_BUILD_OGL "Build the ogl module" ON)
option(XTB_BUILD_WINDOW "Build the window module" ON)
option(XTB_BUILD_RENDERER "Build the renderer module" ON)

if(XTB_BUILD_CORE)
    add_subdirectory(xtb_core)
endif()

if(XTB_BUILD_ANSI)
    add_subdirectory(xtb_ansi)
endif()

if(XTB_BUILD_OS)
    add_subdirectory(xtb_os)
endif()

if(XTB_BUILD_BMP)
    add_subdirectory(xtb_bmp)
endif()

if(XTB_BUILD_M)
    add_subdirectory(xtbm)
endif()

if(XTB_BUILD_JSON)
    add_subdirectory(xtb_json)
endif()

if(XTB_BUILD_OGL)
    add_subdirectory(xtb_ogl)
endif()

if(XTB_BUILD_WINDOW)
    add_subdirectory(xtb_window)
endif()

if(XTB_BUILD_RENDERER)
    add_subdirectory(xtb_renderer)
endif()
