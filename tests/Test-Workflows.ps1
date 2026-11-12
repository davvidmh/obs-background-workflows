#requires -Version 7.2
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$scratch=Join-Path ([IO.Path]::GetTempPath()) "obs-workflows-test-$([guid]::NewGuid())"
New-Item -ItemType Directory -Path $scratch | Out-Null
# Las pruebas editan un fixture, nunca una coleccion real ni el proceso OBS.
function Get-Process { param($Name,$ErrorAction) return $null }
function Assert($Condition,[string]$Message){if(!$Condition){throw $Message}}
$collection=Join-Path $scratch 'fixture.json'
$image=Join-Path $scratch 'test.png'
[IO.File]::WriteAllBytes($image,[Convert]::FromBase64String('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aZ1sAAAAASUVORK5CYII='))
$fixture=@{
    name='Test'; current_scene='Scene'; modules=@{sentinel='retain'}
    sources=@(
        @{name='Camera';uuid='camera-uuid';id='dshow_input';settings=@{sentinel='retain'};filters=@(@{name='Color';id='color_filter';enabled=$true;settings=@{gamma=0.3}})},
        @{name='Board';uuid='board-uuid';id='window_capture';settings=@{window='fixture'}},
        @{name='Other';uuid='other-uuid';id='scene';settings=@{items=@()}},
        @{name='Scene';uuid='scene-uuid';id='scene';settings=@{id_counter=10;items=@(
            @{name='Board';source_uuid='board-uuid';id=4;visible=$true},
            @{name='Camera';source_uuid='camera-uuid';id=10;visible=$true;locked=$false;rot=0;crop_left=0;crop_top=0;crop_right=0;crop_bottom=0;bounds_type=0;align=5;pos=@{x=50;y=40};pos_rel=@{x=0;y=0};scale=@{x=0.5;y=0.5};scale_rel=@{x=0.5;y=0.5};scale_ref=@{x=1920;y=1080};bounds=@{x=0;y=0}}
        )}}
    )
}
$fixture | ConvertTo-Json -Depth 50 | Set-Content -LiteralPath $collection
$original=Get-FileHash -LiteralPath $collection
$parameters=@{ImagePath=$image;CollectionPath=$collection;SceneName='Scene';CameraName='Camera'}
& "$root/scripts/Set-OBSBackground.ps1" @parameters -Engine CPU -WhatIf
Assert ((Get-FileHash -LiteralPath $collection).Hash -eq $original.Hash) 'WhatIf cambio el archivo.'
Assert (@(Get-ChildItem $scratch -Filter '*backup*').Count -eq 0) 'WhatIf creo un respaldo.'
foreach($engine in @('CPU','NVIDIA','NVIDIA','CPU')){
    & "$root/scripts/Set-OBSBackground.ps1" @parameters -Engine $engine
    $p=Get-Content -LiteralPath $collection -Raw | ConvertFrom-Json -AsHashtable
    $scene=$p.sources | Where-Object name -eq 'Scene'
    $camera=$p.sources | Where-Object name -eq 'Camera'
    $bg=@($p.sources | Where-Object name -eq 'Fondo automatizado')
    Assert ($p.sources.Count -eq 5 -and $bg.Count -eq 1) 'Se perdieron o duplicaron fuentes.'
    Assert ($scene.settings.items.Count -eq 3) 'Se perdieron o duplicaron elementos.'
    Assert ($scene.settings.items[0].source_uuid -eq 'board-uuid') 'Se altero el tablero.'
    Assert ($scene.settings.items[1].source_uuid -eq $bg[0].uuid -and $scene.settings.items[2].source_uuid -eq 'camera-uuid') 'Orden de capas incorrecto.'
    Assert ($scene.settings.items[1].bounds.x -eq 320 -and $scene.settings.items[1].bounds.y -eq 240) 'El fondo no coincide con el recuadro.'
    Assert ($scene.settings.items[1].pos.x -eq 50 -and $scene.settings.items[2].scale.x -eq 0.5) 'Se cambio el encuadre de la camara.'
    Assert ($camera.settings.sentinel -eq 'retain' -and $p.modules.sentinel -eq 'retain') 'Se alteraron ajustes ajenos.'
    Assert (($camera.filters | Where-Object id -eq 'color_filter').settings.gamma -eq 0.3) 'Se altero otro filtro.'
    $active=@($camera.filters | Where-Object { $_.enabled -and $_.id -in @('background_removal','nv_greenscreen_filter') })
    $expected=if($engine -eq 'CPU'){'background_removal'}else{'nv_greenscreen_filter'}
    Assert ($active.Count -eq 1 -and $active[0].id -eq $expected) 'El motor activo es incorrecto.'
    if($engine -eq 'NVIDIA'){Assert ($active[0].settings.mode -eq 1 -and $active[0].settings.processing_interval -eq 1) 'Modo RTX incorrecto.'}
}
$backups=@(Get-ChildItem $scratch -Filter '*background-backup*')
Assert ($backups.Count -eq 4) 'Faltan respaldos.'
$first=$backups | Where-Object { (Get-FileHash -LiteralPath $_.FullName).Hash -eq $original.Hash } | Select-Object -First 1
Assert ($null -ne $first) 'No existe respaldo exacto del original.'
& "$root/scripts/Restore-OBSCollection.ps1" -BackupPath $first.FullName -CollectionPath $collection
Assert ((Get-FileHash -LiteralPath $collection).Hash -eq $original.Hash) 'La restauracion no recupero el original.'
# Un nombre de fuente ocupado debe fallar sin modificar el documento.
$before=(Get-FileHash -LiteralPath $collection).Hash
$rejected=$false
try { & "$root/scripts/Set-OBSBackground.ps1" @parameters -Engine CPU -BackgroundName Board } catch { $rejected=$true }
Assert $rejected 'No rechazo un nombre ocupado.'
Assert ((Get-FileHash -LiteralPath $collection).Hash -eq $before) 'Un error modifico el archivo.'
Write-Output "OK: simulacion, ambos motores, cambios repetidos, preservacion, colisiones y restauracion. Fixture: $scratch"
