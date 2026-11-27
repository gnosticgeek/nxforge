# NXForge's Dolphin bridge (wii/README.md), added to Dolphin's own CMake build by scripts/wii_engine.py.
add_library(nxdolphin SHARED nxdolphin.mm)
target_include_directories(nxdolphin PRIVATE "${DOLPHIN_SOURCE}/Source/Core")
target_link_libraries(nxdolphin PRIVATE core uicommon "-framework AppKit")
target_compile_options(nxdolphin PRIVATE -fobjc-arc)
set_target_properties(nxdolphin PROPERTIES PREFIX "" INSTALL_NAME_DIR "@rpath")
set_target_properties(nxdolphin PROPERTIES CXX_STANDARD 23 OBJCXX_STANDARD 23)
