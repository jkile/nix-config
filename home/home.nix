{
  config,
  osConfig,
  pkgs,
  pkgsUnstable,
  inputs,
  lib,
  ...
}:

let
  # Nord palette + the semantic UI tokens derived from it. Kept in its own file
  # so the per-app modules imported below (firefox.nix) read the same values
  # rather than carrying a second copy — see home/palette.nix for the reasoning
  # behind the extended elevation and text ramps.
  inherit (import ./palette.nix) nord ui;

  # Laptop-only bits: niri's host.kdl overrides and the waybar battery module.
  isLaptop = osConfig.networking.hostName == "jakek-laptop";

  # Discord (Electron) hangs on the loading screen under niri because of the
  # wp-fractional-scale protocol — the renderer pegs a core forever. Disabling
  # WaylandFractionalScaleV1 fixes it, and since our output is integer-scaled
  # we lose nothing. NIXOS_OZONE_WL (global) keeps it on Wayland.
  #
  # VK_DRIVER_FILES is what makes screen sharing work. Discord's "linux-vulkan"
  # capture path imports the portal's DMA-BUFs through Vulkan, but Discord ships
  # its own unpatched libvulkan.so.1 (first on LD_LIBRARY_PATH) that has no idea
  # NixOS keeps ICD manifests under /run/opengl-driver. So vkCreateInstance finds
  # no drivers, the capturer ends up advertising zero formats, and the PipeWire
  # link dies with "no more input formats" — the portal picker appears, then the
  # stream immediately errors out. Pointing the bundled loader at the RADV
  # manifest fixes it. Set explicitly rather than at the icd.d directory so the
  # prober can't pick lavapipe over the real GPU.
  #
  # Don't re-add --enable-features=WebRTCPipeWireCapturer here: that feature no
  # longer exists in Electron 37, and because Chromium keeps one value per switch
  # a second --enable-features silently overwrote the WaylandWindowDecorations
  # the nixpkgs wrapper passes.
  discord-wayland = pkgs.symlinkJoin {
    name = "discord-wayland";
    paths = [ pkgs.discord ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      for b in Discord discord; do
        rm -f "$out/bin/$b"
        makeWrapper ${pkgs.discord}/bin/Discord "$out/bin/$b" \
          --set-default VK_DRIVER_FILES \
            "${pkgs.addDriverRunpath.driverLink}/share/vulkan/icd.d/radeon_icd.x86_64.json" \
          --add-flags "--disable-features=WaylandFractionalScaleV1"
      done
    '';
  };

  # Studio tracks nixpkgs-unstable: stable 26.05 lags a major release behind.
  # Android Studio 2025.3+ defaults to X11. Under niri its first-run
  # Compose wizard hangs after the splash screen without ever mapping a window
  # through Xwayland. JetBrains Runtime's native Wayland toolkit avoids that
  # path; wrap the package rather than setting a Java-wide environment variable
  # so Gradle and unrelated JVM applications keep their normal toolkit choice.
  android-studio-wayland = pkgs.symlinkJoin {
    name = "android-studio-wayland";
    paths = [ pkgsUnstable.android-studio ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      rm -f "$out/bin/android-studio"
      makeWrapper ${pkgsUnstable.android-studio}/bin/android-studio "$out/bin/android-studio" \
        --add-flags "-Dawt.toolkit.name=WLToolkit"
    '';
  };

  # Backing scripts for the eww audio panel (see home/eww/). Shipped as bins so
  # eww's yuck can call them by bare name, with their deps pinned on PATH via
  # runtimeInputs. writeShellApplication also shellchecks them at build time.
  # errexit is off for the state script so a transient pactl hiccup can't kill
  # the long-lived `deflisten` listener.
  ewwAudioState = pkgs.writeShellApplication {
    name = "eww-audio-state";
    runtimeInputs = [
      pkgs.pulseaudio
      pkgs.jq
    ];
    bashOptions = [ "pipefail" ];
    text = builtins.readFile ./eww/audio-state.sh;
  };
  ewwAudioCtl = pkgs.writeShellApplication {
    name = "eww-audio-ctl";
    runtimeInputs = [ pkgs.pulseaudio ];
    text = builtins.readFile ./eww/audio-ctl.sh;
  };

  # Now-playing for the waybar custom/media module (replaces the crash-prone
  # native mpris module). Emits waybar JSON; jq handles escaping of arbitrary
  # track titles. Short enough to inline rather than carry a separate file.
  waybarMedia = pkgs.writeShellApplication {
    name = "waybar-media";
    runtimeInputs = [
      pkgs.playerctl
      pkgs.jq
    ];
    text = ''
      status=$(playerctl status 2>/dev/null || true)
      case "$status" in
        Playing) icon="" ;;
        Paused)  icon="" ;;
        *) printf '%s\n' '{"text":""}'; exit 0 ;;
      esac
      title=$(playerctl metadata title 2>/dev/null || true)
      artist=$(playerctl metadata artist 2>/dev/null || true)
      jq -cn --arg icon "$icon" --arg title "$title" --arg artist "$artist" --arg status "$status" '
        {
          text:    ($icon + " " + $title + (if $artist != "" then " — " + $artist else "" end)),
          tooltip: ($title + (if $artist != "" then "\n" + $artist else "" end) + "\n" + $status),
          class:   ($status | ascii_downcase)
        }'
    '';
  };

  # ---- Wallpaper (awww) ----
  # awww is the maintained fork of swww in nixpkgs 26.05 (`pkgs.swww` is now an
  # alias for it); the CLI is unchanged but the binaries are awww/awww-daemon.
  # A reproducible Nord gradient generated at build time with ImageMagick, so
  # there's no binary blob committed to the repo. awww scales/crops it per
  # output (the ultrawide LG and the Studio Display have different aspect
  # ratios). To use your own image instead, point set-wallpaper's `awww img`
  # at a different path. runCommand's name ends in .png, so $out does too and
  # ImageMagick infers the PNG encoder from it.
  # The old gradient ran nord0 -> nord2, which put the desktop at the same hue
  # *and* nearly the same lightness as the panels floating on it — no figure/
  # ground separation, so the bar had no edge to hold. This sits a full ramp step
  # below surface1 so every panel reads as sitting above it.
  #
  # Three passes:
  #   1. the diagonal base gradient, surface0 -> bg
  #   2. a gentle radial multiply, so a 4K expanse doesn't read as flat fill
  #   3. a dither of Gaussian noise
  #
  # (3) is not decoration. Dark gradients band badly at 8 bits — these values
  # span about 7 levels per channel over 2160px, so without a dither you get
  # visible concentric steps. Attenuation is deliberately low: 0.2 breaks the
  # banding up and is invisible at 1:1, while 0.4 reads as film grain.
  nordWallpaper =
    pkgs.runCommand "nord-wallpaper.png" { nativeBuildInputs = [ pkgs.imagemagick ]; }
      ''
        magick -size 3840x2160 -define gradient:angle=135 \
          gradient:'#${ui.surface0}'-'#${ui.bg}' \
          \( -size 3840x2160 radial-gradient:'#FFFFFF'-'#C8C8C8' \) \
          -compose Multiply -composite \
          -attenuate 0.2 +noise Gaussian \
          -depth 8 "$out"
      '';

  # Paints the wallpaper once awww-daemon is up. niri spawns the daemon and this
  # script separately (see config.kdl); the loop polls the daemon's socket so a
  # cold start can't race the `img` call, capped at ~5s so it never spins.
  setWallpaper = pkgs.writeShellApplication {
    name = "set-wallpaper";
    runtimeInputs = [ pkgs.awww ];
    text = ''
      for _ in $(seq 1 50); do
        awww query >/dev/null 2>&1 && break
        sleep 0.1
      done
      awww img "${nordWallpaper}" --transition-type fade --transition-duration 2
    '';
  };

  # Clipboard history picker (Mod+Shift+C). The wl-paste --watch listeners
  # (started by niri) feed cliphist's store; this lists it through fuzzel's
  # dmenu mode and copies the chosen entry back to the clipboard. Uses the same
  # Nord fuzzel config as the launcher.
  clipboardHistory = pkgs.writeShellApplication {
    name = "clipboard-history";
    runtimeInputs = [
      pkgs.cliphist
      pkgs.fuzzel
      pkgs.wl-clipboard
    ];
    text = ''
      cliphist list \
        | fuzzel --dmenu --prompt "󰅍  " --width 60 --lines 12 \
        | cliphist decode \
        | wl-copy
    '';
  };

  # Power menu (Mod+Shift+E). A fuzzel dmenu of session actions. Log out uses
  # niri's own quit; Ctrl+Alt+Delete stays wired to the raw quit-with-
  # confirmation in config.kdl as an escape hatch. Lock goes through
  # `loginctl lock-session` so swayidle's handler is the one place that runs
  # swaylock. `|| chosen=""` swallows the non-zero exit when the menu is
  # dismissed so nothing fires.
  powerMenu = pkgs.writeShellApplication {
    name = "power-menu";
    runtimeInputs = [
      pkgs.fuzzel
      pkgs.systemd
    ];
    text = ''
      chosen=$(printf '%s\n' "󰌾  Lock" "󰗽  Log out" "󰤄  Suspend" "󰜉  Reboot" "󰐥  Shut down" \
        | fuzzel --dmenu --prompt "⏻  " --width 20 --lines 5) || chosen=""
      case "$chosen" in
        *"Lock")      loginctl lock-session ;;
        *"Log out")   niri msg action quit --skip-confirmation ;;
        *"Suspend")   systemctl suspend ;;
        *"Reboot")    systemctl reboot ;;
        *"Shut down") systemctl poweroff ;;
      esac
    '';
  };

  # ---- Blue-light filter (wlsunset) manager ----
  # Single source of truth for the night-light settings: niri starts it
  # (`nightlight start`) and the waybar custom/nightlight widget toggles/queries
  # it (`nightlight toggle` / `status`), both through this one script. Edit the
  # four settings below to retune; `wlsunset -h` lists the rest. setsid detaches
  # the daemon so it survives this short-lived invocation; toggle pokes waybar
  # (SIGRTMIN+8 = the module's signal=8) so the icon flips the instant you click.
  # NB: wlsunset has no query API, so status can only report running/stopped —
  # the temps shown in the tooltip are the configured values, not a live read.
  nightlight = pkgs.writeShellApplication {
    name = "nightlight";
    runtimeInputs = [
      pkgs.wlsunset
      pkgs.jq
      pkgs.procps # pgrep/pkill
      pkgs.util-linux # setsid
    ];
    text = ''
      LAT=34.05
      LONG=-118.24
      NIGHT=4000 # night (low) temp in K — lower is warmer/more orange
      DAY=6500 # day (high) temp in K — 6500 is neutral daylight

      start_daemon() {
        setsid wlsunset -l "$LAT" -L "$LONG" -t "$NIGHT" -T "$DAY" >/dev/null 2>&1 &
      }

      case "''${1:-status}" in
        start)
          pgrep -x wlsunset >/dev/null 2>&1 || start_daemon
          ;;
        stop)
          pkill -x wlsunset || true
          ;;
        toggle)
          if pgrep -x wlsunset >/dev/null 2>&1; then
            pkill -x wlsunset || true
          else
            start_daemon
          fi
          pkill -RTMIN+8 waybar || true
          ;;
        status)
          if pgrep -x wlsunset >/dev/null 2>&1; then
            jq -cn --arg tip "Blue-light filter: on"$'\n'"Night ''${NIGHT}K · Day ''${DAY}K"$'\n'"Click to disable" \
              '{text:"󰖔", class:"on", tooltip:$tip}'
          else
            jq -cn --arg tip "Blue-light filter: off"$'\n'"Click to enable (night ''${NIGHT}K · day ''${DAY}K)" \
              '{text:"󰖙", class:"off", tooltip:$tip}'
          fi
          ;;
      esac
    '';
  };

  # Web shortcuts launcher (Mod+G / the waybar 󰖟 button). A fuzzel dmenu of
  # bookmarks that each open in a chosen Firefox profile — the OS-level stand-in
  # for Arc/Zen's command bar + spaces. Edit the `entries` list to taste; the
  # profile field must match a programs.firefox.profiles.<name> below. Firefox
  # is intentionally NOT pinned in runtimeInputs so this calls the session's
  # policy-wrapped firefox (from programs.firefox), not a bare unwrapped copy.
  webShortcuts = pkgs.writeShellApplication {
    name = "web-shortcuts";
    runtimeInputs = [ pkgs.fuzzel ];
    text = ''
      # "Label|URL|profile" — profile is personal or work (see home.nix).
      entries=(
        "󰊤  GitHub|https://github.com|work"
        "󰖟  Overview|https://overview.app|work"
        "󰖟  PostHog|https://us.posthog.com|work"
        "󰇮  Proton Mail|https://mail.proton.me|personal"
        "󰃭  Proton Calendar|https://calendar.proton.me|personal"
        "󰗃  YouTube|https://youtube.com|personal"
      )

      labels=()
      for e in "''${entries[@]}"; do labels+=("''${e%%|*}"); done

      chosen=$(printf '%s\n' "''${labels[@]}" \
        | fuzzel --dmenu --prompt "󰖟  " --width 40 --lines 8) || exit 0
      [ -n "$chosen" ] || exit 0

      for e in "''${entries[@]}"; do
        if [ "''${e%%|*}" = "$chosen" ]; then
          rest=''${e#*|}
          firefox -P "''${rest##*|}" "''${rest%%|*}" &
          exit 0
        fi
      done
    '';
  };

  # Quick web search (Mod+S). A prompt-only fuzzel box (--lines 0, empty stdin):
  # type a query and it opens DuckDuckGo results in Firefox; paste a full URL and
  # it opens that directly. jq @uri URL-encodes the query so spaces/&/# are safe.
  webSearch = pkgs.writeShellApplication {
    name = "web-search";
    runtimeInputs = [
      pkgs.fuzzel
      pkgs.jq
    ];
    text = ''
      query=$(fuzzel --dmenu --prompt "󰍉  " --width 40 --lines 0 </dev/null) || exit 0
      [ -n "$query" ] || exit 0
      case "$query" in
        http://* | https://*)
          url="$query"
          ;;
        *)
          q=$(printf '%s' "$query" | jq -sRr @uri)
          url="https://duckduckgo.com/?q=$q"
          ;;
      esac
      firefox "$url" &
    '';
  };
in
{
  imports = [
    inputs.zen-browser.homeModules.beta
    ./claude-code.nix # Claude Code CLI + declarative skills (settings.json left mutable)
    ./codex.nix # Codex CLI, same split: shared ./agent-skills, config.toml left mutable
    ./firefox.nix # Firefox + the Nord userChrome/userContent that matches this session
  ];

  home.username = "jakek";
  home.homeDirectory = "/home/jakek";
  home.stateVersion = "26.05";

  home.packages = with pkgs; [
    discord-wayland # Discord w/ fractional-scale + PipeWire flags (see let binding)
    ripgrep
    fd
    procs
    # btop with its AMD GPU panel working. btop talks to Radeon cards only
    # through ROCm's librocm_smi64, which it dlopens at runtime; without it the
    # GPU meters silently stay empty, which is why a stock btop shows nothing on
    # the R9700. rocmSupport doesn't build a ROCm *compute* stack — it only adds
    # rocm-smi (a sysfs/ioctl management library) to btop's rpath, so inference
    # keeps using the Vulkan path untouched. Costs ~169 MiB of closure.
    #
    # Deliberately an override on this one package rather than
    # `nixpkgs.config.rocmSupport = true`: that flag is read by many packages,
    # llama-cpp among them, so setting it globally would trigger a from-source
    # ROCm build of llama.cpp — exactly what hosts/desktop/llama-cpp.nix avoids.
    (btop.override { rocmSupport = true; })
    nerd-fonts.jetbrains-mono
    nerd-fonts.symbols-only
    # Nord GTK theme + Nordzy icons/cursor are installed via the `gtk` module
    # below (theme/iconTheme/cursorTheme .package), so they're not listed here.
    # claude-code is installed by ./claude-code.nix (programs.claude-code).
    qpwgraph # PipeWire patchbay — route the ULN-8's 12 discrete channels
    pwvucontrol # full GTK4 mixer — middle-click volume module for per-channel detail
    swayosd # on-screen volume/mute popup (server spawned by niri; see config.kdl)

    # eww audio panel (Mod+A / click the volume module). eww itself comes from
    # programs.eww below; these are the pactl-driven helper scripts it calls.
    ewwAudioState
    ewwAudioCtl
    waybarMedia # now-playing script for the waybar custom/media module

    # niri-session workflow tools — wallpaper, clipboard, screenshots, night
    # light. Their binds/spawns live in home/niri/config.kdl.
    awww # animated wallpaper daemon (swww fork; spawn-at-startup: awww-daemon)
    setWallpaper # paints the Nord gradient once awww-daemon's socket is up
    wl-clipboard # wl-copy/wl-paste — clipboard plumbing (also feeds cliphist)
    cliphist # clipboard history store (fed by the wl-paste --watch listeners)
    clipboardHistory # Mod+Shift+C — fuzzel clipboard-history picker
    powerMenu # Mod+Shift+E — fuzzel session menu (logout/suspend/reboot/off)
    wlsunset # blue-light filter engine (driven by the nightlight script below)
    nightlight # wlsunset manager + backs the waybar custom/nightlight widget
    swayidle # locks before sleep / on lock-session (spawned by niri); swaylock is programs.swaylock
    grim # screenshot capture backend for the swappy region grab
    slurp # Nord-tinted region selector for the swappy grab
    swappy # screenshot annotation (Mod+Shift+S)
    webShortcuts # Mod+G / waybar 󰖟 — fuzzel web bookmarks → Firefox profiles
    webSearch # Mod+S — fuzzel prompt → DuckDuckGo search in Firefox

    sops
    age
    ssh-to-age

    proton-vpn # ProtonVPN app; provides `protonvpn-app` (waybar VPN module click)

    obsidian # markdown notes (Electron; Wayland via the global NIXOS_OZONE_WL)

    k9s # Kubernetes terminal UI tool

    # Android development. The nixpkgs wrapper gives Studio and its downloaded
    # SDK/emulator binaries the FHS runtime they expect on NixOS; android-tools
    # keeps adb/fastboot available from any shell, independent of the IDE.
    android-studio-wayland
    android-tools
  ];

  # Android Studio's default writable SDK location. Export it so Gradle and
  # command-line tools can find the SDK installed by the setup wizard without
  # tying this config to one SDK/platform version. Do not prepend its binary
  # directories here: the Nix-native android-tools should remain the shell's
  # adb/fastboot, while Studio runs downloaded SDK binaries in its FHS wrapper.
  home.sessionVariables.ANDROID_HOME = "${config.home.homeDirectory}/Android/Sdk";

  xdg.configFile."niri/config.kdl".source = ./niri/config.kdl;
  # Pulled in by the `include` at the end of config.kdl. It's generated on every
  # host because niri won't start if an included file is missing; the desktop's
  # copy is empty.
  xdg.configFile."niri/host.kdl".text =
    if isLaptop then
      ''
        // Framework 13 internal panel (2880x1920 -> 1920x1280 logical). 1.5 divides
        // the panel evenly, so niri can render it without rounding.
        output "eDP-1" {
            scale 1.5
        }

        // An included touchpad/mouse block replaces config.kdl's whole block
        // rather than merging into it, so repeat the shared settings here.
        input {
            touchpad {
                // No `tap`: only a physical press clicks on the laptop.
                natural-scroll
                accel-speed 0.65
                // Two-finger press = right click, three = middle (instead of
                // libinput's default bottom-corner button areas).
                click-method "clickfinger"
            }
            mouse {
                natural-scroll
                accel-speed 0.65
            }
        }
      ''
    else
      "// No overrides for this host.\n";

  # SwayOSD volume/mute popup — Nord styling to match waybar/mako/fuzzel:
  # the same floating, rounded, translucent dark surface with a frost-blue
  # progress fill. swayosd-server is pointed at this file via --style in the
  # niri spawn-at-startup line.
  xdg.configFile."swayosd/style.css".text = ''
    window {
      background-color: rgba(35, 43, 54, 0.94);   /* surface1 */
      border: 1px solid rgba(63, 74, 92, 0.7);    /* lineStrong */
      border-radius: 12px;
      padding: 12px 16px;
    }

    #container { margin: 12px; }

    image, label {
      color: #${ui.text};
    }

    /* Thinner track than before: at 8px the bar read as a chunky widget, at 5px
       it reads as a measurement. The fill is the accent because this popup
       exists precisely to show one changing value. */
    progressbar {
      min-height: 5px;
      border-radius: 3px;
      background: transparent;
    }
    trough {
      min-height: 5px;
      border-radius: 3px;
      background-color: #${ui.surface3};
    }
    progress {
      min-height: 5px;
      border-radius: 3px;
      background-color: #${ui.accent};
    }

    /* Muted — drop the fill out of the accent entirely so "muted" is legible at
       a glance rather than being a slightly different blue. */
    progressbar:disabled progress { background-color: #${ui.textFaint}; }
    image:disabled, label:disabled { color: #${ui.textFaint}; }
  '';

  # swappy — screenshot annotation (Mod+Shift+S grabs a region into it). Saves
  # to the same folder niri's own screenshots use, so everything lands together.
  xdg.configFile."swappy/config".text = ''
    [Default]
    save_dir=/home/jakek/Pictures/Screenshots
    save_filename_format=Screenshot swappy %Y-%m-%d %H-%M-%S.png
    show_panel=false
    early_exit=false
    fill_shape=false
  '';

  # Make sure the screenshot folder exists so both niri and swappy can write it.
  home.file."Pictures/Screenshots/.keep".text = "";

  # eww — the audio control panel HUD (Mod+A, or click the waybar volume
  # module). Config lives as readable files in home/eww/; the module writes
  # them to ~/.config/eww/. The daemon is started by niri spawn-at-startup so
  # the deflisten state is warm before the panel is first opened.
  programs.eww = {
    enable = true;
    yuckConfig = builtins.readFile ./eww/eww.yuck;
    scssConfig = builtins.readFile ./eww/eww.scss;
  };

  programs.home-manager.enable = true;

  # waybar — styled to echo COSMIC's panel: a floating, rounded, translucent
  # dark bar (Nord). Installed here but only started by niri's spawn-at-startup
  # (systemd.enable is off by default), so it stays niri-session only.
  programs.waybar = {
    enable = true;
    settings.mainBar = {
      layer = "top";
      position = "top";
      height = 34;
      spacing = 6;
      # Float the bar off the screen edges (the COSMIC look).
      margin-top = 6;
      margin-left = 10;
      margin-right = 10;

      modules-left = [
        "custom/webshortcuts"
        "niri/workspaces"
        "niri/window"
      ];
      modules-center = [ "clock" ];
      modules-right = [
        "custom/media"
        "custom/weather"
        "cpu"
        "memory"
        "custom/temp"
        "custom/nightlight"
        "pulseaudio"
        "network"
        "custom/protonvpn"
      ]
      ++ lib.optional isLaptop "battery"
      ++ [ "tray" ];

      "niri/workspaces".format = "{icon}";

      # Focused-window title. Truncated so a long title can't shove the
      # centered clock off-center; empty when nothing is focused.
      "niri/window" = {
        format = "{title}";
        max-length = 55;
        tooltip = false;
      };

      # Web shortcuts launcher button — static globe icon; click (or Mod+G)
      # opens the fuzzel bookmarks menu. `interval = "once"` renders it a single
      # time since the icon never changes.
      "custom/webshortcuts" = {
        format = "{}";
        exec = "${pkgs.writeShellScript "waybar-webshortcuts" ''
          printf '{"text":"󰖟","tooltip":"Web shortcuts — Mod+G"}\n'
        ''}";
        return-type = "json";
        interval = "once";
        on-click = "web-shortcuts";
      };

      clock = {
        format = "  {:%a %d %b   %H:%M}";
        tooltip-format = "<tt><small>{calendar}</small></tt>";
      };

      # Now-playing. Deliberately NOT waybar's native `mpris` module — that
      # module segfaults the whole bar in 0.15 (clicking it took waybar down).
      # This is a plain custom module driven by playerctl via the waybar-media
      # script: exec-and-display only, so it can never crash waybar. Click
      # toggles play/pause, scroll skips tracks.
      "custom/media" = {
        format = "{}";
        exec = "waybar-media";
        interval = 2;
        return-type = "json";
        max-length = 45;
        on-click = "playerctl play-pause";
        on-scroll-up = "playerctl next";
        on-scroll-down = "playerctl previous";
      };

      # Weather from wttr.in (auto-locates by IP). curl is on PATH; the sed
      # drops the leading '+' wttr prepends to positive temps.
      "custom/weather" = {
        exec = "${pkgs.curl}/bin/curl -s 'wttr.in/?format=%c+%t' | sed 's/+//g'";
        interval = 1800;
        format = "{}";
        tooltip = false;
      };

      cpu = {
        format = "󰻠 {usage}%";
        interval = 2;
        on-click = "ghostty -e btop";
      };
      memory = {
        format = "󰍛 {percentage}%";
        interval = 5;
        tooltip-format = "{used:0.1f}G / {total:0.1f}G used";
        on-click = "ghostty -e btop";
      };

      # CPU temperature read by sensor *name* (k10temp), not hwmon index —
      # the index isn't stable across reboots, and thermal_zone0 here is the
      # wifi card, not the CPU. See the writeShellScript body for details.
      "custom/temp" = {
        exec = "${pkgs.writeShellScript "waybar-temp" ''
          for h in /sys/class/hwmon/hwmon*; do
            if [ "$(cat "$h/name" 2>/dev/null)" = "k10temp" ] && [ -f "$h/temp1_input" ]; then
              c=$(( $(cat "$h/temp1_input") / 1000 ))
              if [ "$c" -ge 85 ]; then cls="critical"; icon="";
              elif [ "$c" -ge 70 ]; then cls="warning"; icon="";
              else cls="normal"; icon=""; fi
              printf '{"text":"%s %s°C","class":"%s","tooltip":"CPU (k10temp): %s°C"}\n' "$icon" "$c" "$cls" "$c"
              exit 0
            fi
          done
          printf '{"text":"","class":"normal"}\n'
        ''}";
        return-type = "json";
        interval = 5;
        format = "{}";
      };

      # Blue-light filter, via the `nightlight` script (home.nix is the single
      # source of truth for its settings). Left-click toggles wlsunset on/off;
      # the toggle signals waybar (signal 8 → SIGRTMIN+8) so the icon updates
      # instantly, with the 30s interval as a fallback. wlsunset can't be
      # queried, so this only reflects running/stopped, not the live temp.
      "custom/nightlight" = {
        exec = "nightlight status";
        return-type = "json";
        interval = 30;
        signal = 8;
        format = "{}";
        on-click = "nightlight toggle";
      };

      # Left-click toggles the eww audio panel; middle-click opens pwvucontrol
      # for deep per-channel work; right-click mutes; scroll nudges volume via
      # swayosd-client so the OSD popup shows. Tooltip names the active sink.
      pulseaudio = {
        format = "{icon} {volume}%";
        format-muted = "󰝟 muted";
        format-icons.default = [
          "󰕿"
          "󰖀"
          "󰕾"
        ];
        tooltip-format = "{desc} · {volume}%";
        on-click = "eww open --toggle audio-panel";
        on-click-middle = "pwvucontrol";
        on-click-right = "swayosd-client --output-volume mute-toggle";
        on-scroll-up = "swayosd-client --output-volume raise --max-volume 100";
        on-scroll-down = "swayosd-client --output-volume lower";
      };
      network = {
        format-wifi = "󰤨 {essid}";
        format-ethernet = "󰈀 wired";
        format-disconnected = "󰤭 offline";
        tooltip-format = "{ifname} · {ipaddr}";
      };

      # ProtonVPN status + quick launch. The official app manages its own
      # WireGuard link; we detect a proton/wg interface to show connected
      # state, and click opens the GUI. Styled green/grey via the class.
      "custom/protonvpn" = {
        exec = "${pkgs.writeShellScript "waybar-protonvpn" ''
          iface=$(ip -o link show 2>/dev/null | grep -oE 'proton0|pvpn[a-z0-9]*|wg[0-9]+' | head -n1)
          if [ -n "$iface" ]; then
            printf '{"text":"󰦝 VPN","class":"connected","tooltip":"ProtonVPN connected (%s) — click to open app"}\n' "$iface"
          else
            printf '{"text":"󰦞 VPN","class":"disconnected","tooltip":"ProtonVPN disconnected — click to open app"}\n'
          fi
        ''}";
        return-type = "json";
        interval = 5;
        format = "{}";
        on-click = "protonvpn-app";
      };

      # Laptop only (see modules-right). The warning/critical classes fire at
      # these capacities while discharging and colour the module.
      battery = {
        states = {
          warning = 30;
          critical = 15;
        };
        format = "{icon} {capacity}%";
        format-charging = "󰂄 {capacity}%";
        format-plugged = "󰚥 {capacity}%";
        format-icons = [
          "󰁺"
          "󰁼"
          "󰁾"
          "󰂀"
          "󰁹"
        ];
        tooltip-format = "{timeTo} · {power:.1f} W";
      };

      tray = {
        spacing = 8;
        icon-size = 16;
      };
    };

    # Styling rules for this bar:
    #  · Hierarchy comes from *lightness*, not hue. The clock is the brightest
    #    thing; stats and metadata recede to textMute; everything at rest is
    #    monochrome.
    #  · Colour is semantic only. A module goes yellow/red/green because it is
    #    telling you something, never because it looked nice. The previous bar
    #    tinted seven modules seven different Nord hues, which meant none of
    #    them registered as important.
    #  · The accent belongs to the focused workspace and nothing else.
    style = ''
      * {
        font-family: "JetBrainsMono Nerd Font", "Symbols Nerd Font";
        font-size: 13px;
        min-height: 0;
      }

      window#waybar {
        background-color: rgba(35, 43, 54, 0.88);   /* surface1 */
        border: 1px solid rgba(63, 74, 92, 0.7);    /* lineStrong */
        border-radius: 12px;
        color: #${ui.textDim};
      }

      #custom-webshortcuts, #workspaces, #window, #clock, #custom-media, #cpu, #memory,
      #custom-temp, #custom-nightlight, #custom-weather, #pulseaudio, #network,
      #custom-protonvpn, #battery, #tray {
        padding: 0 9px;
        margin: 4px 1px;
      }

      /* Workspaces — the only place the accent appears. */
      #workspaces button {
        padding: 0 9px;
        margin: 4px 1px;
        color: #${ui.textFaint};
        background: transparent;
        border-radius: 8px;
      }
      #workspaces button.active {
        background-color: #${ui.accentDeep};
        color: #${ui.text};
      }
      #workspaces button:hover {
        background-color: #${ui.surface3};
        color: #${ui.textDim};
      }

      #custom-webshortcuts { color: #${ui.textMute}; font-size: 15px; }
      #custom-webshortcuts:hover {
        background-color: #${ui.surface3};
        color: #${ui.text};
        border-radius: 8px;
      }

      /* Clock is the anchor of the bar, so it gets the top of the text ramp.
         Nerd Font is monospaced, so the digits already hold their column and
         the bar never reflows on a minute tick. */
      #clock {
        color: #${ui.text};
        letter-spacing: 0.02em;
      }

      /* Focused-window title — the quietest thing on the bar. Italic monospace
         renders as a slanted upright in JetBrains Mono rather than a true
         italic, so it just looks smeared; lightness does the recessing here. */
      #window { color: #${ui.textMute}; }

      /* Ambient readouts. Monochrome at rest — they are glanceable context, not
         alerts, and they change often enough that colour would make the bar
         twitch in peripheral vision. */
      #pulseaudio, #network, #custom-weather, #custom-media, #cpu, #memory, #custom-temp,
      #battery {
        color: #${ui.textMute};
      }
      #custom-media.paused { color: #${ui.textFaint}; }

      /* Thermals — the one ambient readout allowed to escalate. */
      #custom-temp.warning { color: #${ui.warn}; }
      #custom-temp.critical {
        color: #${ui.err};
        animation: blink 1s steps(2, start) infinite;
      }

      /* Battery escalates like thermals, but only while discharging — plugged
         in at 20% isn't something you need to act on. */
      #battery.discharging.warning { color: #${ui.warn}; }
      #battery.discharging.critical {
        color: #${ui.err};
        animation: blink 1s steps(2, start) infinite;
      }
      #battery.charging { color: #${ui.ok}; }

      /* Toggles: lit when on, faint when off. State reads as presence/absence
         of light rather than as two competing colours. */
      #custom-nightlight.on { color: #${ui.warn}; }
      #custom-nightlight.off { color: #${ui.textFaint}; }
      #custom-protonvpn.connected { color: #${ui.ok}; }
      #custom-protonvpn.disconnected { color: #${ui.textFaint}; }

      @keyframes blink {
        to { color: #${ui.text}; }
      }
    '';
  };

  # Dark mode + Nord theming. niri has no settings daemon to broadcast a
  # light/dark preference, so we set it explicitly across the toolkits:
  #  - GTK3 apps read the theme name + the prefer-dark flag below.
  #  - libadwaita/GTK4 apps and browsers read `color-scheme` over the Settings
  #    portal, served by xdg-desktop-portal-gnome (which niri wires up already).
  # These are user-level, so they apply in both the niri and COSMIC sessions.
  gtk = {
    enable = true;
    theme = {
      name = "Nordic";
      package = pkgs.nordic;
    };
    iconTheme = {
      name = "Nordzy-dark";
      package = pkgs.nordzy-icon-theme;
    };
    cursorTheme = {
      name = "Nordzy-cursors";
      package = pkgs.nordzy-cursor-theme;
    };
    gtk3.extraConfig.gtk-application-prefer-dark-theme = 1;
    gtk4.extraConfig.gtk-application-prefer-dark-theme = 1;
  };

  dconf.settings."org/gnome/desktop/interface" = {
    color-scheme = "prefer-dark";
    gtk-theme = "Nordic";
  };

  # Screen locker, run by swayidle (spawned in config.kdl) before sleep and on
  # `loginctl lock-session`. Same ground as the wallpaper; the ring stays quiet
  # at rest and only takes colour to say something: accent while typing,
  # warn while checking, err on a wrong password. Its PAM entry is in
  # modules/common.nix.
  programs.swaylock = {
    enable = true;
    settings = {
      color = ui.bg;
      font = "JetBrainsMono Nerd Font";
      font-size = 18;
      indicator-radius = 90;
      indicator-thickness = 8;
      show-failed-attempts = true;
      ignore-empty-password = true;
      # Without this the ring only appears once you start typing, so the lock
      # screen is a bare ui.bg rectangle that reads as a frozen gray screen.
      indicator-idle-visible = true;

      inside-color = "${ui.surface1}ee";
      inside-clear-color = "${ui.surface1}ee";
      inside-ver-color = "${ui.surface1}ee";
      inside-wrong-color = "${ui.surface1}ee";
      ring-color = ui.lineStrong;
      ring-clear-color = ui.textFaint;
      ring-ver-color = ui.warn;
      ring-wrong-color = ui.err;
      key-hl-color = ui.accent;
      bs-hl-color = ui.err;
      line-color = "00000000";
      line-clear-color = "00000000";
      line-ver-color = "00000000";
      line-wrong-color = "00000000";
      separator-color = "00000000";
      text-color = ui.text;
      text-clear-color = ui.textDim;
      text-ver-color = ui.warn;
      text-wrong-color = ui.err;
    };
  };

  # fuzzel launcher (Mod+D / Mod+Space) — Nord colors, rounded to match waybar.
  # Config-only module; fuzzel is not a daemon, so nothing auto-starts.
  programs.fuzzel = {
    enable = true;
    settings = {
      main = {
        font = "JetBrainsMono Nerd Font:size=12";
        terminal = "ghostty";
        prompt = ''"❯ "'';
        icon-theme = "Nordzy-dark";
        layer = "overlay";
        width = 38;
        lines = 8;
        # Roomier padding + taller rows read as sleeker/less cramped.
        horizontal-pad = 24;
        vertical-pad = 18;
        inner-pad = 14;
        line-height = 26;
        image-size-ratio = 0.9;
      };
      border = {
        # 12px everywhere: niri's geometry-corner-radius, waybar, mako and this
        # all share one radius so surfaces read as one system rather than four
        # separately-tuned widgets.
        width = 1;
        radius = 12;
      };
      # fuzzel colors are RRGGBBAA hex with no leading '#'.
      colors = {
        background = "${ui.surface1}f2";
        text = "${ui.textDim}ff";
        prompt = "${ui.accent}ff";
        input = "${ui.text}ff";
        # The fuzzy-match highlight is the one accent in the list. Selection is
        # carried by the raised surface instead of by colour, so the highlight
        # stays legible on both selected and unselected rows.
        match = "${ui.accent}ff";
        selection = "${ui.surface3}ff";
        selection-text = "${ui.text}ff";
        selection-match = "${ui.accent}ff";
        border = "${ui.lineStrong}cc";
      };
    };
  };

  # mako notification daemon — Nord styling. This HM module installs the package
  # + config only (no systemd service), so mako still runs only when niri starts
  # it via spawn-at-startup; COSMIC keeps using its own notifier.
  services.mako = {
    enable = true;
    settings = {
      font = "JetBrainsMono Nerd Font 11";
      background-color = "#${ui.surface1}f2";
      text-color = "#${ui.textDim}";
      # A blue 2px border on *every* notification is decoration, and it competes
      # with the urgent state for attention. Routine notifications get the same
      # quiet hairline as every other floating surface; the border only turns
      # colour when it has something to say (see urgency=high below).
      border-color = "#${ui.lineStrong}";
      border-size = 1;
      border-radius = 12;
      progress-color = "over #${ui.surface3}";
      default-timeout = 5000;
      anchor = "top-right";
      margin = 12;
      padding = 12;
      width = 360;
      icons = true;
      max-icon-size = 48;
      # Urgent notifications get a red border and don't auto-dismiss. Now that
      # the resting border is a neutral hairline, this actually stands out.
      "urgency=high" = {
        border-color = "#${ui.err}";
        border-size = 2;
        default-timeout = 0;
      };
    };
  };

  programs.zed-editor.enable = true;

  programs.zen-browser = {
    enable = true;
  };

  # programs.firefox lives in ./firefox.nix (imported above) — the userChrome /
  # userContent stylesheets that make it match the session are long enough to
  # warrant their own file.

  programs.git = {
    enable = true;
    settings = {
      user = {
        name = "Jake Kile";
        email = "jkile9@gmail.com";
      };
      # Transparently use SSH for github.com even when a remote is an https URL.
      # Comment out if you'd rather clone with git@github.com:... explicitly.
      url."git@github.com:".insteadOf = "https://github.com/";
      # Always merge on `git pull`, never rebase. Also silences the
      # "divergent branches" hint git prints when this is unset.
      pull.rebase = false;
    };
    # Use the work identity for anything under ~/code/overview.
    includes = [
      {
        condition = "gitdir:~/code/overview/";
        contents.user.email = "jake@overview.app";
      }
    ];
  };

  # SSH — the github.com key is provisioned by sops-nix (see configuration.nix),
  # decrypted at boot to /run/secrets/github_ssh_key (owned by jakek, 0600).
  # The private key itself never lives in this repo; only its encrypted form in
  # ./secrets does.
  programs.ssh = {
    enable = true;
    matchBlocks."github.com" = {
      hostname = "github.com";
      user = "git";
      identityFile = "/run/secrets/github_ssh_key";
      identitiesOnly = true;
    };
  };

  # ---- Starship prompt (Nord) ----
  programs.starship = {
    enable = true;
    enableZshIntegration = true; # zsh is HM-managed; integration wired automatically
    settings = {
      add_newline = true;
      palette = "nord";
      palettes.nord = {
        bg = "#${nord.nord1}";
        fg = "#${nord.nord4}";
        blue = "#${nord.nord8}";
        teal = "#${nord.nord7}";
        indigo = "#${nord.nord10}";
        red = "#${nord.nord11}";
        orange = "#${nord.nord12}";
        yellow = "#${nord.nord13}";
        green = "#${nord.nord14}";
        purple = "#${nord.nord15}";
      };
      format = lib.concatStrings [
        "[](teal)"
        "[ ](bg:teal fg:bg)"
        "[](fg:teal bg:indigo)"
        "$directory"
        "[](fg:indigo bg:blue)"
        "$git_branch$git_status"
        "[](fg:blue)"
        " "
        "$character"
      ];
      character = {
        success_symbol = "[❯](bold green)";
        error_symbol = "[❯](bold red)";
      };
      directory = {
        style = "fg:fg bg:indigo";
        format = "[ $path ]($style)";
        truncation_length = 3;
        truncation_symbol = "…/";
      };
      git_branch = {
        symbol = " ";
        style = "fg:bg bg:blue";
        format = "[ $symbol$branch ]($style)";
      };
      git_status = {
        style = "fg:bg bg:blue";
        format = "[$all_status$ahead_behind ]($style)";
      };
    };
  };

  # ---- fastfetch (Nord-colored) ----
  programs.fastfetch = {
    enable = true;
    settings = {
      logo = {
        source = "nix";
        color = {
          "1" = "blue";
          "2" = "cyan";
        };
        padding = {
          top = 1;
          left = 2;
        };
      };
      display.separator = " → ";
      modules = [
        "title"
        "separator"
        {
          type = "os";
          key = " OS";
          keyColor = "blue";
        }
        {
          type = "kernel";
          key = " Kernel";
          keyColor = "blue";
        }
        {
          type = "de";
          key = " DE";
          keyColor = "cyan";
        }
        {
          type = "wm";
          key = " WM";
          keyColor = "cyan";
        }
        {
          type = "terminal";
          key = " Term";
          keyColor = "cyan";
        }
        {
          type = "shell";
          key = " Shell";
          keyColor = "green";
        }
        {
          type = "packages";
          key = " Pkgs";
          keyColor = "green";
        }
        {
          type = "uptime";
          key = " Up";
          keyColor = "magenta";
        }
        "break"
        {
          type = "cpu";
          key = " CPU";
          keyColor = "yellow";
        }
        {
          type = "gpu";
          key = " GPU";
          keyColor = "yellow";
        }
        {
          type = "memory";
          key = " Mem";
          keyColor = "red";
        }
        "break"
        "colors"
      ];
    };
  };

  programs.eza.enable = true; # ls replacement (aliased below)

  programs.bat = {
    enable = true;
    config.theme = "Nord";
  };

  programs.fzf = {
    enable = true;
    enableZshIntegration = true;
    defaultOptions = [
      "--color=bg+:#3B4252,bg:#2E3440,spinner:#81A1C1,hl:#616E88"
      "--color=fg:#D8DEE9,header:#616E88,info:#81A1C1,pointer:#81A1C1"
      "--color=marker:#81A1C1,fg+:#D8DEE9,prompt:#81A1C1,hl+:#81A1C1"
    ];
  };

  programs.zoxide = {
    enable = true;
    enableZshIntegration = true; # adds `z` / `zi`
  };

  # direnv + nix-direnv — auto-load per-project dev shells (e.g. ~/code/overview's
  # flake) on `cd`. Pairs with the .direnv/ entry already in .gitignore.
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
    enableZshIntegration = true;
  };

  programs.tealdeer = {
    # provides `tldr`
    enable = true;
    settings.updates.auto_update = true;
  };

  # Ghostty terminal emulator (Nord). Launches the zsh below, so every shell
  # alias (ovw → zellij, ll/la → eza, cat → bat, z → zoxide …) and TUI in this
  # config is reachable straight from a new window.
  programs.ghostty = {
    enable = true;
    enableZshIntegration = true; # cursor/title/sudo hooks for the zsh below
    installBatSyntax = true; # register ghostty's syntax with bat (Nord)
    settings = {
      theme = "Nord";
      # nerd-fonts.jetbrains-mono for text, nerd-fonts.symbols-only as the glyph
      # fallback (eza icons, zellij/helix status glyphs).
      font-family = [
        "JetBrainsMono Nerd Font"
        "Symbols Nerd Font"
      ];
      font-size = 12;
      cursor-style = "block";
      # No titlebar/headerbar — niri draws the window edge (see prefer-no-csd in
      # config.kdl), so the terminal is just the rounded, shadowed content rect.
      window-decoration = false;
      gtk-titlebar = false;
      shell-integration = "zsh";
      shell-integration-features = "cursor,sudo,title";
      window-padding-x = 8;
      window-padding-y = 8;
      background-opacity = 1;
      # Quick-launch the wired TUIs (types the command and runs it).
      keybind = [
        "ctrl+shift+o=text:ovw\\n" # zellij `overview` workspace
        "ctrl+shift+e=text:hx .\\n" # helix (default editor)
        "ctrl+shift+g=text:btop\\n" # btop system monitor
        "ctrl+shift+l=text:lazygit\\n" # lazygit git TUI
      ];
    };
  };

  # zellij multiplexer (Nord). No zsh auto-start — launch explicitly via `ovw`.
  programs.zellij = {
    enable = true;
    settings.theme = "nord";
  };

  programs.helix = {
    enable = true;
    defaultEditor = true;
    extraPackages = with pkgs; [
      rust-analyzer # Rust services + shared crates
      elixir-ls # firelink / aldrich (elixir + heex)
      nil # Nix (flake.nix, home-manager)
      nixfmt # Nix formatter (wired below)
      typescript-language-server # e2e/ Playwright specs
      vscode-langservers-extracted # html / css / json (firelink assets, bigtable.json)
      taplo # TOML (Cargo.toml, this config's inputs)
      yaml-language-server # k8s manifests, skaffold, CI workflows
      protols # proto/proto/grpc/*.proto
      marksman # docs/book markdown
      bash-language-server # bin/*.sh
      shellcheck # surfaced through bash-language-server
      dockerfile-language-server # deploy/local/docker, per-service Dockerfiles
      terraform-ls # infra/
      just-lsp # the repo justfile
    ];
    settings = {
      theme = "nord";
      editor = {
        bufferline = "multiple";
        cursorline = true;
        color-modes = true;
        indent-guides.render = true;
        cursor-shape.insert = "bar";
        lsp.display-messages = true;
      };
    };
    languages = {
      # protols isn't in helix's default languages.toml — declare it and attach
      # it to protobuf. Everything else uses helix's stock server wiring (the
      # binaries above match the default `command` names).
      language-server.protols.command = "protols";
      language = [
        {
          name = "protobuf";
          language-servers = [ "protols" ];
        }
        {
          name = "nix";
          auto-format = true;
          formatter.command = "nixfmt";
        }
        {
          name = "elixir";
          auto-format = true;
        }
        {
          name = "heex";
          auto-format = true;
        }
      ];
    };
  };

  programs.delta = {
    enable = true;
    enableGitIntegration = true;
    options = {
      navigate = true;
      line-numbers = true;
      syntax-theme = "Nord";
    };
  };

  # lazygit — git TUI (ghostty ctrl+shift+l). Uses delta as its diff pager to
  # match the git config above, and a Nord palette to match everything else.
  programs.lazygit = {
    enable = true;
    settings = {
      gui = {
        nerdFontsVersion = "3";
        theme = {
          activeBorderColor = [
            "#88C0D0"
            "bold"
          ];
          inactiveBorderColor = [ "#4C566A" ];
          searchingActiveBorderColor = [
            "#88C0D0"
            "bold"
          ];
          optionsTextColor = [ "#81A1C1" ];
          selectedLineBgColor = [ "#3B4252" ];
          cherryPickedCommitBgColor = [ "#434C5E" ];
          cherryPickedCommitFgColor = [ "#88C0D0" ];
          unstagedChangesColor = [ "#BF616A" ];
          defaultFgColor = [ "#D8DEE9" ];
        };
      };
      # lazygit 0.55+ replaced the single git.paging object with a git.pagers
      # array. HM symlinks this config read-only, so the old key made lazygit
      # attempt (and fail) an in-place migration on every launch.
      git.pagers = [
        {
          colorArg = "always";
          pager = "delta --dark --paging=never";
        }
      ];
    };
  };

  # ---- zsh (managed by Home Manager, keeping oh-my-zsh) ----
  programs.zsh = {
    enable = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
    oh-my-zsh = {
      enable = true;
      theme = "robbyrussell"; # starship overrides the prompt anyway
      plugins = [ "git" ];
    };
    shellAliases = {
      ls = "eza --icons --group-directories-first";
      ll = "eza -l --icons --group-directories-first --git";
      la = "eza -la --icons --group-directories-first --git";
      lt = "eza --tree --level=2 --icons";
      cat = "bat"; # bat acts like cat when piped
      ovw = "zellij --layout overview"; # launch the overview workspace
    };
    # fastfetch greeter on interactive shells (starship init is added by HM)
    initContent = ''
      if [[ $- == *i* ]] && command -v fastfetch >/dev/null 2>&1; then
        fastfetch
      fi
    '';
  };
}
