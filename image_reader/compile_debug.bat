mkdir build-debug
cd ./build-debug
cmake -G "Ninja" -DCMAKE_BUILD_TYPE=Debug ../ && ninja

pause