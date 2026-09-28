# Fix-Encoding.ps1 -- 把项目内所有 .ps1 统一保存为「UTF-8 with BOM（且仅一个 BOM）」
# Windows PowerShell 5.1 读取无 BOM 的 UTF-8 脚本时会把中文当 ANSI，导致乱码/语法错误。
param([string]$Root = (Split-Path -Parent (Split-Path -Parent $PSCommandPath)))

$enc = New-Object System.Text.UTF8Encoding($true)
$count = 0
Get-ChildItem -Path $Root -Recurse -Include *.ps1 -File | ForEach-Object {
    $bytes = [System.IO.File]::ReadAllBytes($_.FullName)
    $text = [System.Text.Encoding]::UTF8.GetString($bytes)
    $clean = $text.TrimStart([char]0xFEFF)          # 去掉 0 个或多个 BOM 字符
    $clean = $clean -replace "`r`n", "`n"
    [System.IO.File]::WriteAllText($_.FullName, $clean, $enc)
    $count++
    Write-Host ("fixed: {0}" -f $_.FullName.Substring($Root.Length).TrimStart('\'))
}
Write-Host ("共处理 {0} 个 .ps1 文件（UTF-8 BOM）" -f $count)
