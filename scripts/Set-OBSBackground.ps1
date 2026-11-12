#requires -Version 7.2
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][ValidateSet('CPU','NVIDIA')][string]$Engine,
    [Parameter(Mandatory)][string]$ImagePath,
    [Parameter(Mandatory)][string]$CollectionPath,
    [string]$SceneName = 'Scene',
    [string]$CameraName = 'Video Capture Device',
    [string]$BackgroundName = 'Fondo automatizado',
    [ValidateRange(1,8192)][int]$CameraWidth = 640,
    [ValidateRange(1,8192)][int]$CameraHeight = 480
)
$ErrorActionPreference = 'Stop'
if (Get-Process obs64 -ErrorAction SilentlyContinue) { throw 'Cierra OBS para evitar que sobrescriba los cambios.' }
$collection = (Resolve-Path -LiteralPath $CollectionPath).Path
$image = (Resolve-Path -LiteralPath $ImagePath).Path
if ([IO.Path]::GetExtension($image) -notin @('.webp','.png','.jpg','.jpeg','.bmp','.gif')) { throw 'Selecciona un archivo de imagen compatible.' }
$project = Get-Content -LiteralPath $collection -Raw | ConvertFrom-Json -AsHashtable
$scenes = @($project.sources | Where-Object { $_.name -eq $SceneName -and $_.id -eq 'scene' })
$cameras = @($project.sources | Where-Object { $_.name -eq $CameraName -and $_.id -eq 'dshow_input' })
if ($scenes.Count -ne 1 -or $cameras.Count -ne 1) { throw 'No se encontro una unica escena y camara con esos nombres.' }
$scene = $scenes[0]; $camera = $cameras[0]
$cameraItems = @($scene.settings.items | Where-Object { $_.source_uuid -eq $camera.uuid })
if ($cameraItems.Count -ne 1) { throw 'La camara debe estar directamente en la escena, sin grupos ni duplicados.' }
$cameraItem = $cameraItems[0]
if ($cameraItem.rot -ne 0 -or $cameraItem.crop_left -or $cameraItem.crop_top -or $cameraItem.crop_right -or $cameraItem.crop_bottom) {
    throw 'No se admiten camaras rotadas o recortadas; ajustalas antes de ejecutar.'
}
if ($BackgroundName -eq $CameraName -or $BackgroundName -eq $SceneName) { throw 'El nombre del fondo debe ser diferente de la camara y escena.' }
$existing = @($project.sources | Where-Object name -eq $BackgroundName)
if ($existing.Count -gt 1 -or ($existing.Count -eq 1 -and ($existing[0].id -ne 'image_source' -or !$existing[0].private_settings.obs_background_workflows))) {
    throw 'El nombre del fondo pertenece a otra fuente; elige otro BackgroundName.'
}
if ($existing.Count -eq 1) {
    $background = $existing[0]
    # No alterar una imagen compartida con otra escena.
    foreach ($other in @($project.sources | Where-Object { $_.id -in @('scene','group') -and $_.uuid -ne $scene.uuid })) {
        if (@($other.settings.items | Where-Object source_uuid -eq $background.uuid).Count) { throw 'El fondo esta compartido; usa otro BackgroundName.' }
    }
} else {
    $background = @{
        name=$BackgroundName; uuid=[guid]::NewGuid().ToString(); id='image_source'; versioned_id='image_source'
        settings=@{}; enabled=$true; mixers=0; volume=1.0; hotkeys=@{}
        private_settings=@{obs_background_workflows=$true}
    }
    $project.sources = @($project.sources) + @($background)
}
$background.settings = @{file=$image.Replace('\','/'); unload=$false}
$filters = @($camera.filters | Where-Object { $null -ne $_ })
$filterId = if ($Engine -eq 'CPU') { 'background_removal' } else { 'nv_greenscreen_filter' }
foreach ($filter in $filters) {
    if ($filter.id -in @('background_removal','nv_greenscreen_filter')) { $filter.enabled = $false }
}
$matches = @($filters | Where-Object id -eq $filterId)
if ($matches.Count -gt 1) { throw 'Hay filtros de recorte duplicados; revisa la camara en OBS.' }
if ($matches.Count -eq 1) { $active = $matches[0] } else {
    $active = @{name=if($Engine -eq 'CPU'){'Background Removal'}else{'NVIDIA Background Removal'}; uuid=[guid]::NewGuid().ToString(); id=$filterId; versioned_id=$filterId; settings=@{}; enabled=$true; hotkeys=@{}}
    $filters += @($active)
}
$active.enabled = $true
if ($Engine -eq 'CPU') {
    $active.settings.model_select = 'models/rvm_mobilenetv3_fp32.with_runtime_opt.ort'
    $active.settings.numThreads = 2
    $active.settings.smooth_contour = 0.5
} else {
    $active.settings.mode = 1
    $active.settings.processing_interval = 1
    $active.settings.threshold = 1.0
}
$camera.filters = $filters
$items = @($scene.settings.items | Where-Object source_uuid -ne $background.uuid)
$imageItem = $cameraItem | ConvertTo-Json -Depth 100 | ConvertFrom-Json -AsHashtable
$imageItem.name = $background.name; $imageItem.source_uuid = $background.uuid
$maxId = ($scene.settings.items | Measure-Object -Property id -Maximum).Maximum
$imageItem.id = [math]::Max([int]$scene.settings.id_counter,[int]$maxId) + 1
$imageItem.locked = $true; $imageItem.visible = $true
$imageItem.bounds_type = 1 # OBS_BOUNDS_STRETCH: cubrir exactamente el recuadro de camara.
$width = $CameraWidth * $cameraItem.scale.x; $height = $CameraHeight * $cameraItem.scale.y
if ($cameraItem.bounds_type -ne 0) {
    # Solo stretch tiene un rectangulo inequivoco sin conocer el ajuste interno de OBS.
    if ($cameraItem.bounds_type -ne 1) { throw 'La camara usa limites especiales. Usa sin limites o stretch.' }
    $width = $cameraItem.bounds.x; $height = $cameraItem.bounds.y
}
if ($width -le 0 -or $height -le 0) { throw 'Dimensiones invalidas; comprueba CameraWidth/CameraHeight y escala.' }
$imageItem.bounds = @{x=$width; y=$height}
$imageItem.scale = @{x=1.0;y=1.0}
$imageItem.bounds_align = 0; $imageItem.bounds_crop = $false
$imageItem.private_settings = @{}
# Obligar a OBS a recalcular coordenadas relativas a partir de las absolutas guardadas.
foreach ($key in @('pos_rel','bounds_rel','scale_rel','scale_ref')) { $imageItem.Remove($key) }
$newItems = @()
foreach ($item in $items) {
    if ($item.source_uuid -eq $camera.uuid) { $newItems += @($imageItem) }
    $newItems += @($item)
}
$scene.settings.items = $newItems; $scene.settings.id_counter = $imageItem.id
if (!$PSCmdlet.ShouldProcess($collection,"Configurar fondo con motor $Engine y guardar respaldo")) { return }
$backup = "$collection.background-backup-$([guid]::NewGuid()).json"
Copy-Item -LiteralPath $collection -Destination $backup
$temporary = "$collection.$([guid]::NewGuid()).tmp"
$project | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $temporary -Encoding utf8
# Validar antes de reemplazar el documento original.
Get-Content -LiteralPath $temporary -Raw | ConvertFrom-Json -ErrorAction Stop | Out-Null
Move-Item -LiteralPath $temporary -Destination $collection -Force
Write-Output "Configurado: $Engine. Respaldo: $backup"
Write-Output 'Abre OBS, revisa la silueta y confirma que el filtro esta disponible y la camara conserva su encuadre.'
