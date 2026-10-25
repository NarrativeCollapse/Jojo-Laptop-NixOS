-- LazyVim (https://www.lazyvim.org), set up as in its starter
-- (github.com/LazyVim/starter). Differences, both for this config's rule
-- that nothing updates by itself:
-- - No background update checks: plugins change only through `update`
--   ([n]) or :Lazy in Neovim.
-- - Plugin versions are pinned in lazy-lock.json, next to this file in
--   ~/nixos-config, so git tracks them and can roll them back.
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  local lazyrepo = "https://github.com/folke/lazy.nvim.git"
  local out = vim.fn.system({ "git", "clone", "--filter=blob:none", "--branch=stable", lazyrepo, lazypath })
  if vim.v.shell_error ~= 0 then
    vim.api.nvim_echo({
      { "Failed to clone lazy.nvim:\n", "ErrorMsg" },
      { out, "WarningMsg" },
      { "\nPress any key to exit..." },
    }, true, {})
    vim.fn.getchar()
    os.exit(1)
  end
end
vim.opt.rtp:prepend(lazypath)

require("lazy").setup({
  spec = {
    -- add LazyVim and import its plugins
    { "LazyVim/LazyVim", import = "lazyvim.plugins" },
    -- LazyVim extras (more with :LazyExtras, which records them in lazyvim.json)
    { import = "lazyvim.plugins.extras.lang.nix" },
    -- import/override with your plugins
    { import = "plugins" },
  },
  defaults = {
    -- By default, only LazyVim plugins will be lazy-loaded. Your custom plugins will load during startup.
    lazy = false,
    -- Latest git commits, as the starter recommends; lazy-lock.json pins them.
    version = false,
  },
  install = { colorscheme = { "tokyonight", "habamax" } },
  -- No periodic update checks (see the top of this file).
  checker = { enabled = false },
  performance = {
    rtp = {
      -- disable some rtp plugins
      disabled_plugins = {
        "gzip",
        "tarPlugin",
        "tohtml",
        "tutor",
        "zipPlugin",
      },
    },
  },
})
