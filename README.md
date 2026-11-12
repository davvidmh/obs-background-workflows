# Fondos automatizados para OBS: CPU y NVIDIA RTX

Dos flujos para sustituir el fondo de una webcam por una imagen local en OBS Studio para Windows. Instalan el motor correspondiente, activan un solo filtro y colocan la imagen inmediatamente debajo de la cámara, conservando las demás fuentes.

| Método | Motor | Uso |
| --- | --- | --- |
| CPU | obs-backgroundremoval 1.4.1, modelo Robust Video Matting, 2 hilos | Equipos sin RTX; mayor carga de CPU |
| NVIDIA | NVIDIA Video Effects SDK 0.7.6 Ampere, filtro nativo de OBS en modo Performance | GeForce RTX serie 30, incluida RTX 3070 |

La instalación del método NVIDIA abre el asistente oficial: puede solicitar elevación y requiere cerrarlo al terminar. La descarga, verificación y configuración de escena están automatizadas; no se promete instalación totalmente desatendida. No hace falta ejecutar la aplicación NVIDIA Broadcast.

## Requisitos

- Windows x64, PowerShell 7.2 o posterior (`pwsh`) y OBS instalado. Referencia de implementación: OBS 32.2.2.
- Cámara ya agregada directamente a una escena. Sin grupos, rotación ni recortes. Límites admitidos: ninguno o Stretch.
- **OBS completamente cerrado** durante la instalación, configuración y restauración.
- Imagen propia en una ruta permanente. No se distribuyen imágenes ni escenas personales.
- Para instalar plugins en ProgramData puede hacer falta una consola elevada. NVIDIA requiere un controlador compatible; el script no modifica los drivers.
- Para NVIDIA se valida que exista una RTX serie 30. Para otras series consulta el [centro oficial de descargas](https://www.nvidia.com/en-us/geforce/broadcasting/broadcast-sdk/resources/); no uses el paquete Ampere indiscriminadamente.

## 1. Identificar tu colección y cámara

Las colecciones de OBS suelen estar en `$env:APPDATA/obs-studio/basic/scenes`. Usa el archivo **exacto** de tu colección, no un respaldo. Consulta los nombres sin modificar archivos:

```powershell
Get-ChildItem "$env:APPDATA/obs-studio/basic/scenes" -Filter *.json
$collection = "$env:APPDATA/obs-studio/basic/scenes/Untitled.json"
(Get-Content -LiteralPath $collection -Raw | ConvertFrom-Json).sources |
    Select-Object name, id
```

Los ejemplos asumen `Scene`, `Video Capture Device` y una cámara de **640×480**. Cambia estos valores si tu configuración es diferente. El script usa esas dimensiones y la escala guardada para cubrir el recuadro; no detecta automáticamente la resolución de la webcam. Los filtros de la cámara son compartidos por todas las escenas que reutilicen esa fuente.

## 2. Ejecutar uno de los dos flujos

Desde la raíz del repositorio, en PowerShell 7:

```powershell
$collection = "$env:APPDATA/obs-studio/basic/scenes/Untitled.json"
$image = "$env:USERPROFILE/Downloads/Backgrounds_Page.webp"

# A. Motor general de CPU
./scripts/Start-Workflow.ps1 -Engine CPU -Install `
    -ImagePath $image -CollectionPath $collection `
    -SceneName 'Scene' -CameraName 'Video Capture Device' `
    -CameraWidth 640 -CameraHeight 480

# B. Motor de NVIDIA para RTX serie 30: ejecutar en lugar del anterior
./scripts/Start-Workflow.ps1 -Engine NVIDIA -Install `
    -ImagePath $image -CollectionPath $collection `
    -SceneName 'Scene' -CameraName 'Video Capture Device' `
    -CameraWidth 640 -CameraHeight 480
```

Omite `-Install` para cambiar entre motores ya instalados. Se conserva desactivado el filtro alternativo como respaldo. Repetir el flujo actualiza el fondo administrado sin duplicarlo. El nombre predeterminado es `Fondo automatizado`; usa `-BackgroundName` si necesitas otro. Un nombre ocupado por una fuente ajena se rechaza.

Puedes inspeccionar la operación sin descargar, instalar o escribir:

```powershell
./scripts/Start-Workflow.ps1 -Engine NVIDIA -ImagePath $image `
    -CollectionPath $collection -WhatIf
```

Cada escritura genera un respaldo junto al JSON. Se preservan el encuadre de la cámara, el orden de las otras fuentes y los ajustes ajenos. La imagen se estira al tamaño del recuadro; si su proporción difiere, habrá deformación. No se cierra OBS automáticamente ni se inicia emisión, grabación o apagado.

## 3. Verificar en OBS

1. Abre OBS y selecciona la colección modificada.
2. En los filtros de la cámara debe estar activo **solo** el motor elegido. Si el filtro falta, cierra y reinicia OBS tras comprobar la instalación.
3. Confirma que tú apareces sobre tu imagen y que la habitación queda oculta. Revisa cabello, manos y movimientos con buena iluminación.
4. En **View → Stats**, reinicia los contadores y observa FPS, tiempo por fotograma y pérdidas por renderizado. Una escena a 60 FPS dispone de aproximadamente 16.7 ms por fotograma; eso no convierte una webcam de 30 FPS en una de 60.
5. Los registros están en `$env:APPDATA/obs-studio/logs`. Para NVIDIA busca `NVIDIA VIDEO FX` y `enabled, redistributable found`; comprueba que no haya errores del filtro.

La prueba original en una RTX 3070 mostró 60 FPS de composición y 0 pérdidas en 3,962 fotogramas, con unos 5.7 ms por fotograma. Es una observación de ese equipo, con la persona ausente durante la medición final; no mide calidad de bordes en movimiento ni garantiza el mismo resultado en otros equipos. Los tests del repositorio verifican JSON y respaldos, no rendimiento real de GPU o cámara.

## Restaurar

Con OBS cerrado, elige un respaldo creado por el script:

```powershell
./scripts/Restore-OBSCollection.ps1 `
    -BackupPath '/ruta/a/Untitled.json.background-backup-ID.json' `
    -CollectionPath $collection
```

También guarda el estado actual antes de restaurar. No desinstala motores.

## Descargas y procedencia

Las versiones están fijadas; el script comprueba SHA256 antes de copiar o ejecutar. Si un proveedor cambia el archivo, la comprobación falla y no continúa. El instalador NVIDIA 0.7.6 descargado en la implementación original tenía una firma de desarrollo cuya cadena Windows no pudo validar; por eso se fija además el hash de los bytes obtenidos desde el enlace HTTPS oficial. No se cambian certificados ni controles de seguridad. El hash fijado verifica identidad del archivo de referencia, no constituye una auditoría de su código.

- [obs-backgroundremoval: repositorio y versiones](https://github.com/royshil/obs-backgroundremoval/releases/tag/1.4.1).
- [Instalación oficial en ProgramData](https://royshil.github.io/obs-backgroundremoval/windows/INSTALL.html) y [guía de uso](https://royshil.github.io/obs-backgroundremoval/usage.html).
- [NVIDIA Video Effects: redistribuibles por generación de GPU](https://www.nvidia.com/en-us/geforce/broadcasting/broadcast-sdk/resources/).
- [Filtro NVIDIA en el código oficial de OBS 32.2.2](https://github.com/obsproject/obs-studio/blob/32.2.2/plugins/nv-filters/nvidia-videofx-filter.c).

Los binarios se descargan desde sus proveedores y conservan sus propias licencias. Este repositorio no redistribuye instaladores, modelos, código de OBS ni imágenes de terceros.

## Pruebas

```powershell
pwsh -NoProfile -File ./tests/Test-Workflows.ps1
```

GitHub Actions ejecuta análisis de sintaxis y pruebas con una colección ficticia: ambos motores, cambios repetidos, respaldo, restauración, simulación y preservación de otras fuentes. Los workflows de Actions **validan scripts**; la instalación y configuración se ejecutan localmente en el equipo con OBS.
