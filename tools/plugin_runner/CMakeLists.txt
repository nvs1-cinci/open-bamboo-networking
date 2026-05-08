cmake_minimum_required(VERSION 3.20)
project(plugin_runner LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE RelWithDebInfo CACHE STRING "" FORCE)
endif()

# The whole point of this binary is to dlopen() a stock libbambu_networking.so
# whose ABI corresponds to a specific BambuStudio release. PrintParams is
# passed *by value* across the ABI boundary and grew with versions, so the
# binary must be compiled against the matching layout. The wrapper script
# (tools/plugin_runner.sh) picks the right OBN_ABI_VERSION_HEX from the
# requested plugin and rebuilds before each run.
set(OBN_ABI_VERSION_HEX "" CACHE STRING
    "Hex literal for ABI_VERSION (e.g. 0x020503). Required.")
if(NOT OBN_ABI_VERSION_HEX)
    message(FATAL_ERROR
        "OBN_ABI_VERSION_HEX is required. Pass -DOBN_ABI_VERSION_HEX=0xMMmmpp "
        "(matches the first three components of the target plugin's version, "
        "e.g. 0x020503 for plugin 02.05.03.xx).")
endif()

find_package(PkgConfig REQUIRED)
pkg_check_modules(CURL REQUIRED IMPORTED_TARGET libcurl)
pkg_check_modules(MINIZIP REQUIRED IMPORTED_TARGET minizip)
find_package(OpenSSL COMPONENTS SSL REQUIRED)

set(REPO_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../..")

add_executable(plugin_runner
    main.cpp
    plugin_loader.cpp
    print_params_io.cpp
    plugin_downloader.cpp
)

target_include_directories(plugin_runner PRIVATE
    ${REPO_ROOT}/include
    ${CMAKE_CURRENT_SOURCE_DIR}
)

target_compile_definitions(plugin_runner PRIVATE
    ABI_VERSION=${OBN_ABI_VERSION_HEX}
)

target_compile_options(plugin_runner PRIVATE
    -Wall -Wextra -Wno-unused-parameter
)

target_link_libraries(plugin_runner PRIVATE
    PkgConfig::CURL
    PkgConfig::MINIZIP
    OpenSSL::SSL
    pthread
    dl
)

message(STATUS "plugin_runner: ABI_VERSION=${OBN_ABI_VERSION_HEX}")
