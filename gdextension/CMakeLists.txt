cmake_minimum_required(VERSION 3.20)

project(chess_engine
    VERSION 0.1.0
    LANGUAGES CXX)

# Objective-C++ only exists on Apple toolchains; enabling it globally breaks
# Android/Linux/Windows cross-builds. GPLATFORM arrives via -D before this.
if(NOT DEFINED GPLATFORM OR GPLATFORM STREQUAL "macos" OR GPLATFORM STREQUAL "ios")
    enable_language(OBJCXX)
endif()

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

if(NOT CMAKE_CONFIGURATION_TYPES AND NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release CACHE STRING "Build type" FORCE)
endif()

# The .gdextension config file references binaries under bin/<filename>. The
# filename is what determines the loadable extension; CMake's automatic
# naming doesn't always match, so we set it explicitly per target later.
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin)
set(CMAKE_LIBRARY_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin)

# Build target — "template_release" by default. Override with -DGTARGET=...
set(GTARGET "template_release" CACHE STRING "godot-cpp target (template_release/template_debug/editor)")
set(GPLATFORM "macos"  CACHE STRING "Platform (macos/ios/android/linux/windows)")
set(GARCH     "universal" CACHE STRING "Arch (universal/arm64/arm32/x86_64)")

# ─── Godot-cpp (downloaded by the user) ───────────────────────────────────────
set(GODOT_CPP_PATH "${CMAKE_SOURCE_DIR}/godot-cpp" CACHE PATH "Path to godot-cpp")
set(GODOT_CPP_BIN  "${GODOT_CPP_PATH}/bin" CACHE PATH "Path to godot-cpp build dir")
set(GODOT_CPP_LIB  "${GODOT_CPP_BIN}/libgodot-cpp.${GPLATFORM}.${GTARGET}.${GARCH}.a")

if(NOT EXISTS "${GODOT_CPP_LIB}")
    message(FATAL_ERROR
        "godot-cpp library not found at ${GODOT_CPP_LIB}.\n"
        "Build it with:\n"
        "  cd ${GODOT_CPP_PATH} && scons platform=${GPLATFORM} arch=${GARCH} target=${GTARGET} -j$(nproc)\n"
        "Then re-run this build.")
endif()

# ─── Stockfish (vendored, exact version) ─────────────────────────────────────
set(STOCKFISH_PATH "${CMAKE_SOURCE_DIR}/stockfish" CACHE PATH "Path to Stockfish source")

# Stockfish is header-light — single big engine.h plus the src/*.cpp files.
# We do NOT include src/main.cpp (it has main() and would conflict with the
# GDExtension's entry point).
set(SF_SOURCES
    ${STOCKFISH_PATH}/src/benchmark.cpp
    ${STOCKFISH_PATH}/src/bitboard.cpp
    ${STOCKFISH_PATH}/src/engine.cpp
    ${STOCKFISH_PATH}/src/evaluate.cpp
    ${STOCKFISH_PATH}/src/memory.cpp
    ${STOCKFISH_PATH}/src/misc.cpp
    ${STOCKFISH_PATH}/src/movegen.cpp
    ${STOCKFISH_PATH}/src/movepick.cpp
    ${STOCKFISH_PATH}/src/position.cpp
    ${STOCKFISH_PATH}/src/score.cpp
    ${STOCKFISH_PATH}/src/search.cpp
    ${STOCKFISH_PATH}/src/syzygy/tbprobe.cpp
    ${STOCKFISH_PATH}/src/thread.cpp
    ${STOCKFISH_PATH}/src/timeman.cpp
    ${STOCKFISH_PATH}/src/tt.cpp
    ${STOCKFISH_PATH}/src/tune.cpp
    ${STOCKFISH_PATH}/src/uci.cpp
    ${STOCKFISH_PATH}/src/ucioption.cpp
    ${STOCKFISH_PATH}/src/nnue/nnue_accumulator.cpp
    ${STOCKFISH_PATH}/src/nnue/nnue_misc.cpp
    ${STOCKFISH_PATH}/src/nnue/network.cpp
    ${STOCKFISH_PATH}/src/nnue/features/half_ka_v2_hm.cpp
    ${STOCKFISH_PATH}/src/nnue/features/full_threats.cpp
)

set(ENGINE_SOURCES
    ${CMAKE_SOURCE_DIR}/src/chess_engine.cpp
)

if(GPLATFORM STREQUAL "ios")
    list(APPEND ENGINE_SOURCES
        ${CMAKE_SOURCE_DIR}/src/speech_input_ios.mm
        ${CMAKE_SOURCE_DIR}/src/game_center_apple.mm)
    set_source_files_properties(
        ${CMAKE_SOURCE_DIR}/src/speech_input_ios.mm
        ${CMAKE_SOURCE_DIR}/src/game_center_apple.mm PROPERTIES
        COMPILE_FLAGS "-fobjc-arc"
    )
elseif(GPLATFORM STREQUAL "macos")
    list(APPEND ENGINE_SOURCES
        ${CMAKE_SOURCE_DIR}/src/speech_input_macos.mm
        ${CMAKE_SOURCE_DIR}/src/game_center_apple.mm)
    set_source_files_properties(
        ${CMAKE_SOURCE_DIR}/src/speech_input_macos.mm
        ${CMAKE_SOURCE_DIR}/src/game_center_apple.mm PROPERTIES
        COMPILE_FLAGS "-fobjc-arc"
    )
else()
    list(APPEND ENGINE_SOURCES
        ${CMAKE_SOURCE_DIR}/src/speech_input_stub.cpp
        ${CMAKE_SOURCE_DIR}/src/game_center_stub.cpp)
endif()

add_library(chess_engine SHARED
    ${ENGINE_SOURCES}
    ${SF_SOURCES}
)

if(NOT CMAKE_CROSSCOMPILING)
add_executable(stockfish_smoke
    ${CMAKE_SOURCE_DIR}/src/stockfish_smoke.cpp
    ${SF_SOURCES}
)
endif()

target_include_directories(chess_engine PRIVATE
    ${STOCKFISH_PATH}/src
    ${GODOT_CPP_PATH}/include
    ${GODOT_CPP_PATH}/gen/include
    ${GODOT_CPP_PATH}/gdextension
)

target_link_libraries(chess_engine PRIVATE
    ${GODOT_CPP_LIB}
)

target_compile_definitions(chess_engine PRIVATE
    NOBKMARK=1              # no benchmark bloat
    USE_PTHREADS
)

if(NOT GARCH STREQUAL "arm32" AND NOT GARCH STREQUAL "x86_32")
    target_compile_definitions(chess_engine PRIVATE IS_64BIT=1)
endif()

if(GARCH STREQUAL "arm64" OR GARCH STREQUAL "arm32")
    target_compile_definitions(chess_engine PRIVATE USE_NEON=8)
endif()

if(GARCH STREQUAL "arm64" OR GARCH STREQUAL "arm32" OR GARCH STREQUAL "x86_64")
    target_compile_definitions(chess_engine PRIVATE USE_POPCNT)
endif()

# Stockfish uses platform-specific intrinsics. Pull in the right ones per OS.
if(APPLE)
    target_compile_options(chess_engine PRIVATE -Wno-pedantic -Wno-unused-parameter)
    target_link_libraries(chess_engine PRIVATE pthread)
elseif(MSVC)
    target_compile_options(chess_engine PRIVATE /w)
    target_link_libraries(chess_engine PRIVATE ws2_32 wsock32)
elseif(WIN32)
    # MinGW (native or cross). Static runtime so the DLL is self-contained.
    target_compile_options(chess_engine PRIVATE -Wno-pedantic -Wno-unused-parameter)
    target_link_libraries(chess_engine PRIVATE ws2_32 wsock32)
    target_link_options(chess_engine PRIVATE -static -static-libgcc -static-libstdc++)
else()
    target_compile_options(chess_engine PRIVATE -Wno-pedantic -Wno-unused-parameter)
endif()

if(NOT CMAKE_CROSSCOMPILING)
    target_include_directories(stockfish_smoke PRIVATE ${STOCKFISH_PATH}/src)
    target_compile_definitions(stockfish_smoke PRIVATE NOBKMARK=1 USE_PTHREADS)
    if(NOT GARCH STREQUAL "arm32" AND NOT GARCH STREQUAL "x86_32")
        target_compile_definitions(stockfish_smoke PRIVATE IS_64BIT=1)
    endif()
    if(GARCH STREQUAL "arm64" OR GARCH STREQUAL "arm32")
        target_compile_definitions(stockfish_smoke PRIVATE USE_NEON=8)
    endif()
    if(GARCH STREQUAL "arm64" OR GARCH STREQUAL "arm32" OR GARCH STREQUAL "x86_64")
        target_compile_definitions(stockfish_smoke PRIVATE USE_POPCNT)
    endif()
    if(APPLE)
        target_compile_options(stockfish_smoke PRIVATE -Wno-pedantic -Wno-unused-parameter)
        target_link_libraries(stockfish_smoke PRIVATE pthread)
    elseif(MSVC)
        target_compile_options(stockfish_smoke PRIVATE /w)
        target_link_libraries(stockfish_smoke PRIVATE ws2_32 wsock32)
    elseif(WIN32)
        target_compile_options(stockfish_smoke PRIVATE -Wno-pedantic -Wno-unused-parameter)
        target_link_libraries(stockfish_smoke PRIVATE ws2_32 wsock32)
    else()
        target_compile_options(stockfish_smoke PRIVATE -Wno-pedantic -Wno-unused-parameter)
    endif()
endif()

set_target_properties(chess_engine PROPERTIES
    OUTPUT_NAME "chess_engine.${GPLATFORM}.${GTARGET}.${GARCH}"
)

# On macOS / iOS we want a .dylib suffix; on Linux/Android a .so; on Windows a .dll.
if(WIN32)
    set_target_properties(chess_engine PROPERTIES PREFIX "" SUFFIX ".dll")
elseif(APPLE)
    set_target_properties(chess_engine PROPERTIES PREFIX "lib")
    set_target_properties(chess_engine PROPERTIES SUFFIX ".dylib")
else()
    set_target_properties(chess_engine PROPERTIES PREFIX "lib")
    set_target_properties(chess_engine PROPERTIES SUFFIX ".so")
endif()

if(GPLATFORM STREQUAL "ios")
    set_target_properties(chess_engine PROPERTIES
        FRAMEWORK TRUE
        MACOSX_FRAMEWORK_IDENTIFIER "com.kevincardona.chess.chess-engine"
    )
    target_link_libraries(chess_engine PRIVATE "-framework Speech" "-framework AVFoundation" "-framework GameKit" "-framework UIKit")
elseif(GPLATFORM STREQUAL "macos")
    target_link_libraries(chess_engine PRIVATE "-framework Speech" "-framework AVFoundation" "-framework Foundation" "-framework GameKit" "-framework AppKit" "-lobjc")
endif()

if(NOT GPLATFORM STREQUAL "ios")
    add_custom_command(TARGET chess_engine POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E make_directory ${CMAKE_SOURCE_DIR}/bin
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
            $<TARGET_FILE:chess_engine>
            ${CMAKE_SOURCE_DIR}/bin/$<TARGET_FILE_NAME:chess_engine>
    )
endif()
