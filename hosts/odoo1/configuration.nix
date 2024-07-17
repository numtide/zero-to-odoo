{ inputs, flake, ... }:
{
  imports = [
    ./disko.nix
    ./odoo.nix
    flake.nixosModules.server
    # The Hetzner hardware config is handled by SrvOS
    inputs.srvos.nixosModules.hardware-hetzner-online-amd
  ];

  # The machine architecture.
  nixpkgs.hostPlatform = "x86_64-linux";

  # The machine hostname.
  networking.hostName = "odoo1";

  # Needed by ZFS. `head -c4 /dev/urandom | od -A none -t x4`
  networking.hostId = "ceb8cad3";

  # Needed because Hetzner Online doesn't provide RA. Replace the IPv6 with your own.
  systemd.network.networks."10-uplink".networkConfig.Address = "2a01:4f9:3071:295c::2";

  # Load secrets from this file.
  sops.defaultSopsFile = ./secrets.yaml;

  # Used by NixOS to handle state changes.
  system.stateVersion = "24.05";
}
