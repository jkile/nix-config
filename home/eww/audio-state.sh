# Emits the full audio state as a single-line JSON object, once immediately
# and again on every relevant PipeWire/PulseAudio event. Consumed by eww's
# `deflisten audio` in eww.yuck. Depends on pactl (pulseaudio client) + jq,
# both injected on PATH by the writeShellApplication wrapper in home.nix.
#
# NOTE: errexit is deliberately OFF (see bashOptions in home.nix) so a single
# transient pactl failure can't kill the long-running listener.

emit() {
  sinks=$(pactl -f json list sinks | jq -c '
    [ .[] | {
        name,
        desc: (.description // .name),
        vol: (.volume | to_entries[0].value.value_percent | rtrimstr("%") | tonumber),
        mute
      } ]')
  # Drop monitor sources (loopbacks of sinks) — not real inputs.
  sources=$(pactl -f json list sources | jq -c '
    [ .[] | select((.name | test("\\.monitor$")) | not) | {
        name,
        desc: (.description // .name),
        vol: (.volume | to_entries[0].value.value_percent | rtrimstr("%") | tonumber),
        mute
      } ]')
  apps=$(pactl -f json list sink-inputs | jq -c '
    [ .[] | {
        index: (.index | tostring),
        name: (.properties["application.name"] // .properties["media.name"] // "App"),
        media: (.properties["media.name"] // ""),
        vol: (.volume | to_entries[0].value.value_percent | rtrimstr("%") | tonumber),
        mute
      } ]')

  defsink=$(pactl get-default-sink)
  defsource=$(pactl get-default-source)

  # Pull the default device's volume/mute up to the top level so the master
  # sliders bind to a plain number rather than searching the array in yuck.
  sinkvol=$(echo "$sinks" | jq -r --arg d "$defsink" 'map(select(.name==$d))[0].vol // 0')
  sourcevol=$(echo "$sources" | jq -r --arg d "$defsource" 'map(select(.name==$d))[0].vol // 0')
  sinkmute=$(echo "$sinks" | jq -r --arg d "$defsink" 'map(select(.name==$d))[0].mute // false')
  sourcemute=$(echo "$sources" | jq -r --arg d "$defsource" 'map(select(.name==$d))[0].mute // false')

  jq -cn \
    --argjson sinks "$sinks" \
    --argjson sources "$sources" \
    --argjson apps "$apps" \
    --arg defsink "$defsink" \
    --arg defsource "$defsource" \
    --argjson sinkvol "$sinkvol" \
    --argjson sourcevol "$sourcevol" \
    --argjson sinkmute "$sinkmute" \
    --argjson sourcemute "$sourcemute" \
    '{
       sinks: $sinks, sources: $sources, apps: $apps,
       defsink: $defsink, defsource: $defsource,
       sinkvol: $sinkvol, sourcevol: $sourcevol,
       sinkmute: $sinkmute, sourcemute: $sourcemute
     }'
}

emit
# Re-emit on device/stream/server changes. "on sink" also matches
# "on sink-input", so app-volume changes are covered too.
#
# Debounce: after a relevant event, drain everything that arrives within a
# ~150ms quiet window before re-emitting. Without this, our own volume writes
# (and a fast drag, which fires an event per pixel) stream state back into eww
# mid-drag — it rewrites the scale's :value and the knob snaps back, which is
# what makes the sliders sticky and pins the top of the range at 99%.
pactl subscribe 2>/dev/null | while read -r line; do
  case "$line" in
    *"on sink"* | *"on source"* | *"on server"* | *"on card"*) ;;
    *) continue ;;
  esac
  while read -r -t 0.15 _; do :; done
  emit
done
