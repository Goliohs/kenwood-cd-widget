# Kenwood CD Player Widget — QuickShell (zesis)

QML CD audio player skin emulando el display VFD del Kenwood DPX-770MD.
Construido para QuickShell sobre Hyprland.

## Contenido

- `widgets/` — Componentes QML
  - `CdPlayerWidget.qml` — Widget principal (bezel, LCD, header, DotMatrix, EQ, control row)
  - `CdPlayerService.qml` — Singleton (polling, themes, fonts, signals)
  - `CdButton.qml` — Botón LCD segmentado
  - `DotMatrixPanel.qml` — Matriz de puntos con scroll
- `scripts/cd-player.sh` — Backend Audacious headless
- `DESIGN.md` — Documentación de diseño completo

## Requisitos

- QuickShell (`quickshell-git` 0.3.0+)
- Qt 6 + `qt6-tools` (para `qt_add_qml_module`)
- Audacious 4.6+ + `audtool` + `cdparanoia`
- Fonts DSEG7 Classic + DSEG14 Classic en `/usr/share/fonts/dseg/`
- Hyprland (opcional, para keybindings)
- PipeWire (salida audio)

## Instalación

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

## Documentación

Ver [`DESIGN.md`](DESIGN.md) para specs completos: layout vertical, EQ visualizer detalles, themes, fontstack, backend, effects.

## Fuente

Skin basado en el Kenwood DPX-770MD display. Imágenes de referencia en `/home/Helios/kenwood-research/dpx-7000md/`.

## Licencia

MIT
