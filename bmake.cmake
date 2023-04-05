
# bmake.cmake mimics the behavior of bazel (https://bazel.build/) to
# simplify the usability of CMake.
#

option(WITH_TESTING "Compile Source Code with Unit Testing"   ON)
#option(WITH_PYTHON  "Compile Source Code with Python"         ON)

message(STATUS "WITH_TESTING=" ${WITH_TESTING})
#message(STATUS "WITH_PYTHON=" ${WITH_PYTHON})

get_filename_component(BAZEL_SOURCE_DIR ${CMAKE_CURRENT_LIST_DIR} DIRECTORY)
set(BAZEL_THIRD_PARTY_DIR ${BAZEL_SOURCE_DIR}/third-party)

include(color)
if(CMAKE_CROSSCOMPILING)
    include(host)
endif(CMAKE_CROSSCOMPILING)

include(compile)
include(merge_libs)

file(GLOB INCLUDE_CMAKE_LIST ${PROJECT_SOURCE_DIR}/cpp3rdlib/*/*.cmake)
foreach(sub_file ${INCLUDE_CMAKE_LIST})
    file(RELATIVE_PATH relative_sub_file ${PROJECT_SOURCE_DIR} ${sub_file}) # 获取相对路径
    cmake_print_variables(relative_sub_file)
    include(${relative_sub_file})
endforeach()

macro(_build_target func_tag)
    set(_sources ${ARGN})

    # Given a variable containing a file list,
    # it will remove all the files wich basename
    # does not match the specified pattern.
    if(${CMAKE_VERSION} VERSION_LESS 3.6)
        foreach(src_file ${_sources})
            get_filename_component(base_name ${src_file} NAME)
            if(${base_name} MATCHES "\\.proto$")
                list(REMOVE_ITEM _sources "${src_file}")
            endif()
        endforeach()
    else(${CMAKE_VERSION} VERSION_LESS 3.6)
        list(FILTER _sources EXCLUDE REGEX "\\.proto$")
    endif(${CMAKE_VERSION} VERSION_LESS 3.6)

    if (${func_tag} STREQUAL "cc_lib")
        add_library(${_sources})
    elseif(${func_tag} STREQUAL "cc_bin")
        list(REMOVE_ITEM _sources STATIC SHARED)
        add_executable(${_sources})
    endif()
endmacro(_build_target)

function(cmake_library TARGET_NAME)
    set(options STATIC SHARED)
    set(oneValueArgs TAG)
    set(multiValueArgs SRCS DEPS)
    cmake_parse_arguments(cmake_library "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})
    if (cmake_library_SRCS)
        if (cmake_library_SHARED) # build *.so
            set(_lib_type SHARED)
        else(cmake_library_SHARED)
            set(_lib_type STATIC)
        endif(cmake_library_SHARED)
        _build_target(${cmake_library_TAG} ${TARGET_NAME} ${_lib_type} ${cmake_library_SRCS})
        if (cmake_library_DEPS)
            add_dependencies(${TARGET_NAME} ${cmake_library_DEPS})
            target_link_libraries(${TARGET_NAME} ${cmake_library_DEPS})
        endif(cmake_library_DEPS)
    else(cmake_library_SRCS)
        if (cmake_library_DEPS AND ${cmake_library_TAG} STREQUAL "cc_lib")
            merge_static_libs(${TARGET_NAME} ${cmake_library_DEPS})
        else()
            message(FATAL_ERROR "Please review the valid syntax: typing `make helps` in the Terminal"
                    "or visiting https://github.com/gangliao/bazel.cmake#cheat-sheet")
        endif()
    endif(cmake_library_SRCS)
endfunction(cmake_library)

macro(check_gtest)
    set(options STATIC SHARED)
    set(oneValueArgs TAG)
    set(multiValueArgs SRCS DEPS)
    cmake_parse_arguments(check_gtest "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

    set(gtest_deps DEPS gtest gtest_main)
    foreach(filename ${check_gtest_SRCS})
        file(STRINGS ${filename} output REGEX "(int|void)[ ]+main")
        if(output)
            list(REMOVE_ITEM gtest_deps gtest_main)
            break()
        endif(output)
    endforeach()

    set(${gtest_deps} ${gtest_deps} PARENT_SCOPE)
endmacro(check_gtest)

function(cc_library)
    cmake_library(${ARGV} TAG cc_lib)
endfunction(cc_library)

function(cc_binary)
    cmake_library(${ARGV} TAG cc_bin)
endfunction(cc_binary)

function(cc_test)
    check_gtest(${ARGV})
    cmake_library(${ARGV} TAG cc_bin ${gtest_deps})
    add_test(${ARGV0} ${ARGV0})
endfunction(cc_test)


function(proto_library)
    set(options STATIC SHARED)
    set(oneValueArgs TAG)
    set(multiValueArgs SRCS DEPS)
    cmake_parse_arguments(proto_library "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

    _protobuf_generate_cpp(proto_srcs proto_hdrs ${proto_library_SRCS})

    # including binary directory for generated headers (protobuf hdrs).
    include_directories(${CMAKE_CURRENT_BINARY_DIR})
    cmake_library(${ARGV} SRCS ${proto_srcs} ${proto_hdrs} DEPS protobuf TAG cc_lib)

endfunction(proto_library)

function(thrift_library)
    set(options STATIC SHARED)
    set(oneValueArgs TAG SRCS)
    set(multiValueArgs DEPS)
    cmake_parse_arguments(thrift_library "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

    thrift_gen_cpp(${thrift_library_SRCS} thrift_files thrift_inc_dir)

    # including binary directory for generated headers (protobuf hdrs).
    include_directories(${thrift_inc_dir})
    cmake_library(${ARGV} SRCS ${thrift_files} DEPS thrift TAG cc_lib)
endfunction(thrift_library)

function(robin_library)
    set(options STATIC SHARED)
    set(oneValueArgs IDL)
    set(multiValueArgs SRCS DEPS)
    cmake_parse_arguments(robin_library "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})
    get_filename_component(POSTFIX ${robin_library_IDL} EXT)
    get_filename_component(FILE_NAME ${robin_library_IDL} NAME_WLE)
    string(RANDOM LENGTH 5 random_str)

    if (${POSTFIX} STREQUAL ".proto")
        set(new_proto_lib "${FILE_NAME}_${random_str}_proto_lib")  # 将变量和字符串常量拼接起来
        proto_library(${new_proto_lib} SRCS ${robin_library_IDL})
        cc_library(${ARGV} SRCS ${ROBIN_SRC_FILES} DEPS arch_net_core arch_robin ${new_proto_lib})
    elseif(${POSTFIX} STREQUAL ".thrift")
        set(new_thrift_lib "${FILE_NAME}_${random_str}_thrift_lib")  # 将变量和字符串常量拼接起来
        thrift_library(${new_thrift_lib} SRCS ${robin_library_IDL})
        cc_library(${ARGV} SRCS ${ROBIN_SRC_FILES} DEPS arch_net_core arch_robin ${new_thrift_lib})
    else()
        message(FATAL_ERROR "Unknown IDL postfix: ${POSTFIX}, only support .proto and .thrift")
    endif()

endfunction(robin_library)

#
#function(brpc_library)
#    set(options STATIC SHARED)
#    set(oneValueArgs TAG)
#    set(multiValueArgs SRCS DEPS)
#    cmake_parse_arguments(brpc_library "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})
#
#    _protobuf_generate_cpp(proto_srcs proto_hdrs ${brpc_library_SRCS})
#
#    # including binary directory for generated headers (protobuf hdrs).
#    include_directories(${CMAKE_CURRENT_BINARY_DIR})
#
#    if(CMAKE_SYSTEM_NAME STREQUAL "Darwin")
#        include(CheckFunctionExists)
#        CHECK_FUNCTION_EXISTS(clock_gettime HAVE_CLOCK_GETTIME)
#        if(NOT HAVE_CLOCK_GETTIME)
#            set(DEFINE_CLOCK_GETTIME "-DNO_CLOCK_GETTIME_IN_MAC")
#        endif()
#    endif()
#
#    set(CMAKE_CPP_FLAGS "${DEFINE_CLOCK_GETTIME}")
#    set(CMAKE_CXX_FLAGS "${CMAKE_CPP_FLAGS} -DNDEBUG -O2 -D__const__=__unused__ -pipe -W -Wall -Wno-unused-parameter -fPIC -fno-omit-frame-pointer")
#
#    if(CMAKE_VERSION VERSION_LESS "3.1.3")
#        if(CMAKE_CXX_COMPILER_ID STREQUAL "GNU")
#            set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -std=c++11")
#        endif()
#        if(CMAKE_CXX_COMPILER_ID STREQUAL "Clang")
#            set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -std=c++11")
#        endif()
#    else()
#        set(CMAKE_CXX_STANDARD 11)
#        set(CMAKE_CXX_STANDARD_REQUIRED ON)
#    endif()
#
#
#    cmake_library(${ARGV} SRCS ${proto_srcs} ${proto_hdrs}
#            DEPS brpc protobuf gflags leveldb ssl crypto glog
#            TAG cc_lib)
#
#endfunction(brpc_library)
