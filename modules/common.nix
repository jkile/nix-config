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
  environment.systemPackages = with pkgs; [ ];

  # Periodic batched TRIM. Per-device `allowDiscards` is set in each host's LUKS
  # declaration, since the device UUIDs are hardware-specific.
  services.fstrim.enable = true;
  services.fwupd.enable = true; # firmware/BIOS updates via LVFS (`fwupdmgr`)

  # Desktop environment
  services.desktopManager.cosmic.enable = true;
  services.displayManager.cosmic-greeter.enable = true;

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
