# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, inputs, ... }:

{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
    ];

  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  
  boot.initrd.kernelModules = [ "amdgpu" ];
  hardware.enableRedistributableFirmware = true;

  # GPU (Radeon RX 6700 XT / RDNA2, amdgpu). Declared explicitly rather than
  # relying on COSMIC's implicit enable, so the driver + VA-API stack is
  # pinned and diagnosable. `vainfo` (from libva-utils) verifies HW video decode.
  hardware.graphics = {
    enable = true;
    enable32Bit = true; # 32-bit GL/VA-API (games, wine, some media paths)
    extraPackages = with pkgs; [
      libva-utils    # `vainfo` diagnostics; Mesa/radeonsi provides native VA-API
      libvdpau-va-gl # VDPAU->VA-API shim for the odd app that wants VDPAU
    ];
  };

  # RDNA2 is most stable on Mesa's RADV; ensure nothing silently picks amdvlk.
  environment.variables.AMD_VULKAN_ICD = "RADV";

  boot.initrd.luks.devices."luks-8c1d225b-e2fc-4565-a496-96a750c2fcb6".device = "/dev/disk/by-uuid/8c1d225b-e2fc-4565-a496-96a750c2fcb6";
  networking.hostName = "nixos"; # Define your hostname.
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Enable networking
  networking.networkmanager.enable = true;

  # Set your time zone.
  time.timeZone = "America/Los_Angeles";

  # Select internationalisation properties.
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

  # Configure keymap in X11
  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users."jakek" = {
    isNormalUser = true;
    description = "Jake Kile";
    extraGroups = [ "networkmanager" "wheel" ];
    packages = with pkgs; [];
    shell = pkgs.zsh; # login shell — so ghostty (and every terminal) launches zsh
  };

  # Required for zsh to be a valid login shell (adds it to /etc/shells + system
  # zsh init). The interactive config itself lives in home.nix's programs.zsh.
  programs.zsh.enable = true;

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
  #  vim # Do not forget to add an editor to edit configuration.nix! The Nano editor is also installed by default.
  #  wget
  ];

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  # List services that you want to enable:

  # OpenSSH — enabled primarily so NixOS generates the host keypair at
  # /etc/ssh/ssh_host_ed25519_key, which sops-nix uses to decrypt secrets at
  # activation (see the `sops` block below). The daemon is NOT exposed:
  # openFirewall = false keeps port 22 closed, and password auth is off. Flip
  # openFirewall to true later if you ever want to SSH into this box.
  services.openssh = {
    enable = true;
    openFirewall = false;
    settings.PasswordAuthentication = false;
  };

  # ---- Secrets (sops-nix) ----
  # Secrets live encrypted in ./secrets/secrets.yaml (committed to git). This
  # machine decrypts them with the age key derived from its SSH host key. See
  # ./.sops.yaml for the recipient list and the setup notes for the workflow.
  sops = {
    defaultSopsFile = ./secrets/secrets.yaml;
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

    # Decrypt the GitHub SSH private key to /run/secrets/github_ssh_key, owned
    # by jakek with 0600 perms so ssh will accept it. home.nix points ssh's
    # identityFile at this path.
    secrets."github_ssh_key" = {
      owner = "jakek";
      mode = "0600";
    };
  };

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "26.05"; # Did you read the comment?


  # Audio — PipeWire, pinned explicitly rather than relying on COSMIC's
  # implicit enable, so the full stack (ALSA/Pulse/JACK) is declared and
  # diagnosable. The Metric Halo ULN-8 enumerates as a USB Audio Class 2
  # compliant device, so mainline snd-usb-audio drives it with no quirks;
  # all 8x8 analog channels appear once the device is switched to the
  # "Pro Audio" profile (WirePlumber drop-in to follow).
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
        "default.clock.allowed-rates" = [ 44100 48000 88200 96000 176400 192000 ];
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
          actions.update-props."device.profile" =
            "output:multichannel-output+input:multichannel-input";
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

  # Desktop environment

  services.desktopManager.cosmic.enable = true;
  services.displayManager.cosmic-greeter.enable = true;

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

}
