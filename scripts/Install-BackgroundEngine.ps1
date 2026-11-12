#requires -Version 7.2
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][ValidateSet('CPU','NVIDIA')][string]$Engine,
    [string]$CacheDirectory = (Join-Path $env:LOCALAPPDATA 'OBSBackgroundWorkflows/cache'),
    [string]$PluginDirectory = (Join-Path $env:ProgramData 'obs-studio/plugins')
)
$ErrorActionPreference = 'Stop'
if (Get-Process obs64 -ErrorAction SilentlyContinue) { throw 'Cierra OBS antes de instalar el motor.' }
if (!$PSCmdlet.ShouldProcess($Engine, 'Descargar, verificar e instalar el motor de fondo')) { return }
New-Item -ItemType Directory -Path $CacheDirectory -Force | Out-Null

function Get-VerifiedDownload([string]$Url, [string]$Path, [string]$Sha256) {
    if (!(Test-Path -LiteralPath $Path) -or (Get-FileHash -LiteralPath $Path).Hash -ne $Sha256) {
        Invoke-WebRequest -Uri $Url -OutFile $Path
    }
    if ((Get-FileHash -LiteralPath $Path).Hash -ne $Sha256) { throw "SHA256 incorrecto: $Path" }
}

if ($Engine -eq 'CPU') {
    # Version probada con OBS 32.2.2. No seguir latest automaticamente.
    $zip = Join-Path $CacheDirectory 'obs-backgroundremoval-1.4.1-windows-x64.zip'
    Get-VerifiedDownload 'https://github.com/royshil/obs-backgroundremoval/releases/download/1.4.1/obs-backgroundremoval-1.4.1-windows-x64.zip' $zip '7F9C0118C348111BF384C71E23FD056FD26E999BCE90132D91DB3017C6FA1B94'
    $stage = Join-Path $CacheDirectory ([guid]::NewGuid().ToString())
    Expand-Archive -LiteralPath $zip -DestinationPath $stage
    $source = Join-Path $stage 'obs-backgroundremoval'
    if (!(Test-Path -LiteralPath (Join-Path $source 'bin/64bit/obs-backgroundremoval.dll'))) { throw 'El paquete no contiene el plugin esperado.' }
    New-Item -ItemType Directory -Path $PluginDirectory -Force | Out-Null
    $destination = Join-Path $PluginDirectory 'obs-backgroundremoval'
    if (Test-Path -LiteralPath $destination) {
        # Copia antes de sobreescribir; conserva modelos adicionales del usuario.
        Copy-Item -LiteralPath $destination -Destination "$destination.backup-$([guid]::NewGuid())" -Recurse
        Copy-Item -Path (Join-Path $source '*') -Destination $destination -Recurse -Force
    } else { Copy-Item -LiteralPath $source -Destination $destination -Recurse }
    Write-Output 'CPU: obs-backgroundremoval 1.4.1 instalado. Reinicia OBS despues de configurar.'
} else {
    $smi = Get-Command nvidia-smi -ErrorAction Stop
    $gpu = & $smi.Source --query-gpu=name --format=csv,noheader
    if ($LASTEXITCODE -ne 0 -or !($gpu -match 'RTX\s+30\d{2}')) {
        throw 'Este instalador fijado es para GeForce RTX serie 30 (Ampere), incluida RTX 3070. Consulta NVIDIA para otras series.'
    }
    $installer = Join-Path $CacheDirectory 'nvidia_video_effects_sdk_installer_v0.7.6_ampere.exe'
    Get-VerifiedDownload 'https://international.download.nvidia.com/Windows/broadcast/sdk/VFX/nvidia_video_effects_sdk_installer_v0.7.6_ampere.exe' $installer '93BDF4FFEC7C393037936349678D1864897FEF45D7BA2AB81D4B1563E1328512'
    Write-Host 'Completa el asistente oficial de NVIDIA y pulsa Close al finalizar. No se cambian drivers.'
    # -s no evita la pantalla final en este paquete: no prometer instalacion desatendida.
    $process = Start-Process -FilePath $installer -PassThru
    $process.WaitForExit()
    if ($process.ExitCode -notin @(0,3010)) { throw "El instalador termino con codigo $($process.ExitCode)." }
    $dll = Join-Path $env:ProgramFiles 'NVIDIA Corporation/NVIDIA Video Effects/NVVideoEffects.dll'
    if (!(Test-Path -LiteralPath $dll)) { throw 'No se encontro NVVideoEffects.dll despues de instalar.' }
    Write-Output 'NVIDIA Video Effects instalado. Reinicia OBS despues de configurar.'
}
