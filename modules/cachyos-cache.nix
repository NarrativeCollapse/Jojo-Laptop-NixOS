# The binary cache with the prebuilt CachyOS kernels (modules/kernel.nix),
# run by the nix-cachyos-kernel flake's author. Also used by the installer
# ISO, so installing jojo downloads the kernel instead of compiling it.
#
# Only this address and key are trusted. The cache moved here on
# 2026-10-24 after the author's servers were broken into (2026-10-15); the
# old address (attic.xuyh0120.win) and its key, which the flake's own
# settings may still name, are deliberately not trusted, and the flake's
# settings aren't applied (Nix asks before using a flake's nixConfig, and
# the system doesn't use it). If the cache is down, Nix would compile the
# kernel instead, about an hour on the laptop: `update` and the installer
# check first.
#
# The same address and key are in .github/actions/setup-nix/action.yml.
{ lib, ... }:

let
  cache = "https://cache.lantian.pub/lantian";
in
{
  options.my.kernelCache = lib.mkOption {
    type = lib.types.str;
    default = cache;
    readOnly = true;
    description = "The CachyOS kernel's binary cache, for the scripts that check it's reachable.";
  };

  config.nix.settings = {
    # After cache.nixos.org, so everything else still comes from NixOS's own
    # cache and this one is only asked for what that doesn't have.
    substituters = lib.mkOrder 1600 [ cache ];
    trusted-public-keys = [ "lantian:WVGO7vsRMSEN+h7Lp7kv6SAmrkEXgUGbbXm7jMDjBuQ=" ];
  };
}
