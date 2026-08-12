#!/usr/bin/env bash
# CD Music Player - cdparanoia+mpv backend for QuickShell CdPlayer widget
#
# Why cdparanoia+mpv instead of Audacious?
# Audacious' cdaudio-ng plugin fails to read from /dev/sr0 in our Arch setup
# (plugin loads but reports "Searching, 0 files found" and dies).
# cdparanoia reads TOC and audio sectors perfectly.
# mpv plays the ripped WAV via IPC socket with full position/duration support.
#
# Architecture:
#   - DiscID via libdiscid (python-discid)
#   - Metadata via Discogs API (MusicBrainz unreachable from this network)
#   - Cache: ~/.cache/cdplayer/meta-<discid>.json
#   - Rip: /tmp/cdplayer-<discid>/trk-NN.wav  (on-demand, one track at a time)
#   - Playback: mpv --input-ipc-server=/tmp/cdplayer.sock
#   - Control: socat <-> mpv JSON IPC
#
# All commands output JSON suitable for CdPlayerService.qml consumption.

set -uo pipefail

# ─── Environment (Wayland for PipeWire) ────────────────────────────────────────
export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-1}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/1000}"
export QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-wayland}"

# ─── Constants ────────────────────────────────────────────────────────────────
CD_DEVICE="${CD_DEVICE:-$(awk '/^drive name:/ {print $NF; exit}' /proc/sys/dev/cdrom/info 2>/dev/null)}"
[ -z "$CD_DEVICE" ] || [ "$CD_DEVICE" = "name:" ] && CD_DEVICE="sr0"
CD_DEVICE="/dev/$CD_DEVICE"

CACHE_DIR="$HOME/.cache/cdplayer"
SOCK="/tmp/cdplayer.sock"
PID_FILE="/tmp/cdplayer.mpv.pid"
RIP_BASE="/tmp/cdplayer-rip"
STATE_FILE="/tmp/cdplayer.state"   # echoes current discid + track (resilient)

mkdir -p "$CACHE_DIR"

# ─── Helpers ──────────────────────────────────────────────────────────────────
log() { printf '[cdplayer] %s\n' "$*" >&2; }

# Send a single IPC command to mpv, return data field (or empty on error)
mpv_ipc() {
  local cmd="$1"
  local resp
  resp=$(printf '%s\n' "$cmd" | socat - UNIX-CONNECT:"$SOCK" 2>/dev/null)
  [ -z "$resp" ] && { echo ""; return 1; }
  echo "$resp" | python3 -c "
import json, sys
try:
    r = json.loads(sys.stdin.read())
    if r.get('error') == 'success':
        v = r.get('data')
        if v is None:
            print('')
        elif isinstance(v, bool):
            print('true' if v else 'false')
        elif isinstance(v, (dict, list)):
            print(json.dumps(v))
        else:
            print(v)
    else:
        print('')
except Exception:
    print('')
" 2>/dev/null
}

# mpv alive?
mpv_running() {
  [ -S "$SOCK" ] || return 1
  [ -f "$PID_FILE" ] || return 1
  local pid
  pid=$(cat "$PID_FILE" 2>/dev/null)
  [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null
}

# ─── Disc detection ───────────────────────────────────────────────────────────
check_cd() {
  # Audio-CD detection via lsblk block device size.
  # - Fast path: lsblk reports non-zero size → audio-cd
  # - If lsblk reports 0 or empty, the drive may be spinning down/spinning up.
  #   We check the state file: if we recorded an audio-cd recently (within 10s),
  #   trust the last-known state during the spin-up gap.
  local size
  size=$(lsblk -b -n -o SIZE "$CD_DEVICE" 2>/dev/null | tr -d ' ')
  if [ -n "$size" ] && [ "$size" != "0" ]; then
    echo "audio-cd"
    return 0
  fi
  # lsblk empty/0 — check state file mtime as fallback (within 10s of last play)
  if [ -f "$STATE_FILE" ]; then
    local discid age_ms
    discid=$(read_state_discid)
    if [ -n "$discid" ]; then
      # File age in milliseconds
      age_ms=$(( $(date +%s%3N) - $(stat -c %Y "$STATE_FILE" 2>/dev/null || echo 0) * 1000 ))
      # If state was touched in the last 10 seconds, trust the audio-cd
      if [ "$age_ms" -lt 10000 ]; then
        echo "audio-cd"
        return 0
      fi
    fi
  fi
  echo "no-cd"
  return 1
}

# Count audio tracks via cdparanoia TOC
count_tracks() {
  cdparanoia -Q -d "$CD_DEVICE" 2>&1 | grep -cE '^[[:space:]]+[0-9]+\.'
}

# Get expected minimum WAV size for track N (from cached metadata)
# Audio CD: 75 sectors/sec * 2352 bytes/sector = 176400 bytes/sec + 44-byte WAV header
# Output: minimum bytes (we accept ≥ expected_min; 5% margin for rounding)
track_expected_size() {
  local n="$1" discid meta_file dur_secs
  discid=$(read_state_discid)
  [ -z "$discid" ] && discid=$(get_discid)
  [ -z "$discid" ] && return 1
  meta_file="$CACHE_DIR/meta-${discid}.json"
  [ -f "$meta_file" ] || return 1
  dur_secs=$(python3 -c "
import json
try:
    m = json.load(open('$meta_file'))
    for t in m.get('tracks', []):
        if t.get('n') == $n:
            d = t.get('duration', '0:00')
            parts = d.split(':')
            secs = int(parts[0]) * 60 + (int(parts[1]) if len(parts) > 1 else 0)
            print(int(secs * 176400 * 0.95))
            break
except Exception:
    pass
" 2>/dev/null)
  [ -n "$dur_secs" ] && echo "$dur_secs"
}

# List tracks as JSON: [{"n":1,"sectors":17106,"mm":3,"ss":48,"ff":6}, ...]
list_tracks() {
  cdparanoia -Q -d "$CD_DEVICE" 2>&1 | awk '
    /^[[:space:]]+[0-9]+\./ {
      n = $1; gsub(/\./, "", n);
      len = $2; gsub(/\[|\]/, "", len);
      split(len, a, ":");
      sectors = a[1] * 75 + a[2];
      mm = a[1] + 0;
      ss = a[2] + 0;
      printf "{\"n\":%d,\"sectors\":%d,\"mm\":%d,\"ss\":%d}", n, sectors, mm, ss;
      if (n < total) printf ",";
    }
    /^TOTAL/ { total = 999; }
  ' | tr -d '\n'
  echo
}

# ─── DiscID + Metadata ────────────────────────────────────────────────────────
get_discid() {
  python3 -c "
import discid
try:
    d = discid.read('$CD_DEVICE')
    print(d.id)
except Exception:
    pass
" 2>/dev/null
}

get_discid_full() {
  python3 -c "
import discid, json
try:
    d = discid.read('$CD_DEVICE')
    out = {
        'discid': d.id,
        'submission_url': d.submission_url,
        'tracks': [
            {'number': t.number, 'offset': t.offset, 'length': t.length}
            for t in d.tracks
        ],
    }
    print(json.dumps(out))
except Exception as e:
    print(json.dumps({'error': str(e)}))
" 2>/dev/null
}

# Look up Discogs by artist + barcode (always tries MCN from disc, falls back to manual search)
# Output: JSON {artist, album, year, tracks:[{n, title, duration}]}
fetch_metadata_discogs() {
  local discid="$1"
  local mcn="$2"   # Media Catalog Number from cd-info
  local first_isrc="$3"

  python3 <<EOF 2>/dev/null
import json, urllib.request, urllib.parse, sys, time

DISCID = "$discid"
MCN    = "$mcn"
ISRC1  = "$first_isrc"
UA     = "HeliosCDPlayer/1.0 +https://github.com/Goliohs/kenwood-cd-widget"

def get(url, tries=3):
    for i in range(tries):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": "application/json"})
            with urllib.request.urlopen(req, timeout=10) as r:
                return json.loads(r.read())
        except Exception as e:
            if i == tries - 1:
                return None
            time.sleep(1)
    return None

# Try by ISRC first (most precise)
if ISRC1:
    res = get(f"https://api.discogs.com/database/search?q={ISRC1}&type=release")
    if res and res.get("results"):
        rid = res["results"][0]["id"]
        rel = get(f"https://api.discogs.com/releases/{rid}")
        if rel:
            tracks = []
            for t in rel.get("tracklist", []):
                n = t.get("position", "")
                try:
                    n_int = int(n)
                except:
                    n_int = 0
                dur = t.get("duration", "")
                tracks.append({"n": n_int, "title": t.get("title", ""), "duration": dur})
            artist = rel.get("artists", [{}])[0].get("name", "")
            out = {
                "artist": artist,
                "album": rel.get("title", ""),
                "year": rel.get("year", 0),
                "tracks": tracks,
                "source": "discogs-isrc",
                "release_id": rid,
            }
            print(json.dumps(out))
            sys.exit(0)
        time.sleep(1)

# Fallback: search by MCN (barcode)
if MCN:
    res = get(f"https://api.discogs.com/database/search?q={MCN}&type=release")
    if res and res.get("results"):
        rid = res["results"][0]["id"]
        rel = get(f"https://api.discogs.com/releases/{rid}")
        if rel:
            tracks = []
            for t in rel.get("tracklist", []):
                n = t.get("position", "")
                try:
                    n_int = int(n)
                except:
                    n_int = 0
                dur = t.get("duration", "")
                tracks.append({"n": n_int, "title": t.get("title", ""), "duration": dur})
            artist = rel.get("artists", [{}])[0].get("name", "")
            out = {
                "artist": artist,
                "album": rel.get("title", ""),
                "year": rel.get("year", 0),
                "tracks": tracks,
                "source": "discogs-mcn",
                "release_id": rid,
            }
            print(json.dumps(out))
            sys.exit(0)

# Failure
print(json.dumps({"error": "not found", "source": "discogs"}))
EOF
}

# Read MCN of inserted disc via cd-info
get_mcn() {
  cd-info -C "$CD_DEVICE" --no-cddb --no-device-info --no-disc-mode --no-ioctl --no-analyze --no-tracks 2>/dev/null \
    | awk -F': ' '/Media Catalog Number/ {gsub(/ /,"",$2); print $2; exit}'
}

# Read first track ISRC for matching
get_first_isrc() {
  cd-info -C "$CD_DEVICE" --no-cddb --no-device-info --no-disc-mode --no-ioctl --no-analyze --no-tracks 2>/dev/null \
    | awk -F': ' '/^TRACK  1 ISRC/ {print $2; exit}'
}

# Lookup local cache → if miss → fetch via Discogs
# Output: JSON metadata or {"error": "..."}
get_metadata() {
  local discid="$1"
  [ -z "$discid" ] && { echo '{"error":"no discid"}'; return 1; }

  local cache_file="$CACHE_DIR/meta-$discid.json"
  if [ -f "$cache_file" ]; then
    cat "$cache_file"
    return 0
  fi

  # Cache miss → fetch
  local mcn isrc
  mcn=$(get_mcn)
  isrc=$(get_first_isrc)
  log "MCN: $mcn  ISRC1: $isrc"

  local meta
  meta=$(fetch_metadata_discogs "$discid" "$mcn" "$isrc")

  if [ -n "$meta" ] && echo "$meta" | python3 -c "import json,sys; d=json.load(sys.stdin); sys.exit(0 if 'tracks' in d else 1)" 2>/dev/null; then
    echo "$meta" > "$cache_file"
    echo "$meta"
    return 0
  fi

  # Final fallback: generic track list (Track 01 ... Track NN)
  python3 <<EOF
import json
toc = """$(cdparanoia -Q -d "$CD_DEVICE" 2>&1 | awk '/^[[:space:]]+[0-9]+\./ {print $1, $2}' | tr -d '.')"""
tracks = []
try:
    tracks_count = count_tracks()
except:
    pass
EOF
  # Build from TOC
  cdparanoia -Q -d "$CD_DEVICE" 2>&1 | python3 -c "
import json, sys, re
tracks = []
for line in sys.stdin:
    m = re.match(r'\s+(\d+)\.\s+(\d+)\s+\[(\d+):(\d+)\.(\d+)\]', line)
    if m:
        n = int(m.group(1))
        tracks.append({'n': n, 'title': f'Track {n:02d}', 'duration': f'{m.group(3)}:{m.group(4)}'})
out = {'artist': 'Unknown Artist', 'album': 'Audio CD', 'year': 0, 'tracks': tracks, 'source': 'fallback-generic'}
print(json.dumps(out))
" 2>/dev/null | tee "$cache_file"
  return 0
}

# ─── State file (resilient) ───────────────────────────────────────────────────
save_state() {
  local discid="$1" track="$2"
  printf '{"discid":"%s","track":%d}\n' "$discid" "$track" > "$STATE_FILE"
}

read_state_track() {
  [ -f "$STATE_FILE" ] || { echo "1"; return; }
  python3 -c "import json; print(json.load(open('$STATE_FILE')).get('track', 1))" 2>/dev/null || echo "1"
}

read_state_discid() {
  [ -f "$STATE_FILE" ] || { echo ""; return; }
  python3 -c "import json; print(json.load(open('$STATE_FILE')).get('discid', ''))" 2>/dev/null || echo ""
}

# ─── Rip current track ───────────────────────────────────────────────────────
# Rips track N to /tmp/cdplayer-rip/trk-NN.wav
# Idempotent (skips if file exists and is non-empty)
rip_track() {
  local n="$1"
  [ -z "$n" ] || [ "$n" = "0" ] && n=1
  local ripdir="$RIP_BASE"
  mkdir -p "$ripdir"
  local out="$ripdir/trk-$(printf '%02d' "$n").wav"
  if [ -s "$out" ] && [ "$(stat -c %s "$out")" -gt 1000 ]; then
    # Validate against expected size if we have cached metadata
    # Audio CD: 2352 bytes/sector * 75 sectors/sec = 176400 bytes/sec
    # WAV header: 44 bytes; expected ≈ duration_seconds * 176400 + 44
    local expected_min
    expected_min=$(track_expected_size "$n" 2>/dev/null)
    if [ -n "$expected_min" ]; then
      local actual
      actual=$(stat -c %s "$out")
      if [ "$actual" -lt "$expected_min" ]; then
        log "cached trk-$(printf '%02d' "$n").wav is truncated ($actual < $expected_min), re-ripping"
        rm -f "$out"
      else
        echo "$out"
        return 0
      fi
    else
      echo "$out"
      return 0
    fi
  fi
  rm -f "$out"
  # -Z = disable paranoia (8x speed read) — disk is clean, no jitter correction needed
  cdparanoia -d "$CD_DEVICE" -s -Z "$n" "$out" >/dev/null 2>&1
  if [ -s "$out" ] && [ "$(stat -c %s "$out")" -gt 1000 ]; then
    echo "$out"
    return 0
  fi
  echo ""
  return 1
}

# ─── mpv control ─────────────────────────────────────────────────────────────
launch_mpv() {
  [ -S "$SOCK" ] && mpv_running && return 0
  # Cleanup stale
  rm -f "$SOCK"
  [ -f "$PID_FILE" ] && kill "$(cat "$PID_FILE")" 2>/dev/null
  # Use systemd-run --user scope to keep mpv alive after parent dies
  # (setsid hangs SSH; systemd-run is clean and doesn't block)
  systemd-run --user --scope --quiet --collect \
    --unit="cdplayer-mpv-${RANDOM}" \
    mpv --no-video --no-terminal --no-config \
    --audio-display=no --really-quiet \
    --input-ipc-server="$SOCK" \
    --idle=yes \
    --pause \
    >/tmp/cdplayer-mpv.log 2>&1 </dev/null &
  disown 2>/dev/null
  # Wait for socket to appear (mpv creates it on init)
  for i in $(seq 1 30); do
    [ -S "$SOCK" ] && break
    sleep 0.2
  done
  [ -S "$SOCK" ] || { log "mpv socket never appeared"; return 1; }
  # Save our PID
  pgrep -f "input-ipc-server=$SOCK" | head -1 > "$PID_FILE"
  return 0
}

load_track() {
  local n="$1"
  local wav
  wav=$(rip_track "$n")
  [ -z "$wav" ] && { log "rip failed for track $n"; return 1; }
  launch_mpv
  [ ! -S "$SOCK" ] && { log "mpv socket missing"; return 1; }
  # Replace playlist and play
  printf '%s\n' '{"command":["loadfile","'$wav'","replace"]}' | socat - UNIX-CONNECT:"$SOCK" >/dev/null 2>&1
  sleep 0.1
  # Unpause (start playing)
  printf '%s\n' '{"command":["set_property","pause",false]}' | socat - UNIX-CONNECT:"$SOCK" >/dev/null 2>&1
  save_state "$(read_state_discid)" "$n"
}

stop_mpv() {
  if mpv_running; then
    printf '%s\n' '{"command":["quit"]}' | socat - UNIX-CONNECT:"$SOCK" >/dev/null 2>&1
    sleep 0.3
  fi
  [ -f "$PID_FILE" ] && kill "$(cat "$PID_FILE")" 2>/dev/null
  rm -f "$SOCK" "$PID_FILE"
}

# ─── Playback state queries ───────────────────────────────────────────────────
playback_state() {
  if ! mpv_running; then echo "stopped"; return; fi
  local paused idle filename
  paused=$(mpv_ipc '{"command":["get_property","pause"]}')
  idle=$(mpv_ipc '{"command":["get_property","core-idle"]}')
  filename=$(mpv_ipc '{"command":["get_property","filename"]}')
  # No file loaded = stopped (mpv idle)
  if [ -z "$filename" ] || [ "$filename" = "null" ]; then
    echo "stopped"
    return
  fi
  if [ "$paused" = "true" ]; then
    echo "paused"
  elif [ "$idle" = "true" ]; then
    echo "stopped"
  else
    echo "playing"
  fi
}

playback_time() {
  if ! mpv_running; then echo "0"; return; fi
  local t
  t=$(mpv_ipc '{"command":["get_property","time-pos"]}')
  [ -z "$t" ] && { echo "0"; return; }
  python3 -c "print(int(float('$t')))" 2>/dev/null || echo "0"
}

playback_total() {
  if ! mpv_running; then echo "0"; return; fi
  local t
  t=$(mpv_ipc '{"command":["get_property","duration"]}')
  [ -z "$t" ] && { echo "0"; return; }
  python3 -c "print(int(float('$t')))" 2>/dev/null || echo "0"
}

# Current track (numeric, 1-based) — read from state file (not mpv, since mpv doesn't know track#)
current_track() {
  if mpv_running; then
    read_state_track
  else
    echo "0"
  fi
}

# ─── Metadata queries ─────────────────────────────────────────────────────────
# Output: {title, artist, album} for track N
track_metadata() {
  local track_n="$1"
  [ -z "$track_n" ] || [ "$track_n" = "0" ] && track_n=1
  local discid meta
  discid=$(read_state_discid)
  [ -z "$discid" ] && discid=$(get_discid)
  meta=$(get_metadata "$discid")
  echo "$meta" | python3 -c "
import json, sys
d = json.load(sys.stdin)
tracks = d.get('tracks', [])
match = [t for t in tracks if t.get('n') == $track_n]
if not match:
    print(json.dumps({'title': f'Track {$track_n:02d}', 'artist': d.get('artist', 'Unknown'), 'album': d.get('album', 'Audio CD')}))
else:
    t = match[0]
    print(json.dumps({'title': t.get('title', ''), 'artist': d.get('artist', ''), 'album': d.get('album', '')}))
" 2>/dev/null
}

song_title() {
  track_metadata "$1" | python3 -c "import json,sys; print(json.load(sys.stdin).get('title',''))" 2>/dev/null
}

song_artist() {
  track_metadata "$1" | python3 -c "import json,sys; print(json.load(sys.stdin).get('artist',''))" 2>/dev/null
}

song_album() {
  track_metadata "$1" | python3 -c "import json,sys; print(json.load(sys.stdin).get('album',''))" 2>/dev/null
}

# ─── Status JSON ──────────────────────────────────────────────────────────────
status_json() {
  local cd_state track_n state pos total discid
  local title="" artist="" album=""
  cd_state=$(check_cd)
  track_n=$(current_track)
  state=$(playback_state)
  pos=$(playback_time)
  total=$(playback_total)
  discid=$(read_state_discid)
  [ -z "$discid" ] && discid=$(get_discid)
  save_state "$discid" "$track_n"
  if [ "$cd_state" = "audio-cd" ] && [ -n "$discid" ] && [ "$track_n" -gt 0 ] 2>/dev/null; then
    title=$(song_title "$track_n" | tr -d '\n' | sed 's/"/\\"/g')
    artist=$(song_artist "$track_n" | tr -d '\n' | sed 's/"/\\"/g')
    album=$(song_album "$track_n" | tr -d '\n' | sed 's/"/\\"/g')
  fi
  printf '{"cdState":"%s","discid":"%s","trackNum":%s,"state":"%s","pos":%s,"total":%s,"device":"%s","title":"%s","artist":"%s","album":"%s"}\n' \
    "$cd_state" "$discid" "$track_n" "$state" "$pos" "$total" "$CD_DEVICE" "$title" "$artist" "$album"
}

# ─── Tracks JSON (for service init) ───────────────────────────────────────────
tracks_json() {
  local discid meta
  discid=$(get_discid)
  [ -z "$discid" ] && { echo '{"tracks":[]}'; return 1; }
  save_state "$discid" "$(read_state_track)"
  meta=$(get_metadata "$discid")
  local tracks_count
  tracks_count=$(count_tracks)
  printf '{"discid":"%s","count":%d,"meta":%s}\n' "$discid" "$tracks_count" "$meta"
}

# ─── Playback commands ─────────────────────────────────────────────────────────
launch_player() {
  local discid
  discid=$(get_discid)
  [ -z "$discid" ] && { log "no discid"; return 1; }
  local cur_state
  cur_state=$(read_state_track)
  local track_n=1
  [ -n "$cur_state" ] && [ "$cur_state" != "0" ] && [ "$cur_state" -ge 1 ] 2>/dev/null && track_n=$(read_state_track)
  save_state "$discid" "$track_n"
  load_track "$track_n"
}

toggle_playback() {
  if ! mpv_running; then
    launch_player
    return
  fi
  # Toggle pause
  local paused
  paused=$(mpv_ipc '{"command":["get_property","pause"]}')
  if [ "$paused" = "true" ]; then
    printf '%s\n' '{"command":["set_property","pause",false]}' | socat - UNIX-CONNECT:"$SOCK" >/dev/null 2>&1
  else
    printf '%s\n' '{"command":["set_property","pause",true]}' | socat - UNIX-CONNECT:"$SOCK" >/dev/null 2>&1
  fi
}

stop_playback() {
  # Properly stop: pause + seek 0 + clear playlist so playback_state reports "stopped"
  if mpv_running; then
    printf '%s\n' '{"command":["set_property","pause",true]}' | socat - UNIX-CONNECT:"$SOCK" >/dev/null 2>&1
    printf '%s\n' '{"command":["set_property","time-pos",0]}' | socat - UNIX-CONNECT:"$SOCK" >/dev/null 2>&1
    # Stop and clear playlist (mpv becomes idle, filename=null)
    printf '%s\n' '{"command":["stop"]}' | socat - UNIX-CONNECT:"$SOCK" >/dev/null 2>&1
    printf '%s\n' '{"command":["playlist-clear"]}' | socat - UNIX-CONNECT:"$SOCK" >/dev/null 2>&1
  fi
  # Save state as track 0 (means stopped/idle)
  save_state "$(read_state_discid)" "0"
}

next_track() {
  local cur total next
  cur=$(read_state_track)
  total=$(count_tracks)
  # If stopped (cur=0) or no state, go to track 1
  if [ "$cur" -lt 1 ] 2>/dev/null; then
    next=1
  else
    next=$((cur + 1))
    [ "$next" -gt "$total" ] && next=1
  fi
  save_state "$(read_state_discid)" "$next"
  load_track "$next"
}

prev_track() {
  local cur total prev
  cur=$(read_state_track)
  total=$(count_tracks)
  # If stopped (cur=0) or no state, go to track 1
  if [ "$cur" -lt 1 ] 2>/dev/null; then
    prev=1
  else
    prev=$((cur - 1))
    [ "$prev" -lt 1 ] && prev=$total
  fi
  save_state "$(read_state_discid)" "$prev"
  load_track "$prev"
}

eject_cd() {
  stop_mpv
  rm -rf "$RIP_BASE"
  rm -f "$STATE_FILE"
  # Physical eject: use eject -T (toggle). Note: on slim drives without a tray
  # mechanism, this may just unlock the door without opening it — user must pull.
  # We attempt both `eject` and `eject -T` for compatibility. If both fail, no
  # error is fatal: the user can press the physical eject button on the drive.
  eject "$CD_DEVICE" 2>/dev/null || eject -T "$CD_DEVICE" 2>/dev/null || true
}

close_player() {
  stop_mpv
  rm -rf "$RIP_BASE"
  rm -f "$STATE_FILE"
}

# ─── Main dispatch ────────────────────────────────────────────────────────────
case "${1:-}" in
  check)     check_cd ;;
  tracks)    count_tracks ;;
  list)      list_tracks ;;
  discid)    get_discid ;;
  meta)      get_metadata "$(get_discid)" ;;
  tracks-json) tracks_json ;;
  state)     status_json ;;
  launch)    launch_player ;;
  toggle)    toggle_playback ;;
  next)      next_track ;;
  prev)      prev_track ;;
  stop)      stop_playback ;;
  eject)     eject_cd ;;
  close)     close_player ;;
  position)  current_track ;;
  pos-time)  playback_time ;;
  total)     playback_total ;;
  status)    playback_state ;;
  mpv-socket)
    # Used by CdPlayerService to find the socket quickly
    [ -S "$SOCK" ] && echo "$SOCK" || echo ""
    ;;
  cleanup)
    rm -rf "$RIP_BASE"
    rm -f "$STATE_FILE" "$SOCK" "$PID_FILE"
    ;;
  auto)
    TYPE=$(check_cd)
    [ "$TYPE" = "audio-cd" ] && launch_player
    ;;
  *)
    cat <<USAGE
Usage: $0 <command>
Commands:
  check        - show "audio-cd" or "no-cd"
  tracks       - count audio tracks
  list         - list tracks as JSON [{n,sectors,mm,ss}, ...]
  discid       - print MusicBrainz DiscID
  meta         - print JSON metadata {artist,album,year,tracks,source}
  tracks-json  - print {discid,count,meta:{...}}
  state        - print full status JSON ( CdPlayerService uses this )
  launch       - launch mpv + load current track
  toggle       - play/pause toggle (launches mpv if down)
  next         - next track (rip + loadfile)
  prev         - previous track (rip + loadfile)
  stop         - pause mpv and stop playback
  eject        - stop mpv + eject disc + cleanup /tmp
  close        - kill mpv + cleanup (no eject)
  position     - print current track number (1-based)
  pos-time     - print position in seconds
  total        - print current track duration in seconds
  status       - print "playing" | "paused" | "stopped"
  mpv-socket   - print socket path if mpv is running
  cleanup      - remove all temp files
  auto         - launch if CD is audio
USAGE
    exit 1
    ;;
esac
