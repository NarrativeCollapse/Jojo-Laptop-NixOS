-- The Nix language extra (imported in lua/config/lazy.lua) on NixOS: its
-- tools come from the Nix config (home/austin/neovim.nix), not Mason. Mason
-- can't build nil (it needs a Rust toolchain), and the Nix ones match the
-- versions CI uses to check this repo.
return {
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        nil_ls = { mason = false },
      },
    },
  },
}
