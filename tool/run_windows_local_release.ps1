$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$localExe = Join-Path $repoRoot 'build\windows\x64\runner\Release\mindnest.exe'

if (-not (Test-Path $localExe)) {
  Write-Error "Local Windows release build not found at: $localExe`nRun 'flutter build windows' first."
}

Get-Process |
  Where-Object { $_.ProcessName -eq 'mindnest' } |
  ForEach-Object {
    try {
      Stop-Process -Id $_.Id -Force -ErrorAction Stop
    } catch {
      Write-Warning "Could not stop process $($_.Id): $($_.Exception.Message)"
    }
  }

Start-Sleep -Milliseconds 350

Write-Host "Launching local repo-built Windows app:" -ForegroundColor Cyan
Write-Host $localExe -ForegroundColor White

Start-Process -FilePath $localExe -WorkingDirectory (Split-Path $localExe -Parent)
