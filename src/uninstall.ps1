param(
    [string]$PackageRoot
)

$ErrorActionPreference = "SilentlyContinue"

$configPath = Join-Path $PackageRoot "config.json"
$config = if (Test-Path $configPath) { Get-Content $configPath -Raw | ConvertFrom-Json } else { $null }

$taskName = if ($config) { $config.taskName } else { "Sankhya-UpdateModules" }
schtasks /Delete /TN $taskName /F | Out-Null
Write-Host "Tarefa agendada '$taskName' removida (se existia)." -ForegroundColor Cyan

$shortcutName = if ($config) { $config.shortcutName } else { "Atualizar modulos Sankhya" }
$desktop = [Environment]::GetFolderPath("Desktop")
$shortcutPath = Join-Path $desktop ("{0}.lnk" -f $shortcutName)
if (Test-Path $shortcutPath) {
    Remove-Item $shortcutPath -Force
    Write-Host "Atalho removido: $shortcutPath" -ForegroundColor Cyan
}

Write-Host "Desinstalacao concluida. Os arquivos de log em .\logs e a pasta do pacote nao foram apagados." -ForegroundColor Cyan
