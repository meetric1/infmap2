cmake_minimum_required(VERSION 4.0)

set(PROJECT_NAME imagereader)
project(${PROJECT_NAME})

set(CMAKE_CONFIGURATION_TYPES Release Debug)
set(CMAKE_CXX_STANDARD 17)

add_subdirectory(gmod-module-base/include)

#file(GLOB_RECURSE SOURCES CONFIGURE_DEPENDS "*.cpp")
add_library(${PROJECT_NAME} SHARED
	main.cpp
)

target_include_directories(${PROJECT_NAME} PRIVATE
    gmod-module-base/include
    stb
)

target_link_libraries(${PROJECT_NAME} PRIVATE
    gmod-module-base
)