# CD Player Widget — Kenwood DPX-770MD Skin

Skin del reproductor de CD de audio emulando el display VFD del Kenwood DPX-770MD, construido completamente en QML sobre QuickShell.

## Estructura

| Archivo | Rol |
|---|---|
| `CdPlayerWidget.qml` | Widget principal — bezel, LCD cutout, header (clock/TRK/pos), DotMatrixPanel, EQ visualizer, control row |
| `CdPlayerService.qml` | Singleton — polling status/trackList/clock/EQ, theme cycling, fonts, colors, signals |
| `CdButton.qml` | Botón LCD segmentado — label, highlight, highlightColor, signal clicked |
| `DotMatrixPanel.qml` | Panel matriz de puntos — N celdas 14-segmentos, scroll carácter-a-carácter Timer 420ms, ghost "8" + char activo con MultiEffect glow |
| `scripts/cd-player.sh` | Backend Audacious headless — auto-detección CD-ROM, cdparanoia, audtool, cddb_local_lookup fallback MusicBrainz |

## Layout vertical (280px LCD interior)

```
┌───────────────────────────────────┐
│ HEADER (38px)                     │  Clock ghost "88:88" + activo | CD | ▶ | TRK## | pos / total
├───────────────────────────────────┤
│ DOT-MATRIX PANEL (24px)           │  28 celdas DSEG14, scroll 420ms
├───────────────────────────────────┤
│ EQ VISUALIZER (200px)             │
│  • 11 columnas centradas          │
│  • Cada barra: 16 segmentos "--"  │  (dos rects 8×8 paralelos con 1px gap)
│  • Puntos laterales encendidos    │  (16 dots 3×3 izq + 16 der, opacidad 0.70 playing)
│  • Freq labels al fondo (12px)    │  31 63 125 250 500 1k 2k 4k 8k 16k 32k
│  • Tilt 3D 38° pivot en el top    │  "pista de aterrizaje" wide-bottom narrow-top
├───────────────────────────────────┤
│ CTRL ROW (36px, fuera del LCD)    │  físico #181818, prev/play/stop/next/eject/CLR
└───────────────────────────────────┘
```

## EQ Visualizer — Detalles visuales

- **Barras**: 16 segmentos cada una, encienden de abajo↑arriba. `barLevel = _eqBars[i] * 16.0`, segmento lit si `(15 - idx) < _litCount`. Peak = segmento cima con `Qt.lighter(_seg, 1.15)`.
- **`--` per LED**: Cada segmento se dibuja como dos `Rectangle { 8×8, radius:1 }` paralelos con 1px gap entre ellos. La perspectiva 3D tilt produce la convergencia visual hacia el horizonte (de `--` ancho abajo a `-` estrecho arriba).
- **Puntos laterales**: Columnas de 16 dots `Rectangle { 3×3, radius:1.5, opacity: 0.70 playing | 0.20 stopped }` a cada lado de la barra animada.
- **Freq labels** centradas con `anchors.horizontalCenter: parent.horizontalCenter`, debajo de las barras.

## Themes (cycleTheme)

CdPlayerService.define tres themes (amber/white/cyan) con colores:
- `colLcdSeg` — color de los segmentos activos (R, G, B valores)
- `colLcdDim` — para elementos secundarios (source "CD", "/" separator)
- `colLcdBg` — fondo del LCD (#000000)
- `colLcdGhost` — para los "8" / "88" ghost detrás de los activos

Toggle con botón "CLR".

## FontStack

- `fontSegment7` → "DSEG7 Classic" — clock, track num, pos/total, freq labels, EQ labels
- `fontSegment14` → "DSEG14 Classic" — DotMatrixPanel chars y ghost
- `fontMono` → Font Awesome / monospace — labels "CD", "TRK", play pip "▶",

Fonts instaladas en `/usr/share/fonts/dseg/`.

## Backend (cd-player.sh)

Audacious headless:
- Auto-detección CD-ROM en `/dev/sr0`
- `cdparanoia` para TOC
- `audtool` para status, posición, track number
- Metadata CD recuperado del cache MusicBrainz local (`~/.cddb/musicbrainz/`)
- Config Audacious: `use_cddb=true`, `cddb_server=gnudb.org`, skin Winamp2.9, PipeWire output

## Visual Effects

- **INNER Shadow tunnel**: `MultiEffect` con `shadowScale: 1.18` simulando el tunnel/vignette del LCD de pocket
- **Glass overlay**: Sutil dark-blue gradient 3-5% opacity simulando el front polarizer
- **Glow neón**: Cada segmento-activo Text tiene `MultiEffect { shadowOpacity: 0.85, shadowBlur: 1.0, shadowScale: 1.45, brightness: 0.18 }`

## Poling cadence

| Timer | Interval | Función |
|---|---|---|
| statusTimer | 1s | Polling cdState |
| trackListTimer | 5s | Refresh trackList |
| clockTimer | 10s | Update clock HH:MM |
| eqTimer | 90ms | Animated EQ bars (seno + random) |

## Registro en zesis

- **DesktopWidgetCatalog.qml**: entrada `cd-player` con `componentName`, `iconName`, `argType`
- **DesktopWidgetStore.qml**: `targetMonitors`, `configMode`
- **DesktopWidget.qml**: `_wantsInput` whitelist incluye `cd-player` (línea 74)

## Key technical notes

- QML `stateChanged` es built-in — renombrado a `playStateChanged` en CdPlayerService
- `pragma Singleton` + `Singleton { id: root }` para service singletons
- `Process` con `SplitParser` para async stdout
- `Quickshell.shellDir` para paths absolutos
- `_eqBars` array size = 11 (mapea 1:1 a los 11 columnas renderizadas)
- Debug commún: si hay 2 procesos `qs -c zesis` corriendo → barras duplicadas. Matar uno con `kill <PID>`

## Lanzar (via SSH)

```bash
setsid -f env WAYLAND_DISPLAY=wayland-1 XDG_RUNTIME_DIR=/run/user/1000 bash -c 'exec qs -c zesis' >/tmp/zesis-stdout.log 2>&1 </dev/null
```

## To restore

1. Install fonts: `sudo pacman -S dseg-fonts` or copy to `/usr/share/fonts/dseg/`
2. Install deps: `audacious audtool cdparanoia`
3. Copy CdPlayer/ folder to `~/.config/quickshell/zesis/Widgets/CdPlayer/`
4. Copy script to `~/.config/quickshell/zesis/scripts/cd-player.sh` (chmod +x)
5. Register in DesktopWidgetCatalog.qml
6. Add `cd-player` to `_wantsInput` whitelist in DesktopWidget.qml
7. Reload zesis: `qs -c zesis`
