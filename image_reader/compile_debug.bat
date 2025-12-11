mkdir build_debug
cd ./build_debug
cmake -G "Ninja" -DCMAKE_BUILD_TYPE=Debug ../ && ninja

pause