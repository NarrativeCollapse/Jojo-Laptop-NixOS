# The kernel: CachyOS's LTS kernel instead of NixOS's own, from the
# nix-cachyos-kernel flake (flake.nix adds its overlay, which provides
# pkgs.cachyosKernels). CachyOS tunes the kernel for desktop and gaming
# responsiveness: its patch set, 1000 Hz timer, full preemption, the ADIOS
# disk scheduler and -O3 builds; this one is also compiled for x86-64-v3,
# the instruction set of jojo's i7-13620H.
#
# Where it comes from, since it's different from the rest of the system:
# - The flake builds its kernels from its own nixpkgs, nixos-unstable-small,
#   not 26.05. So the kernel, and everything built against it (the NVIDIA
#   driver, the battery driver, xpadneo), come from unstable; the rest of
#   the system stays on 26.05. `update` moves it along with everything else.
# - The kernel itself downloads prebuilt from the flake author's binary
#   cache (modules/cachyos-cache.nix), not from cache.nixos.org; the NVIDIA
#   module and the small drivers compile on the laptop, a few minutes per
#   kernel update.
#
# NixOS's own kernel is always in the boot menu too (the "nixos-kernel"
# entry, below). To go back to it for good: delete this file's import in
# hosts/jojo/configuration.nix (the overlay in flake.nix can stay), then
# rebuild.
{ lib, pkgs, ... }:

{
  imports = [ ./cachyos-cache.nix ];

  # A second boot menu entry for every version, "nixos-kernel": the same
  # system with NixOS 26.05's own kernel (and the NVIDIA driver that comes
  # with it). If a CachyOS kernel update stops jojo booting or breaks the
  # NVIDIA driver, or its cache goes away, it's one boot away, without
  # editing anything. It costs a second set of kernel modules and NVIDIA
  # driver on disk (about 1 GB) and a few more minutes on some updates.
  specialisation.nixos-kernel.configuration = {
    boot.kernelPackages = lib.mkForce pkgs.linuxPackages;
  };

  # The LTS line (6.18, the series NixOS 26.05 itself uses) rather than
  # CachyOS's newest kernel, so NVIDIA's driver and the out-of-tree modules
  # build against it reliably. Non-LTO, because out-of-tree modules (NVIDIA)
  # build with GCC. It keeps the mainline scheduler (EEVDF); CachyOS's BORE
  # scheduler is only in its newest-kernel variant. Both alternatives are
  # among the variants the flake's build server prebuilds:
  #   pkgs.cachyosKernels.linuxPackages-cachyos-bore-x86_64-v3    (BORE)
  #   pkgs.cachyosKernels.linuxPackages-cachyos-latest-x86_64-v3  (newest)
  boot.kernelPackages = pkgs.cachyosKernels.linuxPackages-cachyos-lts-x86_64-v3;
}
