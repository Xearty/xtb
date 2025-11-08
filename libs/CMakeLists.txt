
option(XTB_BUILD_CORE "Build the core module" ON)
option(XTB_BUILD_ANSI "Build the ansi module" ON)
option(XTB_BUILD_OS "Build the os module" ON)
option(XTB_BUILD_JSON "Build the json module" ON)
option(XTB_BUILD_BMP "Build the bmp module" ON)
option(XTB_BUILD_XTBM "Build the math module" ON)
option(XTB_BUILD_OGL "Build the opengl module" ON)

if(XTB_BUILD_CORE)
    add_subdirectory(xtb_core)
endif()

if(XTB_BUILD_ANSI)
    add_subdirectory(xtb_ansi)
endif()

if(XTB_BUILD_OS)
add_subdirectory(xtb_os)
endif()

if(XTB_BUILD_JSON)
    add_subdirectory(xtb_json)
endif()

if(XTB_BUILD_BMP)
    add_subdirectory(xtb_bmp)
endif()

if(XTB_BUILD_XTBM)
    add_subdirectory(xtbm)
endif()

if(XTB_BUILD_OGL)
    add_subdirectory(xtb_ogl)
endif()
