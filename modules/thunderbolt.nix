# Thunderbolt — Apple Studio Display on the board's rear TB4 port.
#
# The display tunnels two independent things over one cable: DisplayPort and
# PCIe. DP tunneling is exempt from Thunderbolt authorization, but the PCIe
# tunnel is not — and the display's USB hub, webcam, speakers and mic all hang
# off an xHCI controller reached over that PCIe tunnel. So on an unauthorized
# device you get a working picture and nothing else, which is exactly the
# failure this module exists to prevent.
#
# The domain runs at security level "user" (SL1), meaning a device stays
# unauthorized until something explicitly approves it. boltd is that something:
# it remembers enrolled devices by UUID and re-authorizes them on every plug.
#
# One-time enrollment, needed once per display (after this the display comes up
# fully on every boot with no intervention):
#   boltctl list                              # find the UUID
#   sudo boltctl enroll --policy auto <uuid>
#
# Deliberately NOT set here:
#   pci=thunderbolt        — not a real kernel parameter; the kernel ignores it
#   amdgpu.vm_update_mode  — GPUVM page-table update mode, unrelated to
#                            Thunderbolt, and forcing CPU updates slows down
#                            compute work on the R9700 (see ./llama-cpp.nix)
{ pkgs, ... }:

{
  # boltd — authorizes enrolled Thunderbolt devices. Without this the Studio
  # Display enumerates (`thunderbolt 0-1: Apple Inc. Studio Display`) but sits
  # at authorized=0 forever. Also provides the `boltctl` CLI used above.
  services.hardware.bolt.enable = true;

  # lspci, setpci — needed to inspect the PCIe topology behind a TB tunnel.
  environment.systemPackages = with pkgs; [ pciutils ];
}
