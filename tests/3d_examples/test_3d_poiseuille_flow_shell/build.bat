@echo off
setlocal

REM --- User Configuration ---
set "TARGET_NAME=test_3d_poiseuille_flow_shell"
REM ---

REM --- Setup Paths ---
set "CURRENT_DIR=%~dp0"
set "PROJECT_ROOT=%CURRENT_DIR%..\..\.."
set "BUILD_DIR=%PROJECT_ROOT%\build"

REM --- Backup and Create Output Directories ---
echo "Handling output directories..."
if exist "output" (
    if exist "output_backup" (
        rmdir /s /q "output_backup"
    )
    rename "output" "output_backup"
)
mkdir "output"

REM --- Build and Run ---
echo "Building target: %TARGET_NAME%..."
cmake --build "%BUILD_DIR%" --target %TARGET_NAME% --config Debug
echo "Running executable..."
"%BUILD_DIR%\tests\3d_examples\%TARGET_NAME%\bin\Debug\%TARGET_NAME%.exe"

endlocal