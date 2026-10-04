# CMake for the aTrust VPN extension shim (libgeektrust_vpn.so).
#
# hvigor does NOT run this file. The shim is built on a developer machine by
# ohos/scripts/build-geektrust-vpn.sh and committed under
# ohos/entry/libs/arm64-v8a/, so the release image needs no C++ toolchain (see
# CLAUDE.md -> OHOS-specific gotchas). The digest below is what keeps that
# committed artifact honest: it is embedded in the .so at compile time and
# recomputed from this directory by test/atrust/geektrust_vpn_artifact_test.dart.
cmake_minimum_required(VERSION 3.10)
project(geektrust_vpn)

set(CMAKE_CXX_STANDARD 17)

add_library(geektrust_vpn SHARED geektrust_vpn.cpp)

# NAPI is provided by the OHOS NDK; dlopen/dlsym come from libc.
target_link_libraries(geektrust_vpn PUBLIC libace_napi.z.so)

# Every file that can change the artifact, in one digest. The recipe is a line
# per file — "<path relative to this directory> <sha256>" — over the files of
# this directory, path-sorted, minus types/ (those are the ArkTS-facing
# declarations, not compiled here). CMakeLists.txt is included, so adding a
# source invalidates the digest too.
file(GLOB_RECURSE GEEKTRUST_VPN_SOURCES
    LIST_DIRECTORIES false
    RELATIVE "${CMAKE_CURRENT_SOURCE_DIR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/*")
list(FILTER GEEKTRUST_VPN_SOURCES EXCLUDE REGEX "^types/")
list(SORT GEEKTRUST_VPN_SOURCES)

set(GEEKTRUST_VPN_SOURCE_LINES "")
foreach(source IN LISTS GEEKTRUST_VPN_SOURCES)
  file(SHA256 "${CMAKE_CURRENT_SOURCE_DIR}/${source}" source_hash)
  string(APPEND GEEKTRUST_VPN_SOURCE_LINES "${source} ${source_hash}\n")
endforeach()
string(SHA256 GEEKTRUST_VPN_SOURCE_SHA256 "${GEEKTRUST_VPN_SOURCE_LINES}")

target_compile_definitions(geektrust_vpn PRIVATE
    GEEKTRUST_VPN_SOURCE_SHA256="${GEEKTRUST_VPN_SOURCE_SHA256}")
message(STATUS "geektrust_vpn source digest ${GEEKTRUST_VPN_SOURCE_SHA256}")
