# Plasma and KDE app settings via plasma-manager (flake input).
#
# Only the settings written here are managed; everything else you change in
# System Settings is left alone (programs.plasma.overrideConfig = false, the
# default). To bring more of your current desktop under the config, run
#   nix run github:nix-community/plasma-manager
# which prints your current Plasma settings as Nix, and copy the parts you
# want to keep here.
{ lib, ... }:

{
  programs.plasma.enable = true;

  # Breeze Dark: dark color scheme for apps and windows, and the dark Plasma
  # style for the panel and widgets. (Wallpapers are set in
  # modules/desktop.nix, next to the wallpaper files.)
  programs.plasma.workspace = {
    colorScheme = "BreezeDark";
    theme = "breeze-dark";
  };

  # Taskbar tweaks, made by a small Plasma script on the existing panel
  # (declaring the panel in plasma-manager would replace your whole layout):
  # - the panel sits flush with the screen edge instead of floating (Plasma
  #   6's default is a floating panel with a gap around it);
  # - pin Google Chrome (the Flatpak, see modules/desktop.nix);
  # - unpin the "default web browser" launcher (LibreWolf; still installed
  #   and in the app menu) and System Settings (still in the app menu);
  # - give the app launcher (start menu) the white NixOS snowflake, from the
  #   nixos-icons package NixOS installs on graphical systems;
  # - the taskbar clock always uses 24-hour time (the system does too; see
  #   LC_TIME in modules/base.nix), with the date in military style, day
  #   month year: "05 Oct 2026". (The widget can't upper-case the month, and
  #   British English abbreviates September as "Sept".)
  # It runs at the first login after a rebuild that changes it, so changes
  # you make by hand afterwards stay.
  programs.plasma.startup.desktopScript.taskbar.text = ''
    const pin = "applications:com.google.Chrome.desktop";
    const unpin = [
      "preferred://browser",
      "applications:systemsettings.desktop",
      "applications:org.kde.systemsettings.desktop",
    ];
    for (const panel of panels()) {
      panel.floating = false;
      for (const widget of panel.widgets()) {
        if (widget.type === "org.kde.plasma.icontasks" || widget.type === "org.kde.plasma.taskmanager") {
          widget.currentConfigGroup = ["General"];
          let launchers = widget.readConfig("launchers", []);
          if (typeof launchers === "string") {
            launchers = launchers ? launchers.split(",") : [];
          }
          launchers = launchers.filter((l) => !unpin.includes(l));
          if (!launchers.includes(pin)) {
            launchers.push(pin);
          }
          widget.writeConfig("launchers", launchers);
        } else if (widget.type === "org.kde.plasma.kickoff" || widget.type === "org.kde.plasma.kicker") {
          widget.currentConfigGroup = ["General"];
          widget.writeConfig("icon", "nix-snowflake-white");
        } else if (widget.type === "org.kde.plasma.digitalclock") {
          widget.currentConfigGroup = ["Appearance"];
          widget.writeConfig("use24hFormat", 2);
          widget.writeConfig("dateFormat", "custom");
          widget.writeConfig("customDateFormat", "dd MMM yyyy");
        }
      }
    }
  '';

  # Minimizing plays Magic Lamp, the macOS-style "genie" effect, instead of
  # Plasma's default Squash: the window bends into a funnel and pours into
  # its taskbar entry, and pours back out when restored. A KWin built-in
  # (nothing extra installed); it applies from the next login. Maximize
  # keeps KWin's default stretch animation. To go back, set "squash".
  programs.plasma.kwin.effects.minimization.animation = "magiclamp";

  # Power profile follows the charger (power-profiles-daemon, switched by
  # Plasma's power management): balanced when plugged in, power saver on
  # battery for longer battery life. For more speed while plugged in (games,
  # big builds), make AC "performance". Only these three keys are managed;
  # the rest of Energy Saving in System Settings stays yours, but a change
  # to these there is reset by the next rebuild.
  programs.plasma.powerdevil = {
    AC.powerProfile = "balanced";
    battery.powerProfile = "powerSaving";
    lowBattery.powerProfile = "powerSaving";
  };

  # plasma-manager's web-search-keywords module always writes KRunner's web
  # shortcut settings, including an empty "preferred shortcuts" list that
  # would reset your choices in System Settings. Write nothing there instead.
  programs.plasma.configFile.kuriikwsfilterrc.General = lib.mkForce { };

  # A Konsole profile using the Nerd Font, so the welcome banner, fastfetch,
  # eza and Starship icons fit the terminal grid (see bling.nix).
  programs.konsole = {
    enable = true;
    defaultProfile = "NixOS";
    profiles.NixOS = {
      name = "NixOS";
      colorScheme = "Breeze";
      font = {
        name = "JetBrainsMono Nerd Font Mono";
        size = 11;
      };
    };
  };
}
