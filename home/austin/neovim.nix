# Neovim with LazyVim (https://www.lazyvim.org).
#
# Nix provides Neovim and the tools LazyVim expects; LazyVim itself and its
# plugins are managed by lazy.nvim, as LazyVim is designed to be. The config
# is home/austin/nvim/ in ~/nixos-config, which ~/.config/nvim points to
# directly (not a copy in the Nix store), so:
# - edits there, and :LazyExtras choices (lazyvim.json), apply on the next
#   Neovim start, without a rebuild;
# - plugin versions are pinned in lazy-lock.json there, so git tracks them.
#   `update` ([n]) moves them on; `git checkout` of the file and :Lazy
#   restore go back.
# The first start downloads the plugins and compiles the treesitter
# parsers, so it needs the internet and takes a minute.
{
  config,
  osConfig,
  pkgs,
  ...
}:

{
  programs.neovim = {
    enable = true;
    # Sets EDITOR and VISUAL to nvim.
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;
    # No Ruby or Python plugins are used; skip their providers.
    withRuby = false;
    withPython3 = false;
    # Home Manager would otherwise write its own small init.lua (the
    # provider settings above) into ~/.config/nvim, which is LazyVim's.
    # This loads it from the command line instead.
    sideloadInitLua = true;

    # On Neovim's PATH only (not the shell's):
    extraPackages = with pkgs; [
      # Treesitter: LazyVim compiles its parsers with these.
      gcc
      tree-sitter
      # Pickers, search and git UI (:checkhealth lazyvim asks for them).
      ripgrep
      fd
      fzf
      lazygit
      # Mason unpacks some tools from zip files. (Mason's prebuilt tools,
      # such as the Lua language server, run through nix-ld; base.nix.)
      unzip
      # The Nix language extra's tools, from Nix rather than Mason
      # (see nvim/lua/plugins/nix.lua): language server, formatter, linter.
      nil
      nixfmt
      statix
      # Clipboard on Wayland (LazyVim uses the system clipboard).
      wl-clipboard
    ];
  };

  # ~/.config/nvim -> ~/nixos-config/home/austin/nvim (see the top).
  xdg.configFile."nvim".source =
    config.lib.file.mkOutOfStoreSymlink "${osConfig.programs.nh.flake}/home/austin/nvim";
}
