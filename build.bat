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
echo =============
powershell -NoProfile -Command "Get-ChildItem -Recurse -File | Select-String -SimpleMatch 'opencv_world4120' | ForEach-Object { Write-Host ('FILE: ' + $_.Path); Write-Host ('LINE: ' + $_.Line); Write-Host '' }"
echo =============
powershell -Command "(Get-Content 'MandelbrotAsm.vcxproj' -Raw) -replace 'opencv_world4120\.lib','opencv_world4130.lib' | Set-Content 'MandelbrotAsm.vcxproj'"
cmake --build . --config Release
