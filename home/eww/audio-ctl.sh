# Action dispatcher for the eww audio panel. pactl is injected on PATH by the
# writeShellApplication wrapper in home.nix. Values from eww scale widgets
# arrive as the trailing argument (eww's "{}" placeholder).
#
# Usage:
#   eww-audio-ctl sink-vol   <0-100>
#   eww-audio-ctl source-vol <0-100>
#   eww-audio-ctl app-vol    <index> <0-100>
#   eww-audio-ctl set-sink   <sink-name>
#   eww-audio-ctl set-source <source-name>
#   eww-audio-ctl toggle-sink-mute
#   eww-audio-ctl toggle-source-mute

cmd=$1
# eww scale onchange hands us a float ("72.0"); pactl wants an integer percent.
# The scales use :max 101 (a GtkRange only reaches upper-page_size, so :max 100
# would cap at 99) — clamp back to 0..100 so we never overshoot.
int() {
  v=$(printf '%.0f' "$1")
  [ "$v" -gt 100 ] && v=100
  [ "$v" -lt 0 ] && v=0
  printf '%s' "$v"
}

case "$cmd" in
  sink-vol)           pactl set-sink-volume @DEFAULT_SINK@ "$(int "$2")%" ;;
  source-vol)         pactl set-source-volume @DEFAULT_SOURCE@ "$(int "$2")%" ;;
  app-vol)            pactl set-sink-input-volume "$2" "$(int "$3")%" ;;
  set-sink)           pactl set-default-sink "$2" ;;
  set-source)         pactl set-default-source "$2" ;;
  toggle-sink-mute)   pactl set-sink-mute @DEFAULT_SINK@ toggle ;;
  toggle-source-mute) pactl set-source-mute @DEFAULT_SOURCE@ toggle ;;
  *)
    echo "eww-audio-ctl: unknown command '$cmd'" >&2
    exit 1
    ;;
esac
