#requires -Version 7.2
[CmdletBinding(SupportsShouldProcess)]
param([Parameter(Mandatory)][string]$BackupPath,[Parameter(Mandatory)][string]$CollectionPath)
$ErrorActionPreference='Stop'
if(Get-Process obs64 -ErrorAction SilentlyContinue){throw 'Cierra OBS antes de restaurar.'}
$backup=(Resolve-Path -LiteralPath $BackupPath).Path
$collection=(Resolve-Path -LiteralPath $CollectionPath).Path
$data=Get-Content -LiteralPath $backup -Raw | ConvertFrom-Json
if(!$data.sources){throw 'El respaldo no contiene una coleccion de OBS.'}
if($PSCmdlet.ShouldProcess($collection,'Guardar estado actual y restaurar coleccion')){
    Copy-Item -LiteralPath $collection -Destination "$collection.before-restore-$([guid]::NewGuid()).json"
    Copy-Item -LiteralPath $backup -Destination $collection -Force
    Write-Output 'Coleccion restaurada. Abre OBS para revisarla.'
}
