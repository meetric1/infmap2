mkdir build-release
cd ./build-release
cmake -G "Visual Studio 17 2022" -DCMAKE_BUILD_TYPE=Release ../ && ninja

pause