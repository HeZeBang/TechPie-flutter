# CMake for the eCard bind packet reader (libecardbind_reader.so).
#
# hvigor does NOT run this file. The .so is built on a developer machine by
# ohos/scripts/build-ecardbind-reader.sh and committed under
# ohos/entry/libs/arm64-v8a/, so the release image needs no C++ toolchain (see
# CLAUDE.md -> OHOS-specific gotchas). The digest below is what keeps that
# committed artifact honest: it is embedded in the .so at compile time and
# recomputed from the source tree by test/ecard_bind_reader_artifact_test.dart.
cmake_minimum_required(VERSION 3.10)
project(ecardbind_reader)

set(CMAKE_CXX_STANDARD 17)

add_library(ecardbind_reader SHARED ecardbind_reader.cpp)

# NAPI is provided by the OHOS NDK.
target_link_libraries(ecardbind_reader PUBLIC
    libace_napi.z.so
)

# Every file that can change the artifact, in one digest. The recipe is a line
# per file — "<path relative to this directory> <sha256>" — over the files of
# this directory, path-sorted, minus types/ (those are the ArkTS-facing
# declarations, not compiled here). CMakeLists.txt is included, so adding a
# source invalidates the digest too.
#
# Two implementations of that recipe exist (this one and the Dart test's).
# They are meant to agree; the test failing is how a disagreement is noticed.
file(GLOB_RECURSE ECARDBIND_SOURCES
    LIST_DIRECTORIES false
    RELATIVE "${CMAKE_CURRENT_SOURCE_DIR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/*")
list(FILTER ECARDBIND_SOURCES EXCLUDE REGEX "^types/")
list(SORT ECARDBIND_SOURCES)

set(ECARDBIND_SOURCE_LINES "")
foreach(source IN LISTS ECARDBIND_SOURCES)
  file(SHA256 "${CMAKE_CURRENT_SOURCE_DIR}/${source}" source_hash)
  string(APPEND ECARDBIND_SOURCE_LINES "${source} ${source_hash}\n")
endforeach()
string(SHA256 ECARDBIND_SOURCE_SHA256 "${ECARDBIND_SOURCE_LINES}")

target_compile_definitions(ecardbind_reader PRIVATE
    ECARDBIND_SOURCE_SHA256="${ECARDBIND_SOURCE_SHA256}")
message(STATUS "ecardbind_reader source digest ${ECARDBIND_SOURCE_SHA256}")
