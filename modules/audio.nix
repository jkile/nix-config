# Audio — PipeWire stack + Metric Halo ULN-8 mkIV tuning.
#
# SHARED across all hosts on purpose: the ULN-8 physically roams between the
# desktop and laptop. Every rule below is keyed on the interface's stable
# device.name / node.name, so on a machine where it isn't currently plugged in
# these rules simply don't fire and PipeWire falls back to that machine's
# built-in audio. Plug it into any host and the same profile pin, native rate
# list, and latency/suspend tuning apply.
{ pkgs, ... }:

{
  # PipeWire, pinned explicitly rather than relying on COSMIC's implicit enable,
  # so the full stack (ALSA/Pulse/JACK) is declared and diagnosable. The Metric
  # Halo ULN-8 enumerates as a USB Audio Class 2 compliant device, so mainline
  # snd-usb-audio drives it; all channels appear once it's on a multichannel
  # profile (see the WirePlumber rules below).
  security.rtkit.enable = true; # lets PipeWire request realtime priority (low latency)
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    jack.enable = true; # exposes a JACK API for pro-audio apps (Ardour, Reaper, etc.)

    # Follow the interface's native rates instead of resampling. The ULN-8
    # advertises all six (44.1k–192k); PipeWire switches to match whatever an
    # app asks for when the graph is idle, so nothing gets resampled.
    extraConfig.pipewire."10-clock-allowed-rates" = {
      "context.properties" = {
        "default.clock.allowed-rates" = [
          44100
          48000
          88200
          96000
          176400
          192000
        ];
      };
    };

    # Pin the ULN-8 to the "Multichannel Duplex" profile, matched by its
    # stable device.name so it re-applies on every replug. This still exposes
    # all 12 in / 12 out channels, but via PipeWire's ACP multichannel path
    # rather than "Pro Audio".
    #
    # NOTE: an earlier revision of this comment blamed the Pro Audio profile
    # for "full-scale garbage on empty channels" and credited Multichannel with
    # driving the hardware cleanly. That garbage was real but the attribution
    # was wrong — it was the 128-frame quantum, fixed below, and it affected
    # both profiles. The profiles were never validly compared against each
    # other, so treat any claimed difference between them as unmeasured.
    #
    # Keep the pin for what it actually buys: a defined 12 in / 12 out layout
    # over the ACP path.
    wireplumber.extraConfig."51-metric-halo-profile" = {
      "monitor.alsa.rules" = [
        {
          matches = [
            { "device.name" = "alsa_card.usb-Metric_Halo_ULN-8mkIV_49485_12x12-00"; }
          ];
          actions.update-props."device.profile" = "output:multichannel-output+input:multichannel-input";
        }
      ];
    };

    # Per-ULN node tuning:
    #  - session.suspend-timeout-seconds = 0: never idle-suspend. USB
    #    suspend/resume toggles the streaming altsetting (which intermittently
    #    times out: usb_set_interface -110) and renumbers the node, silently
    #    dropping the links of apps already using it (e.g. Discord loses its
    #    input). Keeping it always streaming avoids that.
    #  - node.latency = 512/44100 (~11.6ms/dir, ~23ms round-trip): the lowest
    #    value that is CLEAN for playback on this unit. Two separate findings
    #    are folded into that number — read both before lowering it.
    #
    #    (a) DENOMINATOR: it must be 44100, the LOWEST allowed rate, not 48000.
    #    PipeWire's clock.power-of-two-quantum defaults to true, so the
    #    requested latency is converted to frames at the *current* graph rate
    #    and then rounded DOWN to a power of two. The old "256/48000" therefore
    #    only gave 256 frames while the graph happened to run at 48k; the moment
    #    anything played 44.1k content (Firefox, most streaming) the request
    #    scaled to 256*44100/48000 = 235 frames and floored to 128 — silently
    #    reinstating the exact broken quantum this setting exists to avoid.
    #    Expressing the request at the lowest allowed rate makes the floor land
    #    on >=512 frames at every rate in the allowed-rates list above.
    #
    #    (b) NUMERATOR: 512, not 256. 256 is clean for *capture* (measured
    #    below) but not for playback. Measured as xruns/min on a playing client
    #    with pw-top, interleaved because this fault drifts over minutes:
    #
    #      quantum   playback xruns/min
    #      128       ~130                 <- what the 256/48000 bug produced
    #      256       2, 6
    #      512       0, 0
    #      1024      0
    #
    #    Capture, scored separately on ch2 (each second corrupt if its peak
    #    exceeds -60 dBFS; healthy floor is ~-84):
    #
    #      quantum   corrupted seconds
    #      128       19/27, 12/27, 39/59   -> 70/113   worst peak 0.0 dBFS
    #      256        0/27,  0/27,  0/59   ->  0/113   worst peak -83.9 dBFS
    #      512        0/27,  0/27          ->  0/54
    #      1024       0/27,  0/27          ->  0/54
    #
    #    Quantum is graph-wide, so capture and playback cannot be tuned apart
    #    while both live on this one driver — 512 is the max of the two needs.
    #    If a tracking session ever needs tighter monitoring, "256/44100" is the
    #    documented fallback: it costs a few xruns/min but stays off 128.
    #
    #    Set here (WirePlumber, scoped to the ULN driver) rather than as a
    #    global default.clock.quantum on purpose — the global knob lives in the
    #    pipewire *daemon* config, and restarting the daemon degrades this
    #    unit's ACP profile enumeration (forcing a USB replug). WirePlumber
    #    restarts don't.
    wireplumber.extraConfig."52-metric-halo-node-tuning" = {
      "monitor.alsa.rules" = [
        {
          matches = [
            { "node.name" = "~alsa_(input|output)\\.usb-Metric_Halo_ULN-8mkIV.*"; }
          ];
          actions.update-props = {
            "session.suspend-timeout-seconds" = 0;
            "node.latency" = "512/44100";
          };
        }
      ];
    };
  };

  # ---- FIXED: Wine/Proton games crashing on startup (game_stereo) ----
  # Symptom: every Wine/Proton game died ~12s after launch with no window. Looks
  # exactly like a GPU fault and is not one.
  #
  # Cause: the ULN-8's multichannel sink is 12ch with an all-aux channel map
  # (aux0..aux11) — no named speaker positions. Wine's PulseAudio driver maps
  # channels onto *Windows speaker positions*, so an aux-only map yields a mask
  # of zero and format negotiation fails outright:
  #
  #   fixme:pulse:get_channel_mask Unknown speaker configuration: 12
  #   err:pulse:pulse_spec_from_waveformat Invalid channel mask: 0/12 and 0(0)
  #   err:pulse:pulse_spec_from_waveformat Invalid format! Channel spec valid: 0, format: 5
  #
  # winepulse then returns null, FAudio does not null-check it, and the audio
  # thread dereferences it ~2s later. Diagnosed 2026-07-27 on Elden Ring (Steam
  # appid 1245620): 0xc0000005 at xaudio2_8+0xd15a, instruction `movq (%rcx),%rax`
  # with rcx=0, on the FAudio_AudioClientThread. Native apps are unaffected —
  # PipeWire happily remixes stereo onto aux channels by index; only Wine's
  # strict position mapping trips on it.
  #
  # Fix: a 2ch FL/FR loopback sink feeding ULN outputs 1/2 unremixed, made the
  # default so Wine's default-endpoint lookup finds a sane layout. The raw 12ch
  # sink is untouched and still there for DAW/JACK work.
  #
  # Run as a standalone pw-loopback user service rather than a `context.modules`
  # entry in the daemon config ON PURPOSE: daemon config only takes effect on a
  # PipeWire daemon restart, which degrades this unit's ACP profile enumeration
  # and forces a USB replug (see the node.latency notes above). A user service
  # starts, stops, and rebuilds without touching the daemon.
  #
  # ROAMING: gated on the ULN's stable by-id control node so it no-ops on hosts
  # where the interface isn't plugged in — without the gate, target.object would
  # not resolve and the loopback would link to the default sink, which is itself
  # (feedback loop). If you hotplug the ULN *after* login, this service will not
  # pick it up on its own; start it by hand or wire up a udev SYSTEMD_USER_WANTS
  # rule.
  #
  # NOT MEASURED: the latency cost of the extra graph hop, and whether routing
  # all desktop audio through it moves the xrun figures documented above. If
  # playback regresses, re-measure with pw-top before blaming anything else.
  systemd.user.services.game-stereo-loopback = {
    description = "Stereo (FL/FR) loopback sink feeding ULN-8 outputs 1/2";
    after = [ "pipewire.service" ];
    bindsTo = [ "pipewire.service" ];
    wantedBy = [ "pipewire.service" ];
    serviceConfig = {
      ExecCondition = pkgs.writeShellScript "game-stereo-loopback-gate" ''
        test -e /dev/snd/by-id/usb-Metric_Halo_ULN-8mkIV_49485_12x12-00
      '';
      ExecStart = pkgs.writeShellScript "game-stereo-loopback" ''
        exec ${pkgs.pipewire}/bin/pw-loopback \
          --capture-props='media.class=Audio/Sink node.name=game_stereo node.description="Stereo (ULN-8 1/2)" audio.position=[FL,FR] priority.session=2000' \
          --playback-props='node.name=game_stereo.output node.passive=true stream.dont-remix=true audio.position=[AUX0,AUX1] target.object=alsa_output.usb-Metric_Halo_ULN-8mkIV_49485_12x12-00.multichannel-output'
      '';
      Restart = "on-failure";
      RestartSec = 2;
    };
  };

  # ---- FIXED: intermittent capture corruption (node.latency) ----
  # Symptom: apps got bursts of full-scale digital noise plus dropouts from the
  # ULN-8 capture — continuous static under the signal. Cause was the 128-frame
  # quantum above; 256 is clean for capture (playback needs 512 — see the
  # node.latency notes). Kept here because the diagnosis was slow and the traps
  # are worth knowing.
  #
  # The corruption was structured, not random: zero-crossing rate 0.10-0.27
  # (random memory would be ~0.5), with a repeating two-phase frame pattern in
  # which quiet samples appeared at huge magnitudes. Consistent with a framing
  # or stride error on this device's 36-byte frames (S24_3LE x 12ch, single
  # altsetting, ASYNC endpoint) when the quantum is too small to keep up.
  #
  # MEASUREMENT TRAPS — these produced a string of confident wrong answers:
  #  - Short probes are worthless. Every stream has a large burst in roughly
  #    its first second, so a 2-3s capture mostly measures that. 3s probes gave
  #    a convincing ~50% "fault rate" that looked like a per-stream coin flip
  #    and led to an entire detect-and-reopen guard service being built for a
  #    problem that did not exist in that shape. Capture >=30s and score each
  #    second separately.
  #  - The fault drifts over minutes. Blocked A/B testing gives false results:
  #    one 20s run scored 1024 at 0/19 and a later run of the same config at
  #    14/18. Interleave configurations (A, B, A, B) and replicate.
  #  - Those two traps also generated a false "plain ALSA corrupts too, so it
  #    is not PipeWire" conclusion. With 30s captures, ALSA is spotless:
  #      hw native S24_3LE   0/29     plughw S32_LE  0/29
  #      pipewire-pulse     12/27 and 24/27
  #    It was PipeWire-side all along.
  #
  # Also checked and NOT the cause: ACP on/off, mmap on/off, period-size,
  # headroom, pinned format, disable-batch, profile choice (pro-audio vs
  # multichannel), channel remixing, USB autosuspend, and RT starvation
  # (pipewire's data-loop.0 correctly runs SCHED_RR prio 20 via rtkit — check
  # the thread list, not the main pid, which is correctly SCHED_OTHER).
  # A Metric Halo firmware update did not change the behaviour either.
  #
  # To re-measure: ch2 is an unused input, ~-84 dBFS when healthy. Score a
  # second as corrupt if its ch2 peak exceeds -60 dBFS.
  #   parecord --device=alsa_input.usb-Metric_Halo_ULN-8mkIV_49485_12x12-00.multichannel-input \
  #     --format=s24le --rate=48000 --channels=2 --file-format=raw /tmp/c.pcm
}
