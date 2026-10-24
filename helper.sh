#!/bin/bash
# PC Remote helper for macOS. Runs in your login session (started by the "PC Remote Helper" app).
# It does what the website in Docker can't: shut down / restart / lock, show messages,
# share the screen, and notice when the Mac is used again after sitting idle.

DIR="${PCREMOTE_DIR:-$HOME/.pc-remote/trigger}"
HELPER_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG="$DIR/watcher.log"
mkdir -p "$DIR"

# only one helper at a time
if [ -f "$DIR/helper.pid" ] && kill -0 "$(cat "$DIR/helper.pid" 2>/dev/null)" 2>/dev/null; then exit 0; fi
echo $$ > "$DIR/helper.pid"

log() { echo "$(date +%H:%M:%S) $*" >> "$LOG"; }
: > "$LOG"
rm -f "$DIR"/{shutdown,view,screen.jpg,screen.tmp,cap.jpg,message.txt,message.tmp,message.clear,message.on,activity.txt,activity.tmp,action.txt,action.tmp}
echo "mac" > "$DIR/platform.txt"
log "helper started (pid $$)"

TS=""
for p in "/Applications/Tailscale.app/Contents/MacOS/Tailscale" "/opt/homebrew/bin/tailscale" "/usr/local/bin/tailscale"; do
  [ -x "$p" ] && TS="$p" && break
done

OVERLAY_PID=""
stop_message() {
  if [ -n "$OVERLAY_PID" ]; then kill "$OVERLAY_PID" 2>/dev/null; wait "$OVERLAY_PID" 2>/dev/null; OVERLAY_PID=""; fi
  rm -f "$DIR/message.on"
}
show_message() {   # plain text on screen, no background; only the phone removes it
  stop_message
  /usr/bin/osascript -l JavaScript "$HELPER_DIR/overlay.js" "$1" >> "$LOG" 2>&1 &
  OVERLAY_PID=$!
  : > "$DIR/message.on"
  log "message shown"
}
cleanup() { stop_message; rm -f "$DIR/helper.pid"; log "helper stopped"; }
trap cleanup EXIT
trap 'exit 0' TERM INT

mtime()     { stat -f %m "$1" 2>/dev/null || echo 0; }
idle_secs() { ioreg -c IOHIDSystem | awk '/HIDIdleTime/ {printf "%d", $NF/1000000000; exit}'; }
profile_cfg() { case "$1" in low) W=640; Q=40; D=0.10;; high) W=1280; Q=60; D=0.02;; *) W=960; Q=50; D=0.05;; esac; }

capture() {   # one screenshot, shrunk; only replaces the shared picture when the screen changed
  /usr/sbin/screencapture -x -m -t jpg "$DIR/cap.jpg" 2>/dev/null || return 1
  /usr/bin/sips -Z "$W" -s format jpeg -s formatOptions "$Q" "$DIR/cap.jpg" --out "$DIR/screen.tmp" >/dev/null 2>&1 || return 1
  if [ -f "$DIR/screen.jpg" ] && cmp -s "$DIR/screen.tmp" "$DIR/screen.jpg"; then rm -f "$DIR/screen.tmp"; else mv -f "$DIR/screen.tmp" "$DIR/screen.jpg"; fi
}

get_volume() { osascript -e 'output volume of (get volume settings)' 2>/dev/null; }
get_mute()   { osascript -e 'output muted of (get volume settings)' 2>/dev/null; }
set_volume() {   # $1 = 0-100 (optional), $2 = true/false (optional)
  local lvl="$1" mt="$2" script=""
  [ -n "$lvl" ] && script+="set volume output volume $lvl "
  if [ "$mt" = "true" ]; then script+="set volume with output muted"; elif [ "$mt" = "false" ]; then script+="set volume without output muted"; fi
  [ -n "$script" ] && osascript -e "$script" >> "$LOG" 2>&1
}
report_audio() {
  local lvl mt; lvl=$(get_volume); mt=$(get_mute)
  [ -n "$lvl" ] && printf '{"level":%s,"mute":%s}' "$lvl" "${mt:-false}" > "$DIR/audio.json"
}

lock_screen() {
  local cg="/System/Library/CoreServices/Menu Extras/User.menu/Contents/Resources/CGSession"
  if [ -x "$cg" ]; then "$cg" -suspend; else /usr/bin/pmset displaysleepnow; fi
}

probe() {   # triggers the macOS permission questions once, during setup
  /usr/sbin/screencapture -x -m -t jpg "$DIR/probe.jpg" 2>>"$LOG"; rm -f "$DIR/probe.jpg"
  /usr/bin/osascript -e 'tell application "System Events" to get name' >>"$LOG" 2>&1
  log "probe done"
}

update_info() {   # Tailscale name/state for the setup page (the website reads these files)
  [ -n "$TS" ] || return
  "$TS" status --json > "$DIR/ts-status.tmp" 2>/dev/null && mv -f "$DIR/ts-status.tmp" "$DIR/ts-status.json"
  "$TS" serve status > "$DIR/ts-serve.tmp" 2>&1; mv -f "$DIR/ts-serve.tmp" "$DIR/ts-serve.txt"
  scutil --get ComputerName > "$DIR/pc.txt" 2>/dev/null
}

idle_limit=300; was_idle=0; max_idle=0
last_alive=0; last_idle=0; last_cfg=0; last_info=0; last_err=""

while true; do
  now=$(date +%s)

  if [ $((now - last_alive)) -ge 2 ]; then date +%s > "$DIR/alive"; last_alive=$now; fi   # "I'm running"

  # --- commands from the phone ---
  if [ -f "$DIR/shutdown" ]; then
    rm -f "$DIR/shutdown"; log "shutdown requested"
    /usr/bin/osascript -e 'tell application "System Events" to shut down' >> "$LOG" 2>&1
  fi
  if [ -f "$DIR/action.txt" ]; then
    act=$(tr -d '[:space:]' < "$DIR/action.txt"); rm -f "$DIR/action.txt"; log "action: $act"
    case "$act" in
      restart) /usr/bin/osascript -e 'tell application "System Events" to restart' >> "$LOG" 2>&1 ;;
      lock)    lock_screen >> "$LOG" 2>&1 ;;
      probe)   probe ;;
    esac
  fi
  if [ -f "$DIR/volume.txt" ]; then
    lvl=$(sed -n 's/.*"level": *\([0-9]\{1,3\}\).*/\1/p' "$DIR/volume.txt")
    mt=$(sed -n 's/.*"mute": *\(true\|false\).*/\1/p' "$DIR/volume.txt")
    rm -f "$DIR/volume.txt"
    set_volume "$lvl" "$mt"; report_audio; log "volume: level=${lvl:-same} mute=${mt:-same}"
  fi
  if [ -f "$DIR/message.clear" ]; then rm -f "$DIR/message.clear"; stop_message; log "message cleared"; fi
  if [ -f "$DIR/message.txt" ]; then
    text=$(cat "$DIR/message.txt"); rm -f "$DIR/message.txt"
    [ -n "$text" ] && show_message "$text"
  fi
  if [ -n "$OVERLAY_PID" ] && ! kill -0 "$OVERLAY_PID" 2>/dev/null; then   # overlay ended on its own
    OVERLAY_PID=""; rm -f "$DIR/message.on"; log "overlay stopped"
  fi

  # --- idle time chosen in the app ---
  if [ $((now - last_cfg)) -ge 10 ]; then
    last_cfg=$now
    v=$(sed -n 's/.*"idle_seconds": *\([0-9][0-9]*\).*/\1/p' "$DIR/config.json" 2>/dev/null)
    if [ -n "$v" ] && [ "$v" -ge 30 ]; then idle_limit=$v; fi
  fi

  # --- idle, then used again ---
  if [ "$now" -ne "$last_idle" ]; then
    last_idle=$now
    idle=$(idle_secs); idle=${idle:-0}
    if [ "$idle" -ge "$idle_limit" ]; then
      was_idle=1; [ "$idle" -gt "$max_idle" ] && max_idle=$idle
    elif [ "$was_idle" = 1 ]; then
      echo "$max_idle" > "$DIR/activity.tmp"; mv -f "$DIR/activity.tmp" "$DIR/activity.txt"
      log "activity after ${max_idle}s idle"; was_idle=0; max_idle=0
    fi
  fi

  # --- live screen: only while the phone is watching ---
  viewing=0
  if [ -f "$DIR/view" ]; then
    d=$((now - $(mtime "$DIR/view"))); [ "$d" -lt 0 ] && d=$((-d))
    [ "$d" -lt 8 ] && viewing=1
  fi
  if [ "$viewing" = 1 ]; then
    profile_cfg "$(cat "$DIR/view" 2>/dev/null)"
    if ! capture; then
      if [ "$last_err" != "capture" ]; then log "capture failed (is Screen Recording allowed for PC Remote Helper?)"; last_err="capture"; fi
      sleep 0.5
    fi
    sleep "$D"
  else
    rm -f "$DIR/screen.jpg"
    if [ $((now - last_info)) -ge 20 ]; then last_info=$now; update_info; fi
    if [ $((now % 2)) -eq 0 ]; then report_audio; fi
    sleep 0.3
  fi
done
