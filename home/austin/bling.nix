# Bazzite-style terminal, done the Nix way: a greeting (MOTD) on every new
# shell, a branded fastfetch, and the bazzite-cli tool set with its aliases.
# Adapted from ublue-os/bazzite (Apache-2.0), which installs the same tools
# with Homebrew (`ujust bazzite-cli`) and appends source lines to ~/.bashrc.
# Remove the import in home.nix to drop all of it.
{
  osConfig,
  lib,
  pkgs,
  ...
}:

let
  # "0.1 · generation 42 · config 1a2b3c4", shown by the MOTD and fastfetch.
  # The version comes from system.nixos.tags: it's the first part of the
  # running system's label ("0.1-26.05.20260926.5e2305d"), which NixOS keeps
  # in /run/current-system/nixos-version.
  sysinfo = pkgs.writeShellApplication {
    name = "nixos-system-info";
    text = ''
      label=$(cat /run/current-system/nixos-version 2>/dev/null || true)
      ver=''${label%%-*}
      [[ $ver =~ ^[0-9]+\.[0-9]+$ ]] || ver=""
      gen=$(readlink /nix/var/nix/profiles/system 2>/dev/null | sed -n 's/^system-\([0-9]*\)-link$/\1/p' || true)
      rev=$(nixos-version --configuration-revision 2>/dev/null || true)
      out="generation ''${gen:-?}"
      if [ -n "$ver" ]; then out="$ver · $out"; fi
      if [ -n "$rev" ]; then
        short=''${rev:0:7}
        if [[ $rev == *-dirty ]]; then short="$short-dirty"; fi
        out="$out · config $short"
      fi
      echo "$out"
    '';
  };

  tips = pkgs.writeText "motd-tips" (
    lib.concatLines [
      "Roll back a bad rebuild with `sudo nixos-rebuild switch --rollback`, or pick an older generation in the boot menu."
      "Type a command you don't have and the shell names the package that provides it; `, cowsay hi` runs it without installing."
      "Put `use flake` in a project's `.envrc` and run `direnv allow`: its dev shell loads whenever you `cd` in."
      "`nh os switch` shows which packages changed before it activates the new generation."
      "Ctrl+R searches your shell history (atuin); `z <dir>` jumps to directories you visit often (zoxide)."
      "Need software that isn't in nixpkgs? `distrobox create --image fedora:latest` gives you a Fedora container that shares your home."
      "Everything on this machine is defined in ~/nixos-config, so `git log` there is your changelog."
      "`tldr <command>` shows short, practical examples of a command."
    ]
  );

  # A small black-and-white NixOS snowflake (neofetch's "nixos_small"),
  # shown left of the heading.
  logo = pkgs.writeText "nixos-logo-small" ''
      \\  \\ //
     ==\\__\\/ //
       //   \\//
    ==//     //==
     //\\___//
    // /\\  \\==
      // \\  \\
  '';

  motdTemplate = pkgs.writeText "motd.md" ''
    | Command | Description |
    | ------- | ----------- |
    | `update` | Check for system, Flatpak, Homebrew, Neovim and firmware updates; you choose what to apply |
    | `rebuild` | Apply changes from ~/nixos-config |
    | `nix search nixpkgs <name>` | Find a package |
    | `, <command>` | Run a command without installing it |
    | `fastfetch` | View system information |
    | `toggle-motd` | Turn this banner off (or back on) |

    **Tip:** $TIP

    - **󰈙** [NixOS manual](https://nixos.org/manual/nixos/stable/)
    - **󰈙** [Package search](https://search.nixos.org/packages)
    - **󰈙** [Home Manager options](https://nix-community.github.io/home-manager/options.xhtml)
    - **** [This config](https://github.com/NarrativeCollapse/Jojo-Laptop-NixOS)
  '';

  motd = pkgs.writeShellApplication {
    name = "nixos-motd";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gettext
      pkgs.git
      pkgs.glow
      pkgs.ncurses
      sysinfo
    ];
    runtimeEnv = {
      MOTD_TIPS = "${tips}";
      MOTD_TEMPLATE = "${motdTemplate}";
      MOTD_LOGO = "${logo}";
      # The config checkout, for the "not on GitHub yet" line.
      CONFIG_FLAKE = osConfig.programs.nh.flake;
    };
    text = builtins.readFile ../../scripts/nixos-motd.sh;
  };

  # Same on/off switch file as Bazzite's `ujust toggle-user-motd`.
  toggleMotd = pkgs.writeShellApplication {
    name = "toggle-motd";
    text = ''
      flag="''${XDG_CONFIG_HOME:-$HOME/.config}/no-show-user-motd"
      if [ -e "$flag" ]; then
        rm -f "$flag"
        echo "MOTD on: it will show in new shells."
      else
        mkdir -p "$(dirname "$flag")"
        touch "$flag"
        echo "MOTD off. Run toggle-motd again to bring it back."
      fi
    '';
  };
in
{
  # The banner's commands, plus bazzite-cli.Brewfile's standalone tools.
  # (yt-dlp is the one left to Homebrew, which keeps up with it: /Brewfile.)
  home.packages = [
    motd
    toggleMotd
    sysinfo
  ]
  ++ (with pkgs; [
    glow
    ugrep
    # Search and view
    ripgrep # rg
    fd
    bat
    television # tv, fuzzy finder
    # JSON and YAML
    jq
    yq-go # yq (the Go one, as Homebrew's; nixpkgs' plain yq is another tool)
    # GitHub and GitLab
    gh
    glab
    # Disks and files
    dysk # disk usage overview
    trash-cli
    # Shell scripts and stress testing
    shellcheck
    stress-ng
  ]);

  # Share the Nix store, your Home Manager profile, and the current system
  # (read-only) with distrobox containers created from now on. Your shell
  # (/run/current-system/sw/bin/zsh) and its config (~/.zshrc points into
  # /nix/store) then work inside boxes, including the 📦 prompt badge.
  # Existing boxes need recreating to pick this up.
  xdg.configFile."distrobox/distrobox.conf".text = ''
    container_additional_volumes="/nix/store:/nix/store:ro /etc/profiles/per-user:/etc/profiles/per-user:ro /run/current-system:/run/current-system:ro"
  '';

  # `tldr`: short examples for a command. Its pages download separately and
  # refresh on their own.
  programs.tealdeer = {
    enable = true;
    settings.updates.auto_update = true;
  };

  # bling.sh's aliases that the Home Manager modules below don't provide.
  home.shellAliases = {
    grep = "ug";
    egrep = "ug -E";
    fgrep = "ug -F";
    xzgrep = "ug -z";
    xzegrep = "ug -zE";
    xzfgrep = "ug -zF";
    "l." = "eza -d .*";
    l1 = "eza -1";
    open = "xdg-open &>/dev/null";
    neofetch = "fastfetch";
  };

  programs = {
    # ls/ll/la/lt/lla -> eza, with bling.sh's flags.
    eza = {
      enable = true;
      icons = "auto";
      extraOptions = [ "--group-directories-first" ];
    };
    atuin.enable = true;
    zoxide.enable = true;
    # Not in Bazzite's default set, but the natural Nix addition: per-project
    # `nix develop` shells that load on `cd`.
    direnv = {
      enable = true;
      nix-direnv.enable = true;
    };

    # Bazzite's fish prompt shows a box inside containers; starship's
    # container module does the same (`$container` is in home.nix's format).
    # It works in distrobox because of distrobox.conf above.
    starship.settings.container.symbol = "📦";

    # Typing an unknown command suggests the package that provides it, and
    # `, <cmd>` runs a command from nixpkgs without installing it. Uses the
    # prebuilt index from nix-index-database, so nothing is indexed locally.
    nix-index.enable = true;
    nix-index-database.comma.enable = true;

    zsh.initContent = lib.mkAfter "nixos-motd";

    # Bazzite's fastfetch layout with the NixOS logo; the image line shows
    # the system generation and config revision instead.
    fastfetch = {
      enable = true;
      settings = {
        logo.source = "nixos";
        display = {
          separator = "  ";
          color.keys = "light_blue";
        };
        modules = [
          {
            type = "title";
            key = " ";
            color = {
              user = "light_blue";
              at = "white";
              host = "blue";
            };
          }
          "break"
          {
            type = "command";
            key = " 󱋩";
            text = "${sysinfo}/bin/nixos-system-info";
          }
          {
            type = "os";
            key = " ";
            format = "{pretty-name}";
          }
          {
            type = "kernel";
            key = " ";
            format = "{1} {2}";
          }
          {
            type = "uptime";
            key = " 󰅐";
          }
          "break"
          {
            type = "host";
            key = " 󰾰";
          }
          {
            type = "cpu";
            key = " 󰻠";
          }
          {
            type = "gpu";
            key = " 󰍛";
          }
          {
            type = "memory";
            key = " ";
          }
          {
            type = "disk";
            key = " ";
            hideFS = "overlay";
            # /nix/store is a read-only bind mount of /; don't list it twice.
            hideFolders = "/efi:/boot:/boot/*:/nix/store";
          }
          {
            type = "display";
            key = " 󰍹";
          }
          {
            type = "battery";
            key = " ";
          }
          {
            type = "gamepad";
            key = " 󰖺";
          }
          "break"
          {
            type = "de";
            key = " 󰕮";
          }
          {
            type = "wm";
            key = " ";
          }
          {
            type = "shell";
            key = " ";
          }
          {
            type = "terminal";
            key = " ";
          }
          {
            type = "packages";
            key = " 󰏖";
          }
          "break"
          {
            type = "colors";
            paddingLeft = 2;
            symbol = "circle";
          }
        ];
      };
    };
  };
}
