# Test-Syntax.ps1 -- 用当前 PowerShell 解析全部脚本，报告语法错误
param([string]$Root = (Split-Path -Parent (Split-Path -Parent $PSCommandPath)))
$files = Get-ChildItem -Path $Root -Recurse -Include *.ps1 -File | Where-Object { $_.Name -notlike '_*' }
$bad = 0
foreach ($f in $files) {
    $errors = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$null, [ref]$errors)
    if ($errors -and $errors.Count -gt 0) {
        $bad++
        Write-Host ("[语法错误] {0}" -f $f.FullName.Substring($Root.Length).TrimStart('\'))
        foreach ($e in $errors) { Write-Host ("   line {0}: {1}" -f $e.Extent.StartLineNumber, $e.Message) }
    } else {
        Write-Host ("[OK] {0}" -f $f.FullName.Substring($Root.Length).TrimStart('\'))
    }
}
Write-Host ("$($files.Count) 个文件，$bad 个有语法错误（PS $($PSVersionTable.PSVersion)）")
