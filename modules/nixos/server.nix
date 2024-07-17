{
  inputs,
  flake,
  config,
  ...
}:
{
  imports = [
    # Used for disk partitioning.
    inputs.disko.nixosModules.default
    # Used to manage shared secrets.
    inputs.sops-nix.nixosModules.default
    # Provides sane and hardened defaults for our server. Making sure SSH is
    # up and running.
    inputs.srvos.nixosModules.server
  ];

  # Configure Let's Encrypt
  security.acme.acceptTerms = true;
  security.acme.defaults.email = "admin+acme@numtide.com";

  # Allow you to SSH to the servers as root
  users.users.root.openssh.authorizedKeys.keyFiles = [ "${flake}/users/zimbatm/authorized_keys" ];

  # Provisions hosts with pre-generated host keys
  sops.secrets.ssh_host_ed25519_key = { };
  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  services.openssh.hostKeys = [
    {
      path = config.sops.secrets.ssh_host_ed25519_key.path;
      type = "ed25519";
    }
  ];
}
