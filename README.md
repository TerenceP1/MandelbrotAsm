# MandelbrotAsm
Its a public release of my MandelbrotAsm hobby project. It currently only works on windows.

(THIS IS JUST A SNEAK PEAK I WILL FINISH POLISHING LATER)

## Requirements

CMake, MSVC, gfortran (use MSYS2 for gfortran), OpenCV and GMP (best installed by vcpkg, otherwise CMake might complain)
If you run into cmake complaining, this is a sneak peak so you must go fix it :(

## How to use

First, it shows you a little image and then you enter a mode. Mode 0 is interactive exploring but it doesn't use double-double. For mode 0, press a spot on the image to zoom, press q to quit, press o to zoom out, i to set maxitr (Max Iterations) (switch to the terminal to enter the value), and s to set speclen (Spectrum Length or how many colors it takes for it to repeat.


Mode 1 is the animation generator. The resolution is hardcoded to 4k (I will change later). The re and im parameters are the re and im of the center of the image. The zoom is 1 for no zoom and increases for deeper zooms (simply means the end will be scaled up by zoom times). At zoom level 1, the image shows almost the full set. This program goes to at most double-double precision. To find spots, consider my [interactive Mandelbrot set zoomer](https://terencep1.github.io/mandelbrot2) (ignore the whole panel at the bottom its a remote control thing I built for myself). Currently, the only color palette is the built in one but that will hopefully change soon.

## How to build

Simple, just double click build.bat (assuming you have the above installed [these](#requirements)). If any issues arise, you will have to fix the requirement/dependency issue yourself. Ensure gfortran and CMake are on your path upon running. (BEWARE IT WILL WIPE YOUR VCPKG OPENCV IF YOU HAVE IT)
