{
  pkgs,
  inputs,
  lib,
  ...
}:

let
  # Nord palette — https://www.nordtheme.com/
  nord = {
    # Polar Night (dark bases)
    nord0 = "2E3440";
    nord1 = "3B4252";
    nord2 = "434C5E";
    nord3 = "4C566A";
    # Snow Storm (light text)
    nord4 = "D8DEE9";
    nord5 = "E5E9F0";
    nord6 = "ECEFF4";
    # Frost (blue/teal accents)
    nord7 = "8FBCBB";
    nord8 = "88C0D0";
    nord9 = "81A1C1";
    nord10 = "5E81AC";
    # Aurora (colored accents)
    nord11 = "BF616A"; # red
    nord12 = "D08770"; # orange
    nord13 = "EBCB8B"; # yellow
    nord14 = "A3BE8C"; # green
    nord15 = "B48EAD"; # purple
  };

  # Discord hangs under Wayland-native rendering on this machine (the renderer
  # pegs a core on the loading screen, even with --disable-gpu). Running it under
  # XWayland (via xwayland-satellite on :12, spawned by niri) works. This wrapper
  # forces just Discord onto X11 — NIXOS_OZONE_WL stays global so other Electron
  # apps keep sharp Wayland-native rendering.
  #
  # XWayland can't do per-monitor scaling, so Discord renders at native 1x. On
  # the 2x Apple display use Discord's own zoom (Ctrl+= / Ctrl+-, which persists)
  # to size it up; leave it at 100% on the 1x ultrawide.
  discord-x11 = pkgs.symlinkJoin {
    name = "discord-x11";
    paths = [ pkgs.discord ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      for b in Discord discord; do
        rm -f "$out/bin/$b"
        makeWrapper ${pkgs.discord}/bin/Discord "$out/bin/$b" \
          --unset NIXOS_OZONE_WL \
          --set DISPLAY :12 \
          --add-flags "--ozone-platform=x11"
      done
    '';
  };
in
{
  imports = [ inputs.zen-browser.homeModules.beta ];

  home.username = "jakek";
  home.homeDirectory = "/home/jakek";
  home.stateVersion = "26.05";

  home.packages = with pkgs; [
    discord-x11 # Discord wrapped to run under XWayland (see let binding above)
    xwayland-satellite # provides the :12 X server that discord-x11 targets
    ripgrep
    fd
    procs
    btop
    nerd-fonts.jetbrains-mono
    nerd-fonts.symbols-only
    # Nord GTK theme + Nordzy icons/cursor are installed via the `gtk` module
    # below (theme/iconTheme/cursorTheme .package), so they're not listed here.
    claude-code
    qpwgraph # PipeWire patchbay — route the ULN-8's 12 discrete channels
    pavucontrol # quick check of device profile / per-channel levels

    sops
    age
    ssh-to-age
  ];

  xdg.configFile."niri/config.kdl".source = ./niri/config.kdl;
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

      modules-left = [ "niri/workspaces" ];
      modules-center = [ "clock" ];
      modules-right = [
        "pulseaudio"
        "network"
        "tray"
      ];

      "niri/workspaces".format = "{icon}";
      clock = {
        format = "  {:%a %d %b   %H:%M}";
        tooltip-format = "<tt><small>{calendar}</small></tt>";
      };
      pulseaudio = {
        format = "{icon} {volume}%";
        format-muted = "󰝟 muted";
        format-icons.default = [
          "󰕿"
          "󰖀"
          "󰕾"
        ];
        on-click = "pavucontrol";
      };
      network = {
        format-wifi = "󰤨 {essid}";
        format-ethernet = "󰈀 wired";
        format-disconnected = "󰤭 offline";
        tooltip-format = "{ifname} · {ipaddr}";
      };
      tray = {
        spacing = 8;
        icon-size = 16;
      };
    };

    # Nord palette (matches the rest of this config). Translucent surfaces use
    # rgba literals: nord0 = 46,52,64 · nord1 = 59,66,82 · nord3 = 76,86,106.
    style = ''
      * {
        font-family: "JetBrainsMono Nerd Font", "Symbols Nerd Font";
        font-size: 13px;
        min-height: 0;
      }

      window#waybar {
        background-color: rgba(46, 52, 64, 0.85);
        border: 1px solid rgba(76, 86, 106, 0.6);
        border-radius: 12px;
        color: #${nord.nord4};
      }

      #workspaces, #clock, #pulseaudio, #network, #tray {
        padding: 0 10px;
        margin: 4px 2px;
      }

      #workspaces button {
        padding: 0 8px;
        margin: 4px 2px;
        color: #${nord.nord4};
        background: transparent;
        border-radius: 8px;
      }
      #workspaces button.active {
        background-color: #${nord.nord10};
        color: #${nord.nord6};
      }
      #workspaces button:hover {
        background-color: rgba(76, 86, 106, 0.6);
      }

      #clock { color: #${nord.nord8}; font-weight: bold; }
      #pulseaudio { color: #${nord.nord7}; }
      #network { color: #${nord.nord9}; }
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
        # Thin, high-radius border feels more modern than a chunky one.
        width = 1;
        radius = 16;
      };
      # fuzzel colors are RRGGBBAA hex with no leading '#'.
      colors = {
        background = "${nord.nord0}f0";
        text = "${nord.nord4}ff";
        prompt = "${nord.nord8}ff";
        input = "${nord.nord6}ff";
        match = "${nord.nord8}ff";
        selection = "${nord.nord3}ff";
        selection-text = "${nord.nord6}ff";
        selection-match = "${nord.nord8}ff";
        border = "${nord.nord3}cc";
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
      background-color = "#${nord.nord0}f2";
      text-color = "#${nord.nord4}";
      border-color = "#${nord.nord10}";
      border-size = 2;
      border-radius = 12;
      progress-color = "over #${nord.nord3}";
      default-timeout = 5000;
      anchor = "top-right";
      margin = 12;
      padding = 12;
      width = 360;
      icons = true;
      max-icon-size = 48;
      # Urgent notifications get a red (nord11) border and don't auto-dismiss.
      "urgency=high" = {
        border-color = "#${nord.nord11}";
        default-timeout = 0;
      };
    };
  };

  programs.zed-editor.enable = true;

  programs.zen-browser = {
    enable = true;
  };

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
      shell-integration = "zsh";
      shell-integration-features = "cursor,sudo,title";
      window-padding-x = 8;
      window-padding-y = 8;
      background-opacity = 0.98;
      # Quick-launch the wired TUIs (types the command and runs it).
      keybind = [
        "ctrl+shift+o=text:ovw\\n" # zellij `overview` workspace
        "ctrl+shift+e=text:hx .\\n" # helix (default editor)
        "ctrl+shift+g=text:btop\\n" # btop system monitor
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
