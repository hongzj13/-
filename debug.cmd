@echo off
rem ====================================================================
rem  debug.cmd - 带控制台启动，便于排查（会打印日志与异常）
rem ====================================================================
setlocal
chcp 65001 >nul
set "HERE=%~dp0"

echo [1/3] 立即刷新一次数据（离线也能用缓存）...
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "%HERE%tools\Refresh-Once.ps1" -Root "%HERE%."
echo.
echo [2/3] 最近日志（data\widget.log 末尾 30 行）...
if exist "%HERE%data\widget.log" powershell.exe -NoProfile -Command "Get-Content -Path '%HERE%data\widget.log' -Tail 30 -Encoding UTF8"
echo.
echo [3/3] 启动小组件（关闭此控制台窗口即可退出）...
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "%HERE%src\AnimeWidget.ps1" -Root "%HERE%." -DebugConsole

pause
