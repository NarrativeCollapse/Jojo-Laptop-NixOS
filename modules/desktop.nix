{ lib, pkgs, ... }:

let
  # Default wallpaper for the desktop, the lock screen and the login screen
  # (one of the images in wallpapers/).
  wallpaper = ../wallpapers/gas-masks.jpg;

  # Installed with the apps (see "Apps" below; a file can set
  # environment.systemPackages only once):
  wallpaperPackages = [
    # Extra wallpapers: the images in wallpapers/ at the repo root, where
    # Plasma's wallpaper picker lists them next to the stock ones. Add or
    # remove an image there and rebuild.
    (pkgs.runCommand "extra-wallpapers" { } ''
      install -Dm644 -t $out/share/wallpapers ${../wallpapers}/*
    '')
    # Login screen (SDDM's Breeze theme) background.
    (pkgs.writeTextDir "share/sddm/themes/breeze/theme.conf.user" ''
      [General]
      background=${wallpaper}
    '')
  ];
in
{
  ################################
  # Desktop: Plasma 6 on SDDM
  ################################

  # Wayland only: no X server and no "Plasma (X11)" session. X11 apps (and
  # Steam) still run through Xwayland, which Plasma enables itself. To bring
  # the X11 session back on 26.05, set services.xserver.enable = true and
  # remove kwin-x11 from the exclusions below. (26.11 drops the X11 session
  # and kwin-x11 altogether.)
  services.displayManager.sddm = {
    enable = true;
    wayland.enable = true;
  };

  # NOTE: defaultSession is intentionally NOT pinned. With Plasma 6 and the
  # gamescope session both registered, letting SDDM remember the last choice
  # avoids silently falling back when a session name is wrong. If you ever
  # want to force one, check the exact name first with:
  #   ls /run/current-system/sw/share/wayland-sessions/

  services.desktopManager.plasma6.enable = true;

  # Use the stock Xwayland from cache.nixos.org instead of compiling it.
  # NixOS otherwise sets Xwayland's built-in X11 font path, which changes
  # the package so that every nixpkgs update recompiles it (minutes on a
  # laptop). Only old X11 apps that use core X fonts (not fontconfig) are
  # affected, and nothing here uses them.
  programs.xwayland.defaultFontPath = "";

  # Extra wallpapers and the login screen background: `wallpaperPackages`
  # at the top of this file.
  environment.pathsToLink = [ "/share/wallpapers" ];

  # Desktop and lock screen wallpaper (plasma-manager; see
  # home/austin/plasma.nix). Applied at the first login after a rebuild that
  # changes it; one picked by hand in System Settings stays until then.
  home-manager.users.austin.programs.plasma = {
    workspace.wallpaper = wallpaper;
    kscreenlocker.appearance.wallpaper = wallpaper;
  };

  ################################
  # Audio: PipeWire
  ################################

  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    # JACK (for pro-audio apps) is off; nothing here uses it. Set
    # jack.enable = true if you add one, such as Ardour or Carla.
  };

  ################################
  # XDG portals
  ################################

  # Plasma enables the portals (and dconf); this routes xdg-open through
  # them too, so sandboxed and Flatpak apps open links in the default app.
  xdg.portal.xdgOpenUsePortal = true;

  ################################
  # Flatpak + Flathub
  ################################

  # Managed by nix-flatpak (flake input): the Flathub remote and the apps
  # listed below are installed by flatpak-managed-install.service at boot and
  # after each rebuild, retried with backoff while offline. Apps are never
  # updated automatically; `update` ([f]) does that when you choose.
  services.flatpak = {
    enable = true;
    # Flathub is the default remote. Add apps by their Flathub ID (the part
    # after /apps/ in the app's flathub.org address).
    packages = [
      "com.google.Chrome"
      "org.videolan.VLC"
      "com.github.tchx84.Flatseal" # manage Flatpak app permissions
      "org.qbittorrent.qBittorrent"
      "io.github.kolunmi.Bazaar" # Flathub app store (as on Bazzite/Bluefin)
      "org.telegram.desktop" # Telegram
      "com.rtosta.zapzap" # ZapZap: WhatsApp (an unofficial desktop client)
    ];
    # Leave apps installed by hand (Bazaar, `flatpak install`) alone. Set to
    # true once everything you want is listed above to make this list the
    # source of truth, like the Brewfile.
    uninstallUnmanaged = false;
    restartOnFailure.exponentialBackoff.enable = true;
  };

  ################################
  # Apps: added and left out
  ################################

  # Desktop apps installed as Nix packages (the Flatpaks are above; Mullvad's
  # app comes with its module in network.nix). The KDE apps are Nix packages
  # rather than Flatpaks: they use the Qt and Breeze already installed for
  # Plasma (a Flatpak would need KDE's Flatpak runtime, several hundred MB)
  # and update with the system. Add another as kdePackages.<name>.
  environment.systemPackages =
    wallpaperPackages
    ++ [ pkgs.librewolf ] # browser (Chrome is a Flatpak)
    ++ (with pkgs.kdePackages; [
      kcalc # calculator
      isoimagewriter # writes ISO images to USB sticks
      filelight # shows what fills the disk, as a clickable ring chart
    ]);

  # KDE Partition Manager: formats, labels and resizes drives (backup
  # drives, USB sticks after ISO Image Writer). Through its module rather
  # than as a package, since it also installs the D-Bus helper and polkit
  # rules it uses for admin access (asking for your password).
  programs.partition-manager.enable = true;

  # Plasma apps and services installed by default that nothing here uses.
  environment.plasma6.excludePackages =
    with pkgs.kdePackages;
    [
      elisa # music player
      khelpcenter # KDE Help Center
      krdp # remote desktop (RDP) server
      qrca # QR code scanner
      plasma-keyboard # on-screen touch keyboard (the laptop has no touchscreen)
      qtvirtualkeyboard
      # Discover, KDE's software center. Bazaar (a Flatpak, above) is the app
      # store here; Discover would be a second one, and its update notifier
      # nags about updates that `update` handles. On NixOS it can't manage
      # system packages anyway, only Flatpaks and firmware.
      discover
    ]
    # The X11 session's window manager (Wayland only; see above). Only on
    # 26.05: 26.11 removed the package, and naming it there is an error.
    ++ lib.optional (builtins.tryEval kwin-x11).success kwin-x11;

  # Plasma turns these on by default. Off here, since nothing on this
  # machine uses them:
  # - Orca screen reader and the speech-dispatcher text-to-speech service
  #   (~770 MB). Turn both back on if you need a screen reader.
  services.orca.enable = false;
  services.speechd.enable = false;
  # - The KDE PIM backend (Akonadi, ~380 MB), which only KDE's mail, contact
  #   and calendar apps (none installed) and the clock's calendar-events
  #   plugin use.
  programs.kde-pim.enable = false;

  ################################
  # Fonts
  ################################

  # Plasma adds Noto and Hack, and the NixOS defaults add DejaVu, Liberation
  # and more. Listed here: what the config relies on directly.
  fonts = {
    packages = with pkgs; [
      noto-fonts-color-emoji # color emoji everywhere
      nerd-fonts.jetbrains-mono # icons for the terminal (see bling.nix)
    ];
    # Subpixel antialiasing for the laptop's RGB LCD panel.
    fontconfig.subpixel.rgba = "rgb";
  };

  ################################
  # Printing
  ################################

  # CUPS; network printers are found through mDNS (Avahi, in network.nix).
  services.printing.enable = true;
}
