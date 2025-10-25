@echo off
setlocal

set "PROJECT_ROOT=..\..\.."
set "BUILD_DIR=%PROJECT_ROOT%\build_codex"
set "TARGET_NAME=test_3d_channel_flow"
set "GENERATOR_CONFIG=Release"

set "VCPKG_ROOT=%PROJECT_ROOT%\..\vcpkg"
for %%I in ("%VCPKG_ROOT%\scripts\buildsystems\vcpkg.cmake") do set "VCPKG_TOOLCHAIN=%%~fI"
for %%I in ("%VCPKG_ROOT%\installed\x64-windows\share\simbody") do set "SIMBODY_DIR=%%~fI"
for %%I in ("%VCPKG_ROOT%\installed\x64-windows\share\tbb") do set "TBB_DIR=%%~fI"
for %%I in ("%VCPKG_ROOT%\installed\x64-windows") do set "BOOST_ROOT=%%~fI"

echo [configure] Configuring SPHinXsys CMake cache...
cmake -G "Visual Studio 17 2022" -S "%PROJECT_ROOT%" -B "%BUILD_DIR%" ^
    -DSPHINXSYS_3D=ON ^
    -DSPHINXSYS_BUILD_3D_EXAMPLES=ON ^
    -DSPHINXSYS_BUILD_2D_EXAMPLES=OFF ^
    -DSPHINXSYS_BUILD_OPTIMIZATION_EXAMPLES=OFF ^
    -DSPHINXSYS_BUILD_USER_EXAMPLES=OFF ^
    -DSPHINXSYS_BUILD_UNIT_TESTS=OFF ^
    -DSimbody_DIR=%SIMBODY_DIR% ^
    -DTBB_DIR=%TBB_DIR% ^
    -DBOOST_ROOT=%BOOST_ROOT% ^
    -DBoost_INCLUDE_DIR=%BOOST_ROOT%\include ^
    -DCMAKE_PREFIX_PATH=%BOOST_ROOT% ^
    -DCMAKE_TOOLCHAIN_FILE=%VCPKG_TOOLCHAIN% ^
    -DVCPKG_TARGET_TRIPLET=x64-windows
if errorlevel 1 (
    echo [error] CMake configuration failed.
    exit /b 1
)

echo [build] Building %TARGET_NAME% (%GENERATOR_CONFIG%)...
cmake --build "%BUILD_DIR%" --target %TARGET_NAME% --config %GENERATOR_CONFIG%
if errorlevel 1 (
    echo [error] Build failed.
    exit /b 1
)

echo [done] Executable located at:
echo   %BUILD_DIR%\tests\3d_examples\%TARGET_NAME%\bin\%GENERATOR_CONFIG%\%TARGET_NAME%.exe

endlocal
