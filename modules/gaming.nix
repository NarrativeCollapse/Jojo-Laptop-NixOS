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
    # public Wi-Fi included. Off: Steam, its gamescope session and online
    # play only connect outward and don't need them. Set to true to stream
    # to a TV or another PC on your network.
    remotePlay.openFirewall = false;
    # dedicatedServer.openFirewall (27015) is deliberately off: it is only
    # for hosting Source dedicated servers.
    gamescopeSession.enable = true;
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

  programs.gamemode.enable = true;

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

  # Lets gamescope renice itself for smoother frame pacing. Known to break
  # gamescope launches inside Steam's FHS env for some setups — test before
  # keeping:
  # programs.gamescope.capSysNice = true;
}
