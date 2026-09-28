@echo off
rem ====================================================================
rem  run.cmd - 启动「新番桌面小组件」
rem --------------------------------------------------------------------
rem  后台无窗口启动；从托盘图标右键菜单或小组件右上角 × 退出。
rem  首次启动会在 data 目录生成缓存，随后每 6 小时 / 跨日自动更新。
rem ====================================================================
setlocal
chcp 65001 >nul
set "HERE=%~dp0"

start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -STA ^
    -File "%HERE%src\AnimeWidget.ps1" -Root "%HERE%."

exit /b 0
