{

  ################################
  # Hybrid graphics: Intel UHD + NVIDIA RTX 4060 Laptop GPU
  ################################
  #
  # The Intel GPU runs the desktop and the laptop's own screen; the RTX 4060
  # powers down when nothing uses it and wakes for what's started on it
  # (PRIME render offload): Steam and its games (gaming.nix), anything
  # right-clicked in the app menu → "Run using dedicated graphics card",
  # and `nvidia-offload <command>` in a terminal. That keeps battery life
  # close to an Intel-only laptop. On most laptops like this one the HDMI
  # port is wired to the NVIDIA GPU, so an external display there wakes it
  # for as long as the display is connected.

  # The name is historical: this loads the NVIDIA driver for Wayland too.
  services.xserver.videoDrivers = [ "nvidia" ];

  hardware.nvidia = {
    # NVIDIA's open kernel module: the one NVIDIA recommends for RTX 20-series
    # and newer, and the only one it develops further. (The default driver
    # version, nvidiaPackages.stable, follows the NixOS release.)
    open = true;
    # Kernel modesetting, which Plasma on Wayland needs.
    modesetting.enable = true;
    # Saves the GPU's memory across suspend, so games and apps on the GPU
    # survive closing the lid; and powers the GPU fully off when idle
    # (fine-grained power management, RTX 20-series and newer, offload only).
    powerManagement = {
      enable = true;
      finegrained = true;
    };
    # Dynamic Boost (nvidia-powerd): on AC, shifts power from the CPU to the
    # GPU when a game is GPU-bound, as NVIDIA's Windows driver does.
    dynamicBoost.enable = true;
    # The nvidia-settings app mostly configures X11, which Plasma on Wayland
    # doesn't use; `nvidia-smi` shows the GPU's state instead.
    nvidiaSettings = false;
    # No NVIDIA video decoding (nvidia-vaapi-driver, on by default): the
    # Intel GPU decodes video (hardware.nix), so the RTX 4060 can stay off
    # while a video plays.
    videoAcceleration = false;
    prime = {
      offload = {
        enable = true;
        # The `nvidia-offload` command.
        enableOffloadCmd = true;
      };
      # The two GPUs' PCI addresses, in decimal (lspci shows them in hex:
      # 00:02.0 and 01:00.0). These are the usual ones for an Intel laptop
      # with an NVIDIA GPU; check with `lspci | grep -E 'VGA|3D'` (see the
      # hardware checklist in README.md). Only X11 reads them, so a wrong
      # value here doesn't break the Wayland desktop.
      intelBusId = "PCI:0:2:0";
      nvidiaBusId = "PCI:1:0:0";
    };
  };

  # The driver is unfree; allowed by name (see "Unfree packages" in base.nix).
  my.unfreePackages = [ "nvidia-x11" ];

  # Tells Plasma which GPU is the dedicated one, for the app menu's "Run
  # using dedicated graphics card" and apps that ask for it in their
  # .desktop file (PrefersNonDefaultGPU).
  services.switcherooControl.enable = true;

}
