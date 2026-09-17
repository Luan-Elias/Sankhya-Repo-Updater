param(
    [Parameter(Mandatory)] [string]$SrcDir,
    [Parameter(Mandatory)] [string]$OutDir
)

$ErrorActionPreference = "Stop"

function New-PolyglotBat {
    param(
        [Parameter(Mandatory)] [string]$SourcePs1,
        [Parameter(Mandatory)] [string]$OutputBat,
        [switch]$Silent,   # sem console visivel / sem pause (para a tarefa agendada)
        [switch]$NoPause
    )

    $psContent = Get-Content -Raw -LiteralPath $SourcePs1
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($psContent)
    $b64 = [Convert]::ToBase64String($bytes)

    $chunkSize = 300
    $chunks = for ($i = 0; $i -lt $b64.Length; $i += $chunkSize) {
        $b64.Substring($i, [Math]::Min($chunkSize, $b64.Length - $i))
    }

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('@echo off')
    [void]$sb.AppendLine('setlocal')
    [void]$sb.AppendLine('set "PKGROOT=%~dp0"')
    [void]$sb.AppendLine('if "%PKGROOT:~-1%"=="\" set "PKGROOT=%PKGROOT:~0,-1%"')
    [void]$sb.AppendLine('set "B64=%TEMP%\snk_%RANDOM%_%RANDOM%.b64"')
    [void]$sb.AppendLine('set "PS1=%TEMP%\snk_%RANDOM%_%RANDOM%.ps1"')

    $first = $true
    foreach ($c in $chunks) {
        if ($first) {
            [void]$sb.AppendLine("> `"%B64%`" echo $c")
            $first = $false
        } else {
            [void]$sb.AppendLine(">> `"%B64%`" echo $c")
        }
    }

    [void]$sb.AppendLine('certutil -decode "%B64%" "%PS1%" >nul 2>&1')
    [void]$sb.AppendLine('del "%B64%" >nul 2>&1')
    [void]$sb.AppendLine('powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1%" -PackageRoot "%PKGROOT%" %*')
    [void]$sb.AppendLine('set "RC=%errorlevel%"')
    [void]$sb.AppendLine('del "%PS1%" >nul 2>&1')
    if (-not $Silent -and -not $NoPause) {
        [void]$sb.AppendLine('echo.')
        [void]$sb.AppendLine('pause')
    }
    [void]$sb.AppendLine('exit /b %RC%')

    # ascii e suficiente - o conteudo real (base64) so usa A-Za-z0-9+/=
    Set-Content -LiteralPath $OutputBat -Value $sb.ToString() -Encoding ascii -NoNewline
}

if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir -Force | Out-Null }

New-PolyglotBat -SourcePs1 (Join-Path $SrcDir "Instalar-Automatico.ps1") -OutputBat (Join-Path $OutDir "Instalar-Automatico.bat")
New-PolyglotBat -SourcePs1 (Join-Path $SrcDir "install.ps1")             -OutputBat (Join-Path $OutDir "install.bat")
New-PolyglotBat -SourcePs1 (Join-Path $SrcDir "uninstall.ps1")           -OutputBat (Join-Path $OutDir "uninstall.bat")
New-PolyglotBat -SourcePs1 (Join-Path $SrcDir "Atualizar-Agora.ps1")     -OutputBat (Join-Path $OutDir "Atualizar-Agora.bat")
New-PolyglotBat -SourcePs1 (Join-Path $SrcDir "update-sankhya-modules.ps1") -OutputBat (Join-Path $OutDir "update-sankhya-modules.bat") -Silent

Write-Host "Gerados em $OutDir" -ForegroundColor Green
Get-ChildItem $OutDir -Filter *.bat | Select-Object Name, Length
