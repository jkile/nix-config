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
  inputs,
  ...
}:

{
  imports = [
    ./hardware-configuration.nix # generated on the laptop (step 1)
    # Framework 13 Pro — Intel Core Ultra Series 3 (Panther Lake). Brings fwupd,
    # a new-enough kernel, nvme/s2idle power fixes, fprintd, and the EC tools.
    # If `lscpu` on the laptop says AMD instead, swap for framework-amd-ai-300-series.
    inputs.nixos-hardware.nixosModules.framework-intel-core-ultra-series3
  ];

  networking.hostName = "jakek-laptop"; # TODO: set the real hostname

  # ---- GPU ----
  # nixos-generate-config already sets the kernel modules + microcode; this is
  # the userspace driver bit. Uncomment ONE block matching the hardware.
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };
  # Intel Xe3 iGPU: iHD is the VA-API driver for Gen12+; thermald manages
  # Intel thermal limits. `vainfo` (libva-utils) verifies HW video decode.
  hardware.graphics.extraPackages = with pkgs; [
    intel-media-driver
    libva-utils
    libvdpau-va-gl
  ];
  environment.variables.LIBVA_DRIVER_NAME = "iHD";
  services.thermald.enable = true;
  # Panel Self Refresh freezes the panel after s2idle resume: the system and
  # input are alive (power key still suspends), but the screen stays on the last
  # frame — swaylock's plain nord1 background before its indicator draws — so it
  # looks like an unresponsive gray screen. Every boot also logs
  #   xe 0000:00:02.0: [drm] Selective fetch area calculation failed in pipe A
  # Costs a little idle battery. Revisit on a newer kernel (6.18.43 at time of
  # writing); `xe.enable_psr2_sel_fetch=0` is the narrower thing to try first.
  boot.kernelParams = [ "xe.enable_psr=0" ];
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

  # The Intel PCIe Bluetooth controller (btintel_pcie) refuses to enter D3, which
  # aborts every suspend: the lid closes, suspend fails twice (~4s each) and the
  # machine stays awake with the screen off:
  #   Bluetooth: hci0: Timeout (3000 ms) on alive interrupt for D3 entry
  #   btintel_pcie 0000:00:14.7: PM: failed to suspend async: error -16
  # Unloading the driver before sleep and reloading it on wake sidesteps it.
  # Revisit on a newer kernel (6.18.43 at time of writing).
  powerManagement.powerDownCommands = "${pkgs.kmod}/bin/modprobe -r btintel_pcie || true";
  powerManagement.resumeCommands = "${pkgs.kmod}/bin/modprobe btintel_pcie || true";

  # ---- TRIM ----
  # Once you know the laptop's LUKS device name from the generated
  # hardware-configuration.nix, add (mirrors the desktop; fstrim is on in common):
  #   boot.initrd.luks.devices."luks-XXXXXXXX".allowDiscards = true;

  system.stateVersion = "26.05"; # TODO: set to the laptop's install release
}
