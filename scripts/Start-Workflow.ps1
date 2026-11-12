#requires -Version 7.2
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][ValidateSet('CPU','NVIDIA')][string]$Engine,
    [Parameter(Mandatory)][string]$ImagePath,
    [Parameter(Mandatory)][string]$CollectionPath,
    [string]$SceneName='Scene',
    [string]$CameraName='Video Capture Device',
    [string]$BackgroundName='Fondo automatizado',
    [ValidateRange(1,8192)][int]$CameraWidth=640,
    [ValidateRange(1,8192)][int]$CameraHeight=480,
    [switch]$Install
)
$ErrorActionPreference='Stop'
if ($Install) { & "$PSScriptRoot/Install-BackgroundEngine.ps1" -Engine $Engine -WhatIf:$WhatIfPreference }
if (!$WhatIfPreference) {
    $dependency = if ($Engine -eq 'CPU') {
        Join-Path $env:ProgramData 'obs-studio/plugins/obs-backgroundremoval/bin/64bit/obs-backgroundremoval.dll'
    } else { Join-Path $env:ProgramFiles 'NVIDIA Corporation/NVIDIA Video Effects/NVVideoEffects.dll' }
    if (!(Test-Path -LiteralPath $dependency)) { throw 'El motor no esta instalado. Ejecuta con -Install.' }
}
& "$PSScriptRoot/Set-OBSBackground.ps1" -Engine $Engine -ImagePath $ImagePath -CollectionPath $CollectionPath -SceneName $SceneName -CameraName $CameraName -BackgroundName $BackgroundName -CameraWidth $CameraWidth -CameraHeight $CameraHeight -WhatIf:$WhatIfPreference
