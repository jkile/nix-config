# Shared system config — applied to EVERY host (desktop, laptop, …).
# Per-machine hardware, GPU, and hostname live in hosts/<name>/default.nix;
# the PipeWire/ULN-8 audio stack lives in modules/audio.nix (also shared).
{
  config,
  pkgs,
  inputs,
  ...
}:

{
  # Bootloader (systemd-boot). configurationLimit caps the loader entries
  # written to the ESP so it can't fill and break a rebuild mid-`switch`.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.systemd-boot.configurationLimit = 20;
  boot.loader.systemd-boot.consoleMode = "max"; # largest console resolution — crisp on hi-res displays
  boot.loader.timeout = 3; # shorter menu; hold a key during POST to pause on it

  # Flicker-free graphical boot. systemd-in-initrd (emergencyAccess below pulls
  # it in) plus early KMS (amdgpu is in each host's initrd) lets Plymouth own the
  # screen from initrd onward — including a graphical LUKS passphrase dialog
  # instead of a raw text prompt. `quiet` + trimmed log levels keep it clean;
  # drop `quiet`/set consoleLogLevel higher when debugging a boot failure.
  boot.plymouth = {
    enable = true;
    theme = "nixos-bgrt"; # animated NixOS snowflake
    themePackages = [ pkgs.nixos-bgrt-plymouth ];
  };
  boot.initrd.verbose = false;
  boot.consoleLogLevel = 3;
  boot.kernelParams = [
    "quiet" # `splash` is added automatically by the plymouth module
    "rd.udev.log_level=3"
    "udev.log_priority=3"
    "pcie_ports=native"  # Enable PCIe native mode for better Thunderbolt support
  ];

  boot.initrd.systemd.emergencyAccess = true;
  hardware.enableRedistributableFirmware = true;

  # Networking
  networking.networkmanager.enable = true;

  # Locale / time / keymap
  time.timeZone = "America/Los_Angeles";
  i18n.defaultLocale = "en_US.UTF-8";
  i18n.extraLocaleSettings = {
    LC_ADDRESS = "en_US.UTF-8";
    LC_IDENTIFICATION = "en_US.UTF-8";
    LC_MEASUREMENT = "en_US.UTF-8";
    LC_MONETARY = "en_US.UTF-8";
    LC_NAME = "en_US.UTF-8";
    LC_NUMERIC = "en_US.UTF-8";
    LC_PAPER = "en_US.UTF-8";
    LC_TELEPHONE = "en_US.UTF-8";
    LC_TIME = "en_US.UTF-8";
  };
  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };

  # User account. The interactive shell config lives in home/home.nix's
  # programs.zsh; programs.zsh.enable here just makes zsh a valid login shell.
  users.users."jakek" = {
    isNormalUser = true;
    description = "Jake Kile";
    extraGroups = [
      "networkmanager"
      "wheel"
      "docker"
    ];
    packages = with pkgs; [ ];
    shell = pkgs.zsh;
  };
  programs.zsh.enable = true;

  virtualisation.docker.enable = true;

  nixpkgs.config.allowUnfree = true;
  environment.systemPackages = with pkgs; [
    # X11 apps under niri (Steam client, older games, anything without a Wayland
    # backend) need an X server. niri has native xwayland-satellite integration:
    # with this binary on PATH and the `xwayland-satellite` node in niri's
    # config.kdl, niri starts it on demand and sets $DISPLAY for spawned clients.
    xwayland-satellite
    k9s
  ];

  # Periodic batched TRIM. Per-device `allowDiscards` is set in each host's LUKS
  # declaration, since the device UUIDs are hardware-specific.
  services.fstrim.enable = true;
  services.fwupd.enable = true; # firmware/BIOS updates via LVFS (`fwupdmgr`)

  # Desktop environment
  services.desktopManager.cosmic.enable = true;
  services.displayManager.cosmic-greeter.enable = true;

  programs.niri.enable = true;

  # Run Electron/Chromium apps (Discord, Zed, etc.) natively on Wayland rather
  # than through XWayland — sharper rendering, proper fractional scaling, and no
  # dependence on the X server. (XWayland itself is available via
  # xwayland-satellite above, for X11-only apps like the Steam client.)
  environment.sessionVariables.NIXOS_OZONE_WL = "1";

  # OpenSSH — enabled primarily so each host generates its
  # /etc/ssh/ssh_host_ed25519_key, which sops-nix uses to decrypt secrets at
  # activation. The daemon is NOT exposed (openFirewall = false, no passwords).
  services.openssh = {
    enable = true;
    openFirewall = false;
    settings.PasswordAuthentication = false;
  };

  # ---- Secrets (sops-nix) ----
  # Secrets live encrypted in ../secrets/secrets.yaml (committed). Each machine
  # decrypts with the age key derived from its SSH host key; ../.sops.yaml lists
  # one host key per machine. Adding a host = append its key there + updatekeys.
  sops = {
    defaultSopsFile = ../secrets/secrets.yaml;
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    secrets."github_ssh_key" = {
      owner = "jakek";
      mode = "0600";
    };
  };

  # ---- Nix ----
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  # Keep the store bounded: weekly GC of anything older than 30 days, plus
  # hardlink-dedupe of identical store paths on every build.
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };
  nix.settings.auto-optimise-store = true;

  # Prebuilt binaries for community / Helix-master builds. `extra-*` appends to
  # the default cache.nixos.org rather than replacing it.
  nix.settings.extra-substituters = [
    "https://helix.cachix.org"
    "https://nix-community.cachix.org"
  ];
  nix.settings.extra-trusted-public-keys = [
    "helix.cachix.org-1:ejp9KQpR1FBI2onstMQ34yogDm4OgU2ru6lIwPvuCVs="
    "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
  ];
}
