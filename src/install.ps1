param(
    [string]$PackageRoot
)

$ErrorActionPreference = "Stop"

function Get-ConfiguredRepoPaths {
    param([Parameter(Mandatory)] $Config)
    if ($Config.PSObject.Properties.Name -contains 'repoPaths' -and $Config.repoPaths -and @($Config.repoPaths).Count -gt 0) {
        return @($Config.repoPaths)
    }
    if (-not $Config.reposRoot -or -not $Config.repoNames) { return @() }
    return @($Config.repoNames | ForEach-Object { Join-Path $Config.reposRoot $_ })
}

function Install-SankhyaUpdater {
    param(
        [Parameter(Mandatory)] $Config,
        [Parameter(Mandatory)] [string]$PackageRoot
    )

    $repoPaths = Get-ConfiguredRepoPaths -Config $Config
    if ($repoPaths.Count -eq 0) {
        throw "Nenhum repositorio configurado (repoPaths vazio e reposRoot/repoNames tambem vazios)."
    }

    foreach ($repoPath in $repoPaths) {
        if (Test-Path (Join-Path $repoPath ".git")) {
            Push-Location $repoPath
            git config core.longpaths true 2>$null
            Pop-Location
        } else {
            Write-Warning "Repositorio nao encontrado, pulando: $repoPath"
        }
    }

    $scriptPath = Join-Path $PackageRoot "update-sankhya-modules.bat"
    $trArg = "cmd.exe /c `"$scriptPath`""
    schtasks /Create /TN $Config.taskName /TR $trArg /SC DAILY /ST $Config.scheduleTime /RL LIMITED /F | Out-Null

    $manualScript = Join-Path $PackageRoot "Atualizar-Agora.bat"
    $WshShell = New-Object -ComObject WScript.Shell
    $desktop = [Environment]::GetFolderPath("Desktop")
    $shortcutPath = Join-Path $desktop ("{0}.lnk" -f $Config.shortcutName)
    $shortcut = $WshShell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = $manualScript
    $shortcut.WorkingDirectory = $PackageRoot
    $shortcut.IconLocation = "shell32.dll,238"
    $shortcut.Description = "Verifica e atualiza os repositorios configurados (git pull) e mostra o resultado"
    $shortcut.Save()

    return [pscustomobject]@{
        TaskName     = $Config.taskName
        ShortcutPath = $shortcutPath
        RepoCount    = $repoPaths.Count
        RepoPaths    = $repoPaths
    }
}

$configPath = Join-Path $PackageRoot "config.json"
if (-not (Test-Path $configPath)) {
    throw "config.json nao encontrado. Ajuste config.json (reposRoot, repoNames, scheduleTime, discardMode) antes de instalar, ou rode Instalar-Automatico.bat para descobrir os repositorios sozinho."
}
$config = Get-Content $configPath -Raw | ConvertFrom-Json

$hasRepoPaths = ($config.PSObject.Properties.Name -contains 'repoPaths') -and $config.repoPaths -and @($config.repoPaths).Count -gt 0
if (-not $hasRepoPaths -and $config.reposRoot -match "CAMINHO\\PARA\\SEUS\\PROJETOS") {
    throw "Edite config.json e defina 'reposRoot'/'repoNames' (ou rode Instalar-Automatico.bat para detectar sozinho) antes de instalar."
}

Write-Host "Instalando com base em: $PackageRoot" -ForegroundColor Cyan
Write-Host "discardMode: $($config.discardMode)"
Write-Host "horario: $($config.scheduleTime)"
Write-Host ""

$installResult = Install-SankhyaUpdater -Config $config -PackageRoot $PackageRoot

Write-Host "Repositorios configurados ($($installResult.RepoCount)):" -ForegroundColor Cyan
$installResult.RepoPaths | ForEach-Object { Write-Host "  - $_" }
Write-Host ""
Write-Host "Tarefa agendada '$($installResult.TaskName)' criada para rodar 1x por dia as $($config.scheduleTime)." -ForegroundColor Green
Write-Host "Atalho criado na area de trabalho: $($installResult.ShortcutPath)" -ForegroundColor Green

Write-Host ""
Write-Host "IMPORTANTE: se algum repositorio tiver arquivos de build com caminhos muito longos," -ForegroundColor Yellow
Write-Host "pode ser necessario habilitar suporte a caminhos longos do Windows (requer admin):" -ForegroundColor Yellow
Write-Host '  New-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem" -Name LongPathsEnabled -Value 1 -PropertyType DWord -Force' -ForegroundColor Yellow
Write-Host ""
Write-Host "Instalacao concluida." -ForegroundColor Cyan
