param(
    [string]$PackageRoot,
    [string]$GitHost = "gitlab.sankhya.com.br"
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Windows.Forms

function Get-ConfiguredRepoPaths {
    param([Parameter(Mandatory)] $Config)
    if ($Config.PSObject.Properties.Name -contains 'repoPaths' -and $Config.repoPaths -and @($Config.repoPaths).Count -gt 0) {
        return @($Config.repoPaths)
    }
    if (-not $Config.reposRoot -or -not $Config.repoNames) { return @() }
    return @($Config.repoNames | ForEach-Object { Join-Path $Config.reposRoot $_ })
}

function Find-SankhyaRepos {
    param(
        [Parameter(Mandatory)] [string]$GitHostFilter,
        [string[]]$SearchRoots,
        [int]$MaxDepth = 7
    )

    if (-not $SearchRoots -or $SearchRoots.Count -eq 0) {
        $SearchRoots = [System.IO.DriveInfo]::GetDrives() |
            Where-Object { $_.DriveType -eq 'Fixed' -and $_.IsReady } |
            ForEach-Object { $_.RootDirectory.FullName }
    }

    $excludeDirNames = @(
        'Windows', 'Program Files', 'Program Files (x86)', 'ProgramData',
        '$Recycle.Bin', 'System Volume Information', 'Windows.old',
        'AppData', 'node_modules', '.git', '.vs', '.idea', 'bin', 'obj',
        'Recovery', 'PerfLogs', 'found.000', 'found.001', 'found.002'
    )

    $found = New-Object System.Collections.Generic.List[object]
    $visited = New-Object System.Collections.Generic.HashSet[string]

    foreach ($root in $SearchRoots) {
        if (-not (Test-Path -LiteralPath $root)) { continue }

        $stack = New-Object System.Collections.Generic.Stack[object]
        $stack.Push(@{ Path = (Resolve-Path -LiteralPath $root).Path; Depth = 0 })

        while ($stack.Count -gt 0) {
            $current = $stack.Pop()
            $path = $current.Path
            $depth = $current.Depth

            if (-not $visited.Add($path)) { continue }

            if (Test-Path -LiteralPath (Join-Path $path ".git")) {
                $remote = $null
                try {
                    Push-Location -LiteralPath $path
                    $remote = git remote get-url origin 2>$null
                    $ok = ($LASTEXITCODE -eq 0)
                    Pop-Location
                } catch {
                    $ok = $false
                    try { Pop-Location } catch {}
                }
                if ($ok -and $remote -and $remote -like "*$GitHostFilter*") {
                    $found.Add([pscustomobject]@{
                        Name   = Split-Path $path -Leaf
                        Path   = $path
                        Remote = $remote
                    })
                }
                continue
            }

            if ($depth -ge $MaxDepth) { continue }

            $children = $null
            try {
                $children = Get-ChildItem -LiteralPath $path -Directory -Force -ErrorAction SilentlyContinue
            } catch { continue }

            foreach ($child in $children) {
                if ($excludeDirNames -contains $child.Name) { continue }
                if ($child.Name.StartsWith('$')) { continue }
                $stack.Push(@{ Path = $child.FullName; Depth = $depth + 1 })
            }
        }
    }

    return @($found | Sort-Object Path -Unique)
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

Write-Host "Procurando repositorios git com remoto '$GitHost' neste computador..." -ForegroundColor Cyan
Write-Host "(pode levar 1-2 minutos na primeira vez, dependendo do tamanho do disco)" -ForegroundColor Cyan
Write-Host ""

$repos = Find-SankhyaRepos -GitHostFilter $GitHost

if (-not $repos -or $repos.Count -eq 0) {
    [System.Windows.Forms.MessageBox]::Show(
        "Nao encontrei nenhum repositorio git apontando para '$GitHost' neste computador.`n`n" +
        "Verifique se os projetos ja foram clonados (git clone) antes de rodar este instalador.`n" +
        "Se os repositorios usam outro host git, rode:`n  Instalar-Automatico.bat -GitHost `"seu.git.host`"",
        "Nenhum repositorio encontrado",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Warning
    ) | Out-Null
    exit
}

Write-Host "Encontrados $($repos.Count) repositorio(s):" -ForegroundColor Green
$repos | ForEach-Object { Write-Host "  - $($_.Name)  ->  $($_.Path)" }
Write-Host ""

$configPath = Join-Path $PackageRoot "config.json"
$config = if (Test-Path $configPath) {
    Get-Content $configPath -Raw | ConvertFrom-Json
} else {
    [pscustomobject]@{
        reposRoot      = ""
        repoNames      = @()
        repoPaths      = @()
        gitHost        = $GitHost
        taskName       = "Sankhya-UpdateModules"
        scheduleTime   = "11:00"
        discardMode    = "stash"
        vpnAutoConnect = $false
        shortcutName   = "Atualizar modulos Sankhya"
    }
}

$config | Add-Member -NotePropertyName repoPaths -NotePropertyValue @() -Force
$config.repoPaths = @($repos | ForEach-Object { $_.Path })
$config.reposRoot = ""
$config.repoNames = @()
$config.gitHost = $GitHost

($config | ConvertTo-Json -Depth 5) | Set-Content -Path $configPath -Encoding utf8

Write-Host "config.json atualizado com os repositorios encontrados." -ForegroundColor Green
Write-Host ""

$installResult = Install-SankhyaUpdater -Config $config -PackageRoot $PackageRoot

Write-Host "Tarefa agendada '$($installResult.TaskName)' criada para rodar 1x por dia as $($config.scheduleTime)." -ForegroundColor Green
Write-Host "Atalho criado na area de trabalho: $($installResult.ShortcutPath)" -ForegroundColor Green

$listText = ($repos | ForEach-Object { "  - $($_.Name)" }) -join "`n"
[System.Windows.Forms.MessageBox]::Show(
    "Instalacao concluida!`n`n" +
    "Repositorios encontrados e configurados ($($repos.Count)):`n$listText`n`n" +
    "Verificacao automatica diaria as $($config.scheduleTime).`n" +
    "Atalho manual criado na area de trabalho: $($config.shortcutName)`n`n" +
    "Se algum repositorio tiver arquivos de build com caminho muito longo, pode ser`n" +
    "necessario habilitar LongPathsEnabled do Windows (veja o README.md).",
    "Sankhya - instalacao automatica concluida",
    [System.Windows.Forms.MessageBoxButtons]::OK,
    [System.Windows.Forms.MessageBoxIcon]::Information
) | Out-Null
