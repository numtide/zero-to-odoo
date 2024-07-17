{ pkgs, perSystem }:
pkgs.mkShellNoCC {
  packages = [
    perSystem.sops-nix.default
    pkgs.nixos-anywhere
    pkgs.nixos-rebuild
    pkgs.age
    pkgs.pwgen
    pkgs.sops
    pkgs.ssh-to-age
  ];
}
