@echo off
setlocal

REM Set project root and build directories
set "PROJECT_ROOT=d:/AAA_postgraduate/SPH/code/SPHinXsys"
set "BUILD_DIR=%PROJECT_ROOT%/build"
set "EXECUTABLE_DIR=%BUILD_DIR%/bin"

REM Set target name
set "TARGET_NAME=test_2d_channel_flow_fluid_shell"

REM Build and run
echo "Building target: %TARGET_NAME%..."
cmake --build "%BUILD_DIR%" --target %TARGET_NAME%
echo "Running executable..."
"%BUILD_DIR%/tests/2d_examples/%TARGET_NAME%/bin/Debug/%TARGET_NAME%.exe"

REM Copy output directory
echo "Copying output directory..."
if exist "%EXECUTABLE_DIR%/output" (
    xcopy /E /I /Y "%EXECUTABLE_DIR%/output" "output"
    echo "Output directory copied successfully."
) else (
    echo "Warning: Output directory not found."
)

endlocal