cd deepfortran
call compile.bat
cd ..
powershell -Command "Start-BitsTransfer -Source https://github.com/opencv/opencv/releases/download/4.13.0/opencv-4.13.0-windows.exe -Destination opencv.exe"
opencv.exe -oopencv -y

cmake . -DCMAKE_TOOLCHAIN_FILE=${{ github.workspace }}\vcpkg\scripts\buildsystems\vcpkg.cmake  -DVCPKG_TARGET_TRIPLET=x64-windows
cmake --build . --config Release
