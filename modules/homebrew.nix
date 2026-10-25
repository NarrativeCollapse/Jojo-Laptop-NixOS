{ lib, pkgs, ... }:

let
  prefix = "/home/linuxbrew/.linuxbrew";
  brewfile = ../Brewfile;
in
{
  ################################
  # Homebrew: the escape hatch for tools that outpace NixOS (yt-dlp)
  ################################

  # The formulas are listed in /Brewfile (just yt-dlp); everything else stays
  # in Nix. See "Homebrew" in README.md for the rule.

  # Homebrew's Linux bottles and its bundled Ruby are ordinary prebuilt
  # binaries; nix-ld (base.nix) lets them run.

  # Homebrew's default Linux prefix, owned by the user so brew never needs
  # sudo.
  systemd.tmpfiles.rules = [ "d /home/linuxbrew 0755 austin users -" ];

  # Appended, not prepended: if a brew dependency shares a name with a Nix
  # tool (python3, git, curl, ...), the Nix one keeps winning.
  environment.extraInit = ''
    export PATH="$PATH:${prefix}/bin:${prefix}/sbin"
  '';
  # Tab completion for brew and its formulas (yt-dlp): add brew's
  # zsh completion directory before Home Manager's zsh runs compinit.
  home-manager.users.austin.programs.zsh.initContent = lib.mkOrder 550 ''
    fpath+=(${prefix}/share/zsh/site-functions)
  '';

  environment.variables = {
    HOMEBREW_PREFIX = prefix;
    HOMEBREW_CELLAR = "${prefix}/Cellar";
    HOMEBREW_REPOSITORY = "${prefix}/Homebrew";
    HOMEBREW_NO_ANALYTICS = "1";
    HOMEBREW_NO_ENV_HINTS = "1";
  };

  # `brew-update` (also [b] in the `update` menu): installs Homebrew the first
  # time, then shows how the installed formulas differ from /Brewfile
  # (missing, outdated, or not listed) and applies that only if you say yes.
  # Nothing runs on a timer; tools change only when you run it.
  environment.systemPackages = [
    (pkgs.writeShellApplication {
      name = "brew-update";
      runtimeInputs = with pkgs; [
        bash
        coreutils
        curl
        file
        findutils
        gawk
        git
        glibc.bin # ldd, which brew uses to read the glibc version
        gnugrep
        gnused
        gnutar
        gzip
        procps
        which
        xz
      ];
      runtimeEnv = {
        BREW_PREFIX = prefix;
        BREWFILE = "${brewfile}";
      };
      text = builtins.readFile ../scripts/lib/confirm.sh + builtins.readFile ../scripts/brew-update.sh;
    })
  ];
}
