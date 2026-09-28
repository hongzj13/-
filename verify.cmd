@echo off
chcp 65001 >nul
rem ====================================================================
rem  verify.cmd - 一键自检
rem    1) 语法检查（PowerShell 5.1）
rem    2) 离线解析 yuc.wiki 页面快照
rem    3) 离线跑完整数据管线（不联网，用 tools\samples 播种缓存）
rem    4) 把界面各视图与对话框渲染成图片（build\*.png）
rem ====================================================================
setlocal
set "HERE=%~dp0"
set "PS=powershell.exe -NoProfile -ExecutionPolicy Bypass"

echo ============================================================
echo  [1/4] 语法检查
echo ============================================================
%PS% -File "%HERE%tools\Test-Syntax.ps1" -Root "%HERE%."

echo.
echo ============================================================
echo  [2/4] 离线解析 yuc.wiki 快照
echo ============================================================
%PS% -File "%HERE%tools\Test-Yuc.ps1" -Sample yuc_202610.html
%PS% -File "%HERE%tools\Test-Yuc.ps1" -Sample yuc_202607.html

echo.
echo ============================================================
echo  [3/4] 离线数据管线
echo ============================================================
if exist "%HERE%data\state.json" copy /Y "%HERE%data\state.json" "%HERE%data\state.backup.json" >nul
%PS% -File "%HERE%tools\Test-Pipeline.ps1"
if exist "%HERE%data\state.backup.json" (
    copy /Y "%HERE%data\state.backup.json" "%HERE%data\state.json" >nul
    del "%HERE%data\state.backup.json"
)

echo.
echo ============================================================
echo  [4/4] 渲染界面图片
echo ============================================================
%PS% -STA -File "%HERE%tools\Test-Ui.ps1" -Root "%HERE%."

echo.
echo 完成。界面图片在 build 目录，日志在 data\widget.log
pause
