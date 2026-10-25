{ pkgs, ... }:

{
  ################################
  # Users & shell
  ################################

  users.users.austin = {
    isNormalUser = true;
    description = "Austin";
    # No "audio"/"video" groups: logind already grants the logged-in user
    # access to sound and GPU devices, and "audio" would let apps open sound
    # devices directly, around PipeWire. (No "podman" group either; rootless
    # podman doesn't use one.)
    extraGroups = [
      "wheel"
      "networkmanager"
    ];
    shell = pkgs.zsh;
  };

  # sudo is sudo-rs: a memory-safe Rust rewrite of sudo, the default in
  # Ubuntu 26.04 LTS. The command is still `sudo`, and every script here
  # uses it the plain way (`sudo <command>`), which it fully supports. It
  # also provides `su`. Differences you might notice: typing the password
  # shows `*` per key (`Defaults !pwfeedback` turns that off), and
  # `sudo -E` isn't supported (nothing here uses it). To go back to the
  # original sudo, delete this block.
  security.sudo-rs = {
    enable = true;
    # Remember the password for 15 minutes (sudo-rs's default too; set
    # here so it's visible).
    extraConfig = ''
      Defaults timestamp_timeout=15
    '';
  };

  ################################
  # Containers: Podman
  ################################

  virtualisation.podman = {
    enable = true;
    dockerCompat = true;
    defaultNetwork.settings.dns_enabled = true;
  };

  ################################
  # System packages (command line)
  ################################

  # Kept lean: only what's genuinely system-wide. Desktop apps are in
  # desktop.nix (except BoxBuddy, which belongs with distrobox), per-user
  # tools and editor config in Home Manager (home/austin/), yt-dlp in the
  # Brewfile, and apps that come with a module (podman, mullvad) aren't
  # repeated here.
  environment.systemPackages = with pkgs; [
    # Containers
    podman-compose
    distrobox
    # BoxBuddy: a window for distrobox (create, open, upgrade and remove
    # boxes; install .deb/.rpm files; add a box's apps to the app menu). A
    # Nix package rather than the Flatpak, whose sandbox hides some of its
    # features, since all it does is drive distrobox and podman here.
    boxbuddy

    # git system-wide so root can rebuild from the flake. (curl, coreutils
    # and the like come with NixOS itself.) Other command-line tools are in
    # Home Manager (and yt-dlp in the Brewfile).
    git
  ];

  ################################
  # System shell: zsh
  ################################

  # Needed so pkgs.zsh is a valid login shell for austin. The interactive
  # configuration (aliases, prompt, plugins) is in Home Manager. root keeps
  # the default bash, which has no Home Manager config to miss and is the
  # safer shell for recovery.
  programs.zsh.enable = true;
}
