@echo off
setlocal

REM --- 用户需配置 ---
set "TARGET_NAME=test_3d_FVM_incompressible_channel_flow"
REM ---

REM --- 路径设置 ---
set "PROJECT_ROOT=..\..\..
set "BUILD_DIR=%PROJECT_ROOT%\build"

REM --- 备份与创建 Output ---
if exist "output" (
    if exist "output_backup" (rmdir /s /q "output_backup")
    rename "output" "output_backup"
)
mkdir "output"

REM --- 编译与运行 ---
cmake --build "%BUILD_DIR%" --target %TARGET_NAME% --config Debug
"%BUILD_DIR%\tests\3d_examples\%TARGET_NAME%\bin\Debug\%TARGET_NAME%.exe"

endlocal
