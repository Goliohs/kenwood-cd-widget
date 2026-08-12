#!/usr/bin/env bash
# CD Music Player - Audacious backend for QuickShell CdPlayer widget
# Auto-detects CD-ROM device and loads audio CD tracks using cdaudio-ng plugin
# Uses cdda://?N URI format (Audacious cdaudio-ng syntax)
# Outputs JSON for consumption by CdPlayerService.qml

CD_DEVICE=$(awk '/^drive name:/ {print $NF; exit}' /proc/sys/dev/cdrom/info 2>/dev/null)
[ -z "$CD_DEVICE" ] || [ "$CD_DEVICE" = "name:" ] && CD_DEVICE="sr0"
CD_DEVICE="/dev/$CD_DEVICE"

export DISPLAY=:0
export WAYLAND_DISPLAY=wayland-1
export XDG_RUNTIME_DIR=/run/user/1000
export QT_QPA_PLATFORM=xcb

check_cd() {
  SIZE=$(lsblk -b -n -o SIZE "$CD_DEVICE" 2>/dev/null | tr -d ' ')
  if [ -z "$SIZE" ] || [ "$SIZE" = "0" ]; then
    echo "no-cd"
    return 1
  fi
  echo "audio-cd"
  return 0
}

count_tracks() {
  cdparanoia -Q -d "$CD_DEVICE" 2>&1 | grep -cE '^[[:space:]]+[0-9]+\.'
}

list_tracks() {
  cdparanoia -Q -d "$CD_DEVICE" 2>&1 | awk '/^[[:space:]]+[0-9]+\./ {
    n = $1; gsub(/\./, "", n);
    len = $2;
    printf "{\"n\":%s,\"sectors\":%s}\n", n, len;
  }'
}

is_running() {
  pgrep -x audacious >/dev/null 2>&1
}

current_track() {
  if is_running; then
    local fn
    fn=$(audtool current-song-filename 2>/dev/null || echo "")
    TRACK_N=$(echo "$fn" | sed -n 's/^cdda:\/\/?\([0-9]*\).*/\1/p')
    [ -z "$TRACK_N" ] && TRACK_N=$(audtool playlist-position 2>/dev/null || echo "0")
    echo "$TRACK_N"
  else
    TRACK_N=0
    echo "0"
  fi
}

playback_state() {
  if ! is_running; then
    echo "stopped"
    return
  fi
  local st
  st=$(audtool playback-status 2>/dev/null)
  case "$st" in
    playing) echo "playing" ;;
    paused)  echo "paused" ;;
    *)       echo "stopped" ;;
  esac
}

playback_time() {
  if is_running; then
    audtool current-song-output-length-seconds 2>/dev/null || echo "0"
  else
    echo "0"
  fi
}

playback_total() {
  if is_running; then
    audtool current-song-length-seconds 2>/dev/null || echo "0"
  else
    echo "0"
  fi
}

song_title() {
  local track_n
  track_n=$(current_track)
  if is_running; then
    local t
    t=$(audtool current-song-tuple-data title 2>/dev/null)
    if [ -n "$t" ] && [ "$t" != "Track $track_n" ]; then
      echo "$t"
    else
      cddb_local_lookup "$track_n" title
    fi
  else
    cddb_local_lookup "$track_n" title
  fi
}

song_artist() {
  local track_n
  track_n=$(current_track)
  if is_running; then
    local a
    a=$(audtool current-song-tuple-data artist 2>/dev/null)
    if [ -n "$a" ] && [ "$a" != "Audio CD" ]; then
      echo "$a"
    else
      cddb_local_lookup "$track_n" artist
    fi
  else
    cddb_local_lookup "$track_n" artist
  fi
}

song_album() {
  local track_n
  track_n=$(current_track)
  if is_running; then
    local al
    al=$(audtool current-song-tuple-data album 2>/dev/null)
    if [ -n "$al" ] && [ "$al" != "Audio CD" ]; then
      echo "$al"
    else
      cddb_local_lookup "$track_n" album
    fi
  else
    cddb_local_lookup "$track_n" album
  fi
}

CURRENT_TRACK_N=0

cddb_local_lookup() {
  local track_n=$1 field=$2
  local dir="$HOME/.cddb/musicbrainz"
  [ ! -d "$dir" ] && dir="$HOME/.cddb/freedb"
  [ ! -d "$dir" ] && { echo ""; return; }
  local latest newest_mtime=0
  while read -r f; do
    local m
    m=$(stat -c %Y "$f" 2>/dev/null || echo 0)
    if [ "$m" -gt "$newest_mtime" ]; then
      newest_mtime=$m
      latest="$f"
    fi
  done < <(find "$dir" -type f 2>/dev/null)
  [ -z "$latest" ] && { echo ""; return; }
  local dtit
  dtit=$(awk -F'=' '/^DTITLE=/ {print $2; exit}' "$latest")
  local artist album
  artist=$(echo "$dtit" | awk -F'/' '{print $1}' | sed 's/^ *//;s/ *$//')
  album=$(echo "$dtit" | awk -F'/' '{print $2}' | sed 's/^ *//;s/ *$//')
  case "$field" in
    artist) echo "$artist" ;;
    album)  echo "$album" ;;
    title)
      [ "$track_n" -gt 0 ] 2>/dev/null || track_n=1
      local idx=$((track_n - 1))
      awk -F'=' -v idx="$idx" '$1=="TTITLE"idx {sub(/^[^=]*=/,""); print; exit}' "$latest"
      ;;
    *) echo "" ;;
  esac
}

launch_player() {
  if is_running; then
    audtool playback-play 2>/dev/null
    return
  fi
  pkill -x audacious 2>/dev/null
  sleep 0.5
  sed -i "s|^device=.*|device=$CD_DEVICE|" ~/.config/audacious/config 2>/dev/null
  setsid -f audacious --headless --qt >/dev/null 2>&1
  for i in $(seq 1 20); do
    sleep 0.5
    if audtool playback-status >/dev/null 2>&1; then
      break
    fi
  done
  sleep 1
  local num
  num=$(count_tracks)
  if [ -z "$num" ] || [ "$num" -lt 1 ]; then
    return 1
  fi
  for i in $(seq 1 "$num"); do
    audtool playlist-addurl "cdda://?$i" 2>/dev/null
  done
  sleep 1
  audtool playback-play 2>/dev/null
}

close_player() {
  pkill -x audacious 2>/dev/null
}

toggle_playback() {
  if is_running; then
    audtool playback-playpause 2>/dev/null
  else
    launch_player
  fi
}

next_track() {
  audtool playlist-advance 2>/dev/null
}

prev_track() {
  audtool playlist-reverse 2>/dev/null
}

stop_playback() {
  audtool playback-stop 2>/dev/null
}

eject() {
  stop_playback
  close_player
  sleep 0.5
  eject "$CD_DEVICE" 2>/dev/null || eject -T "$CD_DEVICE" 2>/dev/null
}

status_json() {
  local cd_state track_n state pos total title artist album
  cd_state=$(check_cd)
  track_n=$(current_track)
  TRACK_N=$track_n
  state=$(playback_state)
  pos=$(playback_time)
  total=$(playback_total)
  title=$(song_title | tr -d '\n' | sed 's/"/\\"/g')
  artist=$(song_artist | tr -d '\n' | sed 's/"/\\"/g')
  album=$(song_album | tr -d '\n' | sed 's/"/\\"/g')
  printf '{"cdState":"%s","trackNum":%s,"state":"%s","pos":%s,"total":%s,"device":"%s","title":"%s","artist":"%s","album":"%s"}\n' \
    "$cd_state" "$track_n" "$state" "$pos" "$total" "$CD_DEVICE" "$title" "$artist" "$album"
}

case "$1" in
  check)    check_cd ;;
  tracks)   count_tracks ;;
  list)     list_tracks ;;
  launch)   launch_player ;;
  close)    close_player ;;
  toggle)   toggle_playback ;;
  next)     next_track ;;
  prev)     prev_track ;;
  stop)     stop_playback ;;
  eject)    eject ;;
  status)   playback_state ;;
  position) current_track ;;
  pos-time) playback_time ;;
  total)    playback_total ;;
  state)     status_json ;;
  auto)
    TYPE=$(check_cd)
    if [ "$TYPE" = "audio-cd" ]; then
      launch_player
    fi
    ;;
  *)
    echo "Usage: $0 {check|tracks|list|launch|close|toggle|next|prev|stop|eject|status|position|pos-time|total|state|auto}"
    exit 1
    ;;
esac
