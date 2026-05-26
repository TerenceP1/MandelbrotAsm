cd deepfortran
call compile.bat
cd ..
powershell -Command "Start-BitsTransfer -Source https://github.com/opencv/opencv/releases/download/4.13.0/opencv-4.13.0-windows.exe -Destination opencv.exe"
opencv.exe -oopencv -y
vcpkg remove opencv:x64-windows
vcpkg remove opencv1:x64-windows
vcpkg remove opencv2:x64-windows
vcpkg remove opencv3:x64-windows
vcpkg remove opencv4:x64-windows
cmake . -DCMAKE_TOOLCHAIN_FILE=vcpkg\scripts\buildsystems\vcpkg.cmake  -DVCPKG_TARGET_TRIPLET=x64-windows
cmake --build . --config Release
