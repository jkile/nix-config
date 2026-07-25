# Desktop host "jakek" — Radeon AI PRO R9700 (Navi 48, RDNA4, 32 GB) on an
# Intel Core Ultra 7 270K Plus (Arrow Lake-S). Hardware-specific bits only;
# everything portable is in modules/common.nix, and audio (including the ULN-8
# tuning) is in modules/audio.nix — both pulled in by the flake for every host.
{
  config,
  pkgs,
  ...
}:

{
  imports = [
    ./hardware-configuration.nix
    ./llama-cpp.nix # local Qwen3-Coder inference on the R9700 + the `qwen` CLI
  ];

  networking.hostName = "jakek";

  # GPU — Radeon AI PRO R9700 (Navi 48, RDNA4, amdgpu). Declared explicitly
  # rather than relying on COSMIC's implicit enable, so the driver + VA-API
  # stack is pinned and diagnosable. `vainfo` (from libva-utils) verifies HW
  # video decode.
  boot.initrd.kernelModules = [ "amdgpu" ];
  hardware.graphics = {
    enable = true;
    enable32Bit = true; # 32-bit GL/VA-API (games, wine, some media paths)
    extraPackages = with pkgs; [
      libva-utils # `vainfo` diagnostics; Mesa/radeonsi provides native VA-API
      libvdpau-va-gl # VDPAU->VA-API shim for the odd app that wants VDPAU
    ];
  };
  # RDNA4 is most stable on Mesa's RADV; ensure nothing silently picks amdvlk.
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

  # FPS/vitals overlay + a Proton tweak helper. llama.cpp, vulkan-tools and the
  # Qwen Code CLI moved to ./llama-cpp.nix.
  environment.systemPackages = with pkgs; [
    mangohud
    protontricks
  ];

  # Encrypted root + swap. The `.device` for each LUKS container is declared in
  # hardware-configuration.nix (cryptroot) plus the cryptswap line added there;
  # the allowDiscards merges below attach to them by matching name.
  # allowDiscards so TRIM (services.fstrim, enabled in common) reaches the SSD.
  # Tradeoff: discard reveals which blocks are unused to disk access.
  boot.initrd.luks.devices."cryptroot".allowDiscards = true;
  boot.initrd.luks.devices."cryptswap".allowDiscards = true;

  # First-install release for this machine's stateful data — leave as-is.
  system.stateVersion = "26.05";
}
