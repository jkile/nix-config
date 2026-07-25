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
    # NOTE: an earlier revision of this comment claimed Pro Audio was broken
    # (full-scale garbage on empty channels) and that Multichannel "drives the
    # same hardware cleanly". That was wrong, and it matters — see the capture
    # fault documented at the bottom of this file. Both profiles show the
    # SAME intermittent fault at the same rate; measured over 8 trials each,
    # pro-audio failed 5/8 and multichannel 5/8. The original conclusion came
    # from sampling a ~50% coin flip once or twice per profile.
    #
    # Multichannel is still the right pin, just not for noise reasons: it gives
    # a defined 12 in / 12 out layout over PipeWire's ACP path, whereas
    # pro-audio on this unit also intermittently fails to instantiate its
    # capture source ("no target node available").
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

  # ---- KNOWN UNFIXED: intermittent full-scale capture fault ----
  # Roughly half the time an app starts a capture stream from this ULN-8, the
  # stream carries full-scale digital noise instead of the input — continuous
  # static, while the hardware itself is clean. Measured 2026-07-25:
  #
  #   raw ALSA hw:3   ch1 -33.1 dBFS (mic)   ch2 -100.0 dBFS   <- always clean
  #   via PipeWire    ch1 -20.4 / peak -0.1  ch2 -17.2 / 0.0   <- when faulted
  #
  # `arecord -D hw:3` has never once faulted, so the device, the USB link and
  # snd-usb-audio are fine. The fault is above ALSA, in PipeWire.
  #
  # Ruled out by measurement, so please don't re-try these:
  #  - Profile choice. pro-audio 5/8 failures, multichannel 5/8 — identical.
  #  - use-acp=false (4/8), pinned format/rate (3/8), period-size 1024 (4/8),
  #    node.latency 1024 + headroom (3/8), disable-batch (5/8), baseline (5/8).
  #    56 trials over 7 configs, 51.8% overall, nothing distinguishable.
  #  - Channel remixing. Capturing at the source's native 12ch faulted 6/6, so
  #    it is not the 12->2 downmix path.
  #  - USB autosuspend (already off), and the Studio Display (predates it).
  #
  # It re-rolls per STREAM, not per device open: six consecutive probes of one
  # unchanged node instance (object.serial 10078) read CLEAN, faulted, faulted,
  # faulted, CLEAN, faulted. That kills the obvious workaround — a service that
  # validates the device after it appears and reopens it until clean cannot
  # help, because the next app to open a stream gets its own independent roll.
  # A guard along those lines was written, tested, and removed for this reason.
  #
  # Detection, if you want to check the current stream: capture ch2 (an unused
  # input, -100 dBFS when healthy) and look at its peak. Below about -60 dBFS
  # is clean; anything near 0 dBFS is the fault.
  #   parecord --device=alsa_input.usb-Metric_Halo_ULN-8mkIV_49485_12x12-00.multichannel-input \
  #     --format=s24le --rate=48000 --channels=2 --file-format=raw /tmp/c.pcm
  #
  # Worth reporting upstream to PipeWire; this unit has non-standard descriptors
  # ("Quirk or no altset; falling back to MIDI 1.0" on every enumeration) and is
  # a plausible trigger for a race in capture-stream setup.
}
