# Desktop host "jakek" — Radeon RX 6700 XT. Hardware-specific bits only;
# everything portable is in modules/common.nix, and audio (including the ULN-8
# tuning) is in modules/audio.nix — both pulled in by the flake for every host.
{
  config,
  pkgs,
  ...
}:

{
  imports = [ ./hardware-configuration.nix ];

  networking.hostName = "jakek";

  # GPU — Radeon RX 6700 XT (RDNA2, amdgpu). Declared explicitly rather than
  # relying on COSMIC's implicit enable, so the driver + VA-API stack is pinned
  # and diagnosable. `vainfo` (from libva-utils) verifies HW video decode.
  boot.initrd.kernelModules = [ "amdgpu" ];
  hardware.graphics = {
    enable = true;
    enable32Bit = true; # 32-bit GL/VA-API (games, wine, some media paths)
    extraPackages = with pkgs; [
      libva-utils # `vainfo` diagnostics; Mesa/radeonsi provides native VA-API
      libvdpau-va-gl # VDPAU->VA-API shim for the odd app that wants VDPAU
    ];
  };
  # RDNA2 is most stable on Mesa's RADV; ensure nothing silently picks amdvlk.
  environment.variables.AMD_VULKAN_ICD = "RADV";

  # ---- Steam / gaming ----
  # Always the module, never the bare `steam` package: it provides the FHS
  # runtime, the 32-bit driver path (satisfied by hardware.graphics.enable32Bit
  # above — required for Proton/DXVK's 32-bit Vulkan), controller udev rules, and
  # steam-run. Unfree is already allowed in modules/common.nix.
  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true; # Steam Remote Play / In-Home Streaming
    localNetworkGameTransfers.openFirewall = true; # LAN game transfers between machines
    # gamescopeSession.enable = true; # optional: adds a "Steam (gamescope)" login session
  };

  # gamescope — micro-compositor for clean fullscreen scaling / VRR under
  # Wayland (COSMIC). Use per-title via a Steam launch option: `gamescope -- %command%`.
  programs.gamescope.enable = true;

  # gamemode — transient perf tweaks (CPU governor, niceness) only while a game
  # runs. Enable per-title in Steam launch options: `gamemoderun %command%`.
  programs.gamemode.enable = true;

  # FPS/vitals overlay + a Proton tweak helper.
  environment.systemPackages = with pkgs; [
    mangohud
    protontricks
  ];

  # Encrypted swap partition (the root LUKS device is declared in
  # hardware-configuration.nix; the allowDiscards line below merges into it).
  # allowDiscards on both so TRIM (services.fstrim, enabled in common) reaches
  # the SSD. Tradeoff: discard reveals which blocks are unused to disk access.
  boot.initrd.luks.devices."luks-8c1d225b-e2fc-4565-a496-96a750c2fcb6" = {
    device = "/dev/disk/by-uuid/8c1d225b-e2fc-4565-a496-96a750c2fcb6";
    allowDiscards = true;
  };
  boot.initrd.luks.devices."luks-b8718736-e3c5-41d5-9c69-4c4106b76491".allowDiscards = true;

  # First-install release for this machine's stateful data — leave as-is.
  system.stateVersion = "26.05";
}
