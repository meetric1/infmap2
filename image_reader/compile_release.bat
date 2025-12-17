mkdir build-release
cd ./build-release
cmake -G "Ninja" -DCMAKE_BUILD_TYPE=Release ../ && ninja

pause