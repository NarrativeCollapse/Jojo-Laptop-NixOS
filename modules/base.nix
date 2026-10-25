{ config, lib, ... }:

{
  options.my.unfreePackages = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
    description = "Names (lib.getName) of the unfree packages allowed to build.";
  };

  config = {
    ################################
    # Nix settings
    ################################

    nix = {
      settings.experimental-features = [
        "nix-command"
        "flakes"
      ];

      # Flakes only: no `nix-channel` command or root channel state. `<nixpkgs>`
      # (nix-shell -p, nix-build '<nixpkgs>') and `nix run nixpkgs#...` both
      # resolve to the nixpkgs this system was built from (flake.lock).
      channel.enable = false;

      # Weekly store deduplication (hard-links identical files). Preferred over
      # auto-optimise-store, which does the same work during every build.
      optimise = {
        automatic = true;
        dates = [ "weekly" ];
      };

      # Disk-full protection: while Nix downloads or builds, if free space
      # drops below 5 GiB it deletes unused store paths until 10 GiB are
      # free. Only paths nothing refers to go; the system generations in
      # the boot menu are kept (they're cleaned weekly by nh, below).
      settings.min-free = 5 * 1024 * 1024 * 1024;
      settings.max-free = 10 * 1024 * 1024 * 1024;

      # Optional QoL, off by default:
      # settings.trusted-users = [ "austin" ];  # sudo-less cache/builder ops
      # settings.warn-dirty = false;            # silence "Git tree is dirty"
    };

    ################################
    # nh: rebuild helper + GC
    ################################

    # `nh os switch` rebuilds from NH_FLAKE; `nh clean` replaces nix.gc (the nh
    # module warns if both are enabled). `flake` is where the config checkout
    # lives; `update` and the `rebuild` alias read it from here too.
    programs.nh = {
      enable = true;
      flake = "/home/austin/nixos-config";
      # Two weeks (and never fewer than 5 generations) leaves room to roll back
      # an update whose breakage isn't noticed for a few days.
      clean = {
        enable = true;
        dates = "weekly";
        extraArgs = "--keep-since 14d --keep 5";
      };
    };

    ################################
    # Locale / time
    ################################

    time.timeZone = "America/Chicago";

    # US English, except times: British English gives the 24-hour clock
    # everywhere (taskbar, lock and login screens, apps, `date`). It also
    # makes short dates day/month (29/09/2026).
    i18n.defaultLocale = "en_US.UTF-8";
    i18n.extraLocaleSettings.LC_TIME = "en_GB.UTF-8";

    ################################
    # Unfree packages
    ################################

    # Only unfree packages named in my.unfreePackages may build; any other
    # fails with an "unfree license" error. Each module lists the ones it uses
    # next to the package (Steam: gaming.nix).
    nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) config.my.unfreePackages;

    ################################
    # Prebuilt Linux programs: nix-ld
    ################################

    # Programs built for ordinary Linux distributions expect the loader at
    # /lib64/ld-linux-x86-64.so.2, which NixOS doesn't have; nix-ld provides
    # it (with common libraries). Used by Homebrew's bottles (homebrew.nix)
    # and the tools Mason downloads for Neovim (home/austin/neovim.nix).
    programs.nix-ld.enable = true;

    ################################
    # Logging / misc
    ################################

    # Shutdown: wait at most 45 seconds for a service that won't stop
    # (systemd's default is 90, per service), as Fedora does. Both for
    # system services and for the services in your login session. The
    # session's setting is a drop-in file because its NixOS option changed
    # between 26.05 and 26.11 (see the journal below).
    systemd.settings.Manager.DefaultTimeoutStopSec = "45s";
    environment.etc."systemd/user.conf.d/stop-timeout.conf".text = ''
      [Manager]
      DefaultTimeoutStopSec=45s
    '';

    # Cap the journal's size. A drop-in file rather than a journald option,
    # because the option changed between NixOS 26.05 (extraConfig) and 26.11
    # (settings.Journal); systemd reads the file the same way on both.
    environment.etc."systemd/journald.conf.d/size.conf".text = ''
      [Journal]
      SystemMaxUse=500M
      RuntimeMaxUse=200M
    '';

    # The stock command-not-found needs a channel-built index that flake
    # systems don't have. nix-index-database replaces it (home/austin/bling.nix).
    programs.command-not-found.enable = false;
  };
}
