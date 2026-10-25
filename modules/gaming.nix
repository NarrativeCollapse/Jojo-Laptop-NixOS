{ pkgs, ... }:

{
  ################################
  # Gaming: Steam + Proton
  ################################

  programs.steam = {
    enable = true;
    # Steam and every game it starts run on the RTX 4060 (PRIME render
    # offload, see nvidia.nix), however Steam is opened. Without this,
    # native Linux games would land on the Intel GPU. The cost: the NVIDIA
    # GPU stays awake while Steam is running, so on battery quit Steam
    # (Steam menu → Exit) rather than leaving it in the tray.
    package = pkgs.steam.override {
      extraEnv = {
        __NV_PRIME_RENDER_OFFLOAD = "1";
        __NV_PRIME_RENDER_OFFLOAD_PROVIDER = "NVIDIA-G0";
        __GLX_VENDOR_LIBRARY_NAME = "nvidia";
        __VK_LAYER_NV_optimus = "NVIDIA_only";
      };
    };
    # Remote Play (streaming games from this laptop to another device) would
    # open TCP 27036-27037 and UDP 10400-10401/27031-27036 on every network,
    # public Wi-Fi included. Off: Steam and online play only connect
    # outward and don't need them. Set to true to stream to a TV or another
    # PC on your network.
    remotePlay.openFirewall = false;
    # dedicatedServer.openFirewall (27015) is deliberately off: it is only
    # for hosting Source dedicated servers.
    #
    # No gamescope session (Steam's Big Picture as its own session at the
    # login screen): gamescope then drives the display itself, and on a
    # laptop where the Intel GPU runs the screen and games run on the RTX
    # 4060 it tends to pick the wrong GPU and show a black screen. Big
    # Picture inside Plasma (Steam → View → Big Picture Mode) does the same
    # job.
    # Proton-GE shows up in each game's Properties → Compatibility list next
    # to Valve's Proton builds. It updates with the rest of the system (via
    # flake.lock updates) instead of through ProtonUp-Qt.
    extraCompatPackages = [ pkgs.proton-ge-bin ];
  };
  # Steam is unfree; allowed by name (see "Unfree packages" in base.nix).
  my.unfreePackages = [
    "steam"
    "steam-unwrapped"
  ];

  ################################
  # Xbox wireless controller (Bluetooth)
  ################################

  hardware.xpadneo.enable = true;

  ################################
  # Game optimization helpers
  ################################

  # GameMode, while a game runs under it (`steam-hud`, or `gamemoderun
  # %command%` in a game's launch options): the CPU's performance governor,
  # the game pinned to the i7's 6 performance cores (its 4 efficiency cores
  # are left to everything else; GameMode detects Intel's P- and E-cores),
  # and no screen locking. Its defaults already do all of that.
  programs.gamemode.enable = true;

  # NTSYNC: the kernel's own version of Windows' thread-synchronization
  # calls (Linux 6.14 and later). Wine 11, and the Protons built on it
  # (GE-Proton 11, installed below), use it instead of emulating them
  # whenever /dev/ntsync exists, which helps CPU-heavy Windows games run
  # more smoothly. The kernel has it as a module that nothing loads, and
  # its device would be root-only; Wine opens it read-only.
  boot.kernelModules = [ "ntsync" ];
  services.udev.extraRules = ''
    KERNEL=="ntsync", MODE="0644"
  '';

  # Split-lock throttling off, as on the Steam Deck (SteamOS) and Bazzite.
  # Intel CPUs from the 12th generation on detect "split locks" (an atomic
  # memory operation across two cache lines, which stalls every core), and
  # the kernel then slows the program that caused it on purpose. Some
  # Windows games do it constantly and stutter badly. GameMode already lifts
  # it while it's active; this covers games started without GameMode.
  boot.kernel.sysctl."kernel.split_lock_mitigate" = 0;

  # MangoHud (FPS, frame time and temperature overlay), per-user so its
  # config lives with the user, and `steam-hud`, which starts Steam with
  # MangoHud and GameMode.
  home-manager.users.austin = {
    home.packages = [ pkgs.mangohud ];
    programs.zsh.shellAliases.steam-hud = "MANGOHUD=1 gamemoderun steam";
    xdg.configFile."MangoHud/MangoHud.conf".text = ''
      gpu_name
      fps
      frametime
      cpu_temp
      gpu_temp
      ram
      vram
      position=top-left
      font_size=20
      background_alpha=0.4
      toggle_hud=Shift_R+F12
    '';
  };

  # 32-bit Vulkan/GL for Proton comes from hardware.graphics.enable32Bit
  # (hardware.nix) and PipeWire's alsa.support32Bit (desktop.nix).

  ################################
  # Optional extras (off by default)
  ################################

  # Wired Xbox pads / the Xbox Wireless USB dongle (xpadneo above only covers
  # Bluetooth). Builds an out-of-tree module and fetches controller firmware:
  # hardware.xone.enable = true;

  # gamescope for single games, as a launch option (upscaling, a frame-rate
  # cap): `gamescope -W 1920 -H 1080 -r 144 -f -- %command%`. Runs as a
  # window in Plasma, so it doesn't have the session's GPU problem above.
  # programs.gamescope.enable = true;
}
