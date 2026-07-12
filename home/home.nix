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
in
{
  imports = [ inputs.zen-browser.homeModules.beta ];

  home.username = "jakek";
  home.homeDirectory = "/home/jakek";
  home.stateVersion = "26.05";

  home.packages = with pkgs; [
    pkgs.discord
    ripgrep
    fd
    procs
    btop
    nerd-fonts.jetbrains-mono
    nerd-fonts.symbols-only
    nordic
    nordzy-icon-theme
    nordzy-cursor-theme
    claude-code
    qpwgraph # PipeWire patchbay — route the ULN-8's 12 discrete channels
    pavucontrol # quick check of device profile / per-channel levels

    sops
    age
    ssh-to-age

    fuzzel
    waybar
    mako
  ];

  xdg.configFile."niri/config.kdl".source = ./niri/config.kdl;
  programs.home-manager.enable = true;

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
