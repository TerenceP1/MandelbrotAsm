gfortran -O3 -march=native -mtune=native -fno-fast-math -fopt-info -shared -o mandelbrotfortran.dll deepmandelbrot.f90
xcopy mandelbrotfortran.dll ..\ /Y