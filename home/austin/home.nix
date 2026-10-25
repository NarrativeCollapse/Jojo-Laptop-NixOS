{
  config,
  osConfig,
  lib,
  ...
}:

{
  imports = [
    ./bling.nix # Bazzite-style MOTD, fastfetch, and CLI tools (eza, atuin, zoxide, ...)
    ./plasma.nix # Plasma and Konsole settings (plasma-manager)
    ./neovim.nix # Neovim with LazyVim
  ];

  home.username = "austin";
  home.homeDirectory = "/home/austin";

  # Must match the release you first installed with (NOT the current release).
  # Kept in sync with system.stateVersion in hosts/jojo/configuration.nix
  # (both 26.05). If you change one, change the other.
  home.stateVersion = "26.05";

  xdg.enable = true;

  ###############################
  # Zsh + Starship integration
  ###############################

  programs.zsh = {
    enable = true;
    # Keep .zshrc and .zsh_history in ~ rather than moving to ~/.config/zsh.
    dotDir = config.home.homeDirectory;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;

    # `history` is managed declaratively rather than via raw initContent.
    history = {
      size = 10000;
      save = 10000;
      ignoreDups = true;
      ignoreSpace = true;
      extended = true;
    };

    # ls/ll/la come from programs.eza in bling.nix; steam-hud from
    # modules/gaming.nix.
    shellAliases = {
      # Rebuild from the config checkout (nh's flake path, modules/base.nix).
      # `nh os switch` does the same with a package diff.
      rebuild = "sudo nixos-rebuild switch --flake ${osConfig.programs.nh.flake}#${osConfig.networking.hostName}";
    };
  };

  programs.starship = {
    enable = true;

    settings = {
      add_newline = false;
      command_timeout = 1000;

      format = lib.concatStrings [
        "$container"
        "$directory"
        "$git_branch"
        "$git_status"
        "$nix_shell"
        "$cmd_duration"
        "$line_break"
        "$character"
      ];

      directory = {
        truncation_length = 3;
        truncate_to_repo = true;
      };

      nix_shell = {
        symbol = " ";
        format = "[$symbol$state]($style) ";
      };
    };
  };

  ###############################
  # Git
  ###############################

  programs.git = {
    enable = true;
    settings = {
      # GitHub no-reply address: links commits to the NarrativeCollapse
      # account without publishing a personal email.
      user.name = "Austin";
      user.email = "333098847+NarrativeCollapse@users.noreply.github.com";
      init.defaultBranch = "main";
      pull.rebase = true;
      push.autoSetupRemote = true;
    };
  };

  # Command-line tools are in bling.nix (standalone tools like jq, gh and
  # ripgrep) and neovim.nix; MangoHud is in modules/gaming.nix, with Steam.
  # For a process monitor, Plasma's System Monitor (Ctrl+Esc for its process
  # list) is built in. (PAGER is less, NixOS's default.)
}
