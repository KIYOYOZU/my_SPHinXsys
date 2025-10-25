cmake_minimum_required(VERSION 3.13)
STRING(REGEX REPLACE ".*/(.*)" "\\1" CURRENT_FOLDER ${CMAKE_CURRENT_SOURCE_DIR})
PROJECT("${CURRENT_FOLDER}")

include(FetchContent)
FetchContent_Declare(
  googletest
  URL https://gitee.com/mirrors/googletest/repository/archive/v1.14.0.zip
)
set(gtest_force_shared_crt ON CACHE BOOL "" FORCE)
FetchContent_MakeAvailable(googletest)
include(GoogleTest)

set(LIBRARY_OUTPUT_PATH ${PROJECT_BINARY_DIR}/lib)
set(EXECUTABLE_OUTPUT_PATH "${PROJECT_BINARY_DIR}/bin/")
set(BUILD_INPUT_PATH "${EXECUTABLE_OUTPUT_PATH}/input")
set(BUILD_RELOAD_PATH "${EXECUTABLE_OUTPUT_PATH}/reload")

file(MAKE_DIRECTORY ${BUILD_INPUT_PATH})

add_executable(${PROJECT_NAME})
aux_source_directory(. DIR_SRCS)
target_sources(${PROJECT_NAME} PRIVATE ${DIR_SRCS})
set_source_files_properties(
  ${CMAKE_CURRENT_SOURCE_DIR}/preprocess_data.m
  ${CMAKE_CURRENT_SOURCE_DIR}/visualize_flow.m
  ${CMAKE_CURRENT_SOURCE_DIR}/compare_umax_2d_vs_3d.m
  PROPERTIES HEADER_FILE_ONLY ON
)
target_link_libraries(${PROJECT_NAME} sphinxsys_3d)
set_target_properties(${PROJECT_NAME} PROPERTIES VS_DEBUGGER_WORKING_DIRECTORY "${EXECUTABLE_OUTPUT_PATH}")

add_test(NAME ${PROJECT_NAME}
    COMMAND ${PROJECT_NAME}
    WORKING_DIRECTORY ${EXECUTABLE_OUTPUT_PATH})

gtest_discover_tests(${PROJECT_NAME} WORKING_DIRECTORY ${EXECUTABLE_OUTPUT_PATH})
