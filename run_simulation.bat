@echo off
echo ===================================
echo  Building the simulation...
echo ===================================
cd build
call build.bat
if %errorlevel% neq 0 (
    echo.
    echo Build failed. Aborting.
    pause
    exit /b %errorlevel%
)
cd ..

echo.
echo ===================================
echo  Running the simulation...
echo ===================================
call .\build\tests\2d_examples\test_2d_flow_around_cylinder\bin\Release\test_2d_flow_around_cylinder.exe

echo.
echo ===================================
echo  Simulation finished.
echo ===================================
pause