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
cmake . -DCMAKE_TOOLCHAIN_FILE=C:\vcpkg\scripts\buildsystems\vcpkg.cmake  -DVCPKG_TARGET_TRIPLET=x64-windows
powershell -Command "(Get-Content 'MandelbrotAsm\MandelbrotAsm\MandelbrotAsm.vcxproj' -Raw) -replace 'opencv_world4120\.lib','opencv_world4130.lib' | Set-Content 'MandelbrotAsm\MandelbrotAsm\MandelbrotAsm.vcxproj'"
cmake --build . --config Release
