{ inputs, config, lib, ... }:
let
  domain = "odoo.ntd.one";
in
{
  imports = [
    # Enable Nginx with good defaults.
    inputs.srvos.nixosModules.mixins-nginx
  ];

  # Basic Odoo config.
  services.odoo = {
    enable = true;
    domain = domain;
    # install addons declaratively.
    addons = [ ];
    # add the demo database
    autoInit = true;
  };

  # Enable Let's Encrypt and HTTPS by default.
  services.nginx.virtualHosts.${domain} = {
    enableACME = true;
    forceSSL = true;
  };

  # Daily snapshots of the database.
  services.postgresqlBackup = {
    enable = true;
    databases = [ "odoo" ];
    # Let restic handle the compression so it can de-duplicate chunks.
    compression = "none";
  };

  # Backup and restore
  sops.secrets.restic_odoo_password = {};
  sops.secrets.restic_odoo_environment = {};
  services.restic.backups."odoo" = {
    initialize = true;
    paths = [
      "/var/lib/private/odoo"
      "/var/backup/postgresql"
    ];
    pruneOpts = [
      "--keep-daily 5"
      "--keep-weekly 3"
      "--keep-monthly 2"
    ];
    environmentFile = config.sops.secrets.restic_odoo_environment.path;
    passwordFile = config.sops.secrets.restic_odoo_password.path;
    # We use Cloudflare R2 for this demo, but use whatever works for you.
    repository = "s3:186a9b0a6ef4bf5c3792c9f4b4ebfbda.r2.cloudflarestorage.com/zero-to-infra-odoo";
    timerConfig.OnCalendar = "hourly";
  };
}
