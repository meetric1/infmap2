cmake_minimum_required(VERSION 4.0)

set(PROJECT_NAME imagereader)
project(${PROJECT_NAME})

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CONFIGURATION_TYPES Release Debug)

add_subdirectory(libs/gmod-module-base/include)

file(GLOB_RECURSE SOURCES CONFIGURE_DEPENDS "src/*.cpp")
add_library(${PROJECT_NAME} SHARED ${SOURCES})

target_include_directories(${PROJECT_NAME} PRIVATE
	libs/gmod-module-base/include
	libs/stb
	src
)

target_link_libraries(${PROJECT_NAME} PRIVATE
	gmod-module-base
)