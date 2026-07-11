# Audio — PipeWire stack + Metric Halo ULN-8 mkIV tuning.
#
# SHARED across all hosts on purpose: the ULN-8 physically roams between the
# desktop and laptop. Every rule below is keyed on the interface's stable
# device.name / node.name, so on a machine where it isn't currently plugged in
# these rules simply don't fire and PipeWire falls back to that machine's
# built-in audio. Plug it into any host and the same profile pin, native rate
# list, and latency/suspend tuning apply.
{ ... }:

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
    # We do NOT use "pro-audio" here: on this ULN-8 mkIV, the Pro Audio ACP
    # path is broken — its capture source often fails to instantiate ("no
    # target node available"), and when it does it delivers full-scale garbage
    # on every channel (verified: raw ALSA hw:0 capture is clean/silent on
    # empty channels at -137 dB, while the Pro Audio PipeWire source reads
    # -13 dB full-scale noise on those same empty channels). Almost certainly
    # a PipeWire ACP bug tied to this unit's non-standard USB descriptor (it
    # logs "Quirk or no altset; falling back to MIDI 1.0" at enumeration).
    # The Multichannel profile drives the same hardware cleanly.
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
    #  - node.latency = 128/48000 (~2.7ms/dir, ~5.3ms round-trip): pins the
    #    quantum low for DAW monitoring. Set here (WirePlumber, scoped to the
    #    ULN driver) rather than as a global default.clock.quantum on purpose —
    #    the global knob lives in the pipewire *daemon* config, and restarting
    #    the daemon degrades this unit's ACP profile enumeration (forcing a USB
    #    replug). WirePlumber restarts don't. Verified stable at 128 with zero
    #    xruns; step to 256/48000 if a heavy session ever crackles.
    wireplumber.extraConfig."52-metric-halo-node-tuning" = {
      "monitor.alsa.rules" = [
        {
          matches = [
            { "node.name" = "~alsa_(input|output)\\.usb-Metric_Halo_ULN-8mkIV.*"; }
          ];
          actions.update-props = {
            "session.suspend-timeout-seconds" = 0;
            "node.latency" = "128/48000";
          };
        }
      ];
    };
  };
}
