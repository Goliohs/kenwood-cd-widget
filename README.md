# Kenwood CD Player Widget — QuickShell (zesis)

QML CD audio player skin emulando el display VFD del Kenwood DPX-770MD.
Construido para QuickShell sobre Hyprland.

## Contenido

- `widgets/` — Componentes QML
  - `CdPlayerWidget.qml` — Widget principal (bezel, LCD, header, DotMatrix, EQ, control row)
  - `CdPlayerService.qml` — Singleton (polling, themes, fonts, signals, metadata fetch)
  - `CdButton.qml` — Botón LCD segmentado
  - `DotMatrixPanel.qml` — Matriz de puntos con scroll
- `scripts/cd-player.sh` — Backend cdparanoia + mpv (reemplaza Audacious)
- `DESIGN.md` — Documentación de diseño completo

## Arquitectura del backend

El script `cd-player.sh` usa **cdparanoia + mpv IPC** en vez de Audacious:

```
┌─────────────┐     ┌──────────────┐     ┌──────────────┐
│ QML widget  │ ──> │ cd-player.sh │ ──> │ cdparanoia   │
│ poll 1s     │     │ (bash)       │     │ (rip wav)    │
└──────┬──────┘     └──────┬───────┘     └──────────────┘
       │                   │
       │                   v
       │             ┌──────────────┐
       │             │ mpv IPC sock │
       │             │ /tmp/cd-sock │
       │             └──────┬───────┘
       │                    │
       └─ tracks-json <─────┘
         state              socat bridge
         launch/toggle
         next/prev/stop
```

- **Rip on-demand**: cdparanoia escribe `/tmp/cdplayer-rip/trk-NN.wav`
- **Playback**: mpv via `--input-ipc-server=/tmp/cdplayer.sock` (idle yes, paused)
- **Control**: bash ↔ socat ↔ mpv JSON IPC
- **systemd-run --user --scope** mantiene mpv vivo tras SSH disconnect
- **Metadata**: `libdiscid` + Discogs API (MusicBrainz inalcanzable en muchas redes)
- **Cache**: `~/.cache/cdplayer/meta-<discid>.json`

## Comandos del script

| Comando       | Salida                                                                       |
|---------------|------------------------------------------------------------------------------|
| `check`       | `audio-cd` \| `no-cd`                                                        |
| `state`       | JSON completo: cdState, discid, trackNum, state, pos, total, title, artist... |
| `tracks-json` | JSON álbum: `{count, meta:{artist, album, year, tracks:[{n,title,duration}]}}` |
| `discid`      | String DiscID                                                               |
| `launch`      | Lanza mpv + reproduce track 1 (o último si state persiste)                  |
| `toggle`      | Pause/resume                                                                |
| `next`        | Track siguiente (wrap desde track N → 1)                                    |
| `prev`        | Track anterior (from stopped → track 1)                                     |
| `stop`        | Pause + seek 0 + playlist-clear (state → track 0)                           |
| `eject`       | Stop + cleanup + eject físico (intenta, falla silenciosamente en slim drives) |
| `close`       | Stop + cleanup (sin eject físico)                                           |
| `cleanup`     | Borra /tmp/cdplayer*                                                        |

## Requisitos

- QuickShell (`quickshell-git` 0.3.0+)
- Qt 6 + `qt6-tools` (para `qt_add_qml_module`)
- `cdparanoia` (rip audio)
- `mpv` + `socat` (playback + IPC)
- `python-discid` + `libdiscid` (DiscID calculation)
- `cd-info` (libcdio-utils, MCN/ISRC reading)
- `jq` (opcional, para inspección manual)
- Fonts DSEG7 Classic + DSEG14 Classic en `/usr/share/fonts/dseg/`
- Hyprland (opcional, para keybindings)
- PipeWire (salida audio)

### Arch Linux install

```bash
sudo pacman -S cdparanoia mpv socat libdiscid libcdio python-pip
pip install --user discid
# DSEG fonts: descargar de https://www.keshikan.net/fonts-e.html
#              y copiar a /usr/share/fonts/dseg/
```

## Instalación del widget

```bash
# 1. Copiar widgets
mkdir -p ~/.config/quickshell/zesis/Widgets/CdPlayer
cp widgets/*.qml ~/.config/quickshell/zesis/Widgets/CdPlayer/

# 2. Copiar script
cp scripts/cd-player.sh ~/.config/quickshell/zesis/scripts/
chmod +x ~/.config/quickshell/zesis/scripts/cd-player.sh

# 3. Registrar en DesktopWidgetCatalog.qml (entrada cd-player)
# 4. Añadir 'cd-player' a _wantsInput whitelist en DesktopWidget.qml

# 5. Recargar QuickShell
qs -c zesis
```

## Estado de "no CD" / "stopped"

Cuando no hay CD o el playback está parado, el widget muestra:
- `trackNum: 0`
- `title`, `artist`, `album` vacíos
- `state: "stopped"`
- LCD con reloj fantasma y(segmentos apagados)

> Nota: el lector DVD±RW GT10N (laptop slim) a veces reporta `lsblk SIZE=0` durante el spin-down.
> El script hace fallback a la mtime del state file (10s) para evitar flapping de `cdState`.

## DiscID y metadata

- DiscID: calculado con `libdiscid` (formato CDDB2, compatible con Discogs/MusicBrainz)
- Metadata: Discogs API primero, cacheada en `~/.cache/cdplayer/meta-<discid>.json`
- Si Discogs falla, fallback a "Track N" genérico

## Documentación

Ver [`DESIGN.md`](DESIGN.md) para specs completos: layout vertical, EQ visualizer detalles, themes, fontstack, effects.

## Fuente

Skin basado en el Kenwood DPX-770MD display. Imágenes de referencia en `/home/Helios/kenwood-research/dpx-7000md/`.

## Licencia

MIT
