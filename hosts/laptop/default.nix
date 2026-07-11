# Laptop host — TEMPLATE, not yet wired into the flake.
#
# Before this builds, do the following ON THE LAPTOP (in order — the sops step
# matters, see SETUP-SECRETS.md):
#   1. Install NixOS, then `nixos-generate-config` and copy the generated
#      hardware-configuration.nix into this directory. (That file sets your
#      filesystems, LUKS root device, swap, CPU microcode, and initrd modules
#      automatically — so you don't hand-write any of it.)
#   2. `ssh-to-age < /etc/ssh/ssh_host_ed25519_key.pub` → add the result to
#      ../../.sops.yaml as `&host_<name>`, then run
#      `sops updatekeys secrets/secrets.yaml` ON THE DESKTOP (where the admin
#      key lives) and push. Do this BEFORE the first full rebuild, or the
#      github_ssh_key secret won't decrypt on the laptop.
#   3. Set the hostname + stateVersion below and uncomment your GPU block.
#   4. Uncomment the `jakek-laptop` entry in flake.nix, then
#      `nixos-rebuild switch --flake .#jakek-laptop` on the laptop.
{
  config,
  pkgs,
  lib,
  ...
}:

{
  imports = [ ./hardware-configuration.nix ]; # generated on the laptop (step 1)

  networking.hostName = "jakek-laptop"; # TODO: set the real hostname

  # ---- GPU ----
  # nixos-generate-config already sets the kernel modules + microcode; this is
  # the userspace driver bit. Uncomment ONE block matching the hardware.
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };
  #
  # Intel iGPU:
  #   hardware.graphics.extraPackages = with pkgs; [ intel-media-driver libvdpau-va-gl ];
  #   environment.variables.LIBVA_DRIVER_NAME = "iHD";
  #   services.thermald.enable = true;   # Intel thermal management daemon
  #
  # AMD (APU / Radeon) — mirror the desktop:
  #   hardware.graphics.extraPackages = with pkgs; [ libva-utils libvdpau-va-gl ];
  #   environment.variables.AMD_VULKAN_ICD = "RADV";
  #
  # Nvidia hybrid (Intel/AMD iGPU + Nvidia dGPU):
  #   services.xserver.videoDrivers = [ "nvidia" ];
  #   hardware.nvidia = {
  #     modesetting.enable = true;
  #     open = true;                 # use the open kernel modules (Turing/RTX-20xx+)
  #     prime.offload.enable = true; # + set intelBusId/nvidiaBusId from `lspci`
  #   };

  # ---- Power management ----
  powerManagement.enable = true;
  # power-profiles-daemon integrates with COSMIC's power UI (simplest). For
  # longer battery life swap it for TLP — but don't enable both at once.
  services.power-profiles-daemon.enable = true;
  # services.tlp.enable = true;

  services.logind.lidSwitch = "suspend";
  hardware.bluetooth.enable = true;

  # ---- TRIM ----
  # Once you know the laptop's LUKS device name from the generated
  # hardware-configuration.nix, add (mirrors the desktop; fstrim is on in common):
  #   boot.initrd.luks.devices."luks-XXXXXXXX".allowDiscards = true;

  system.stateVersion = "26.05"; # TODO: set to the laptop's install release
}
