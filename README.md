# It takes 68 steps to deploy Odoo with NixOS

After spending a few years providing NixOS consulting, and building tooling
around it, it's time to take account. How hard is it to go from zero to a
deployed application running on NixOS?

The goal of this article is to serve as a benchmark for future tooling to
reduce the number of steps needed to deploy NixOS from scratch. And reduce the
Total Cost of Ownership for using bare-metal and self-hosting vs cloud and
SaaS.

For this exercise, I picked Odoo as the application, a popular CRM in the
Enterprise world.

Here we go (skip to the [conclusion](#conclusion) if you are not technical).

## Prerequisites (10 steps)

Skill level required: advanced.

I will assume you have access to a few things already and count those as
steps.

 1. A Linux machine with:
 2. [Nix](https://nixos.org/nix) installed on it.
 3. [direnv](https://direnv.net) installed on it.
 4. A SSH key generated with `ssh-keygen -t ed25519`
 5. A corresponding age key
 6. A [Hetzner](https://hetzner.com) account.
 7. A credit card.
 8. A domain (we're using `ntd.one`).
 9. A DNS provider.
10. A S3-compatible object store (we're using Cloudflare R2).

## Order server (6 steps)

Let's get a nice machine to put the service on it. Our friends at Hetzner
offer incredibly cheap bare-metal servers that are 5-10x less expensive than
AWS VMs. Price: EUR 54.7/month, plus EUR 46.41 setup fee.

1. Order <https://www.hetzner.com/dedicated-rootserver/matrix-ax/>
2. AX42 is plenty enough. <https://www.hetzner.com/dedicated-rootserver/ax42/configurator/#/>
3. Keep all the defaults with the rescue system.
4. Add your SSH public key (from `~/.ssh/id_ed25519.pub`)
5. Order.
6. In a few minutes/hours, get back an email with the host's addresses.

`! ipv4=65.21.223.114` `! ipv6=2a01:4f9:3071:295c::2`

## Repo init (3 steps)

While the server is prepared, let's create a bare repository to hold the
configuration. I will use [blueprint](https://github.com/numtide/blueprint) to
reduce the amount of glue code and save a few steps.

```console
$ mkdir -p ~/src/zero-to-odoo
$ cd ~/src/zero-to-odoo
$ nix flake init --template github:numtide/blueprint

wrote: /home/zimbatm/src/zero-to-odoo/flake.nix
```

This creates a basic skeleton that we will populate with more content.

### Add flake inputs (7 steps)

Add a few more dependencies we are going to need later.

We take some extra effort to compress the dependency tree to keep things lean.
This requires inspecting each dependency with `nix flake metadata` and then
connecting the inputs using the "follows" mechanism.

```diff

diff --git a/flake.nix b/flake.nix

index af07574..27ce2ee 100644
--- a/flake.nix
+++ b/flake.nix
@@ -6,8 +6,6 @@
     nixpkgs.url = "github:NixOS/nixpkgs?ref=nixos-unstable";
     blueprint.url = "github:numtide/blueprint";
     blueprint.inputs.nixpkgs.follows = "nixpkgs";
+    disko.url = "github:nix-community/disko";
+    disko.inputs.nixpkgs.follows = "nixpkgs";
+    sops-nix.url = "github:mic92/sops-nix";
+    sops-nix.inputs.nixpkgs.follows = "nixpkgs";
+    sops-nix.inputs.nixpkgs-stable.follows = "";
+    srvos.url = "github:nix-community/srvos";
+    srvos.inputs.nixpkgs.follows = "nixpkgs";
   };
```

### Add devshell with a couple of tools (2 steps)

Create a shell environment with all the tools we're going to need.

> In reality, I had to come back a few times to add missing dependencies.

Add: [$ devshell.nix](devshell.nix) as nix

```nix
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
```

```console
$ git add devshell.nix
```

### Configure direnv (2 steps)

Configure direnv to automatically load the tools into the environment when
entering the project folder.

Add: [$ .envrc](.envrc) as shell

```shell
#!/usr/bin/env bash

watch_file devshell.nix

use flake
```

```console
direnv: error /home/zimbatm/src/zero-to-odoo/.envrc is blocked. Run `direnv allow` to approve its content

$ direnv allow

direnv: loading ~/src/zero-to-odoo/.envrc

direnv: using flake

warning: Git tree '/home/zimbatm/src/zero-to-odoo' is dirty

direnv: export +AR +AS +CC +CONFIG_SHELL +CXX +HOST_PATH +IN_NIX_SHELL +LD +NIX_BINTOOLS +NIX_BINTOOLS_WRAPPER_TARGET_HOST_x86_64_unknown_linux_gnu +NIX_BUILD_CORES +NIX_BUILD_TOP +NIX_CC +NIX_CC_WRAPPER_TARGET_HOST_x86_64_unknown_linux_gnu +NIX_CFLAGS_COMPILE +NIX_ENFORCE_NO_NATIVE +NIX_HARDENING_ENABLE +NIX_LDFLAGS +NIX_STORE +NM +OBJCOPY +OBJDUMP +RANLIB +READELF +SIZE +SOURCE_DATE_EPOCH +STRINGS +STRIP +TEMP +TEMPDIR +TMP +TMPDIR +__structuredAttrs +buildInputs +buildPhase +builder +cmakeFlags +configureFlags +depsBuildBuild +depsBuildBuildPropagated +depsBuildTarget +depsBuildTargetPropagated +depsHostHost +depsHostHostPropagated +depsTargetTarget +depsTargetTargetPropagated +doCheck +doInstallCheck +dontAddDisableDepTrack +mesonFlags +name +nativeBuildInputs +out +outputs +patches +phases +preferLocalBuild +propagatedBuildInputs +propagatedNativeBuildInputs +shell +shellHook +stdenv +strictDeps +system ~PATH ~XDG_DATA_DIRS
```

### Prepare your user (5 steps)

We are going to generate an AGE key from our SSH private key.

> NOTE: the age key is stored decrypted at rest. This is a limitation of age.

```console
$ mkdir -p ~/.config/sops/age
$ ssh-to-age -private-key -i ~/.ssh/id_ed25519 >> ~/.config/sops/age/keys.txt
```

Then, add our user information to the repo, making place for potentially more
users in the future.

`! USER=zimbatm`

```console
$ mkdir -p users/$USER
$ cat ~/.ssh/id_ed25519.pub > users/$USER/authorized_keys
$ git add users
```

### Prepare some shared configuration (3 steps)

Create a NixOS module with some basic configuration we can share will all the
potential future servers.

> In reality, I had to come back a few times.

```console
$ mkdir -p modules/nixos
```

Add: `> modules/nixos/server.nix`

```nix
{ inputs, flake, ... }:
{
  imports = [
    inputs.disko.nixosModules.default
    inputs.sops-nix.nixosModules.default
    inputs.srvos.nixosModules.server
  ];
  
  # Allow you to SSH to the servers as root
  users.users.root.openssh.authorizedKeys.keyFiles = [
    "${flake}/users/zimbatm/authorized_keys"
  ];
}
```

```console
$ git add modules
```

## Host bootstrap

Ok, the base skeleton is in place. Next, configure and deploy a naked
configuration to the host.

### Bind DNS entry (2 steps)

Use your DNS provider to bind the IPv4 and IPv6 to it.

* `odoo.$domain.		300	IN	A	$ipv4`
* `odoo.$domain.		300	IN	AAAA	$ipv6`

### Prepare the host configuration (5 steps)

Our machine is going to be called "odoo1" (this is my weird naming scheme).

```console
$ mkdir -p hosts/odoo1
```

We are going to use [disko](https://github.com/nix-community/disko) to
partition the machine declaratively. This saves 5-10 steps from the original
NixOS installation manual.

Getting this configuration right usually takes a few iterations, but we are
lucky, I had a ZFS config from another machine.

Add: `> hosts/odoo1/disko.nix` as nix

```nix
{ ... }:
let
  mirrorBoot = idx: {
    type = "disk";
    device = "/dev/nvme${idx}n1";
    content = {
      type = "gpt";
      partitions = {
        ESP = {
          size = "512M";
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot${idx}";
          };
        };
        zfs = {
          size = "100%";
          content = {
            type = "zfs";
            pool = "zroot";
          };
        };
      };
    };
  };
in
{
  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    efiInstallAsRemovable = true;
    mirroredBoots = [
      {
        path = "/boot0";
        devices = [ "nodev" ];
      }
      {
        path = "/boot1";
        devices = [ "nodev" ];
      }
    ];
  };

  disko.devices = {
    disk = {
      x = mirrorBoot "0";
      y = mirrorBoot "1";
    };

    zpool = {
      zroot = {
        type = "zpool";
        rootFsOptions = {
          compression = "lz4";
          "com.sun:auto-snapshot" = "true";
        };
        datasets = {
          "root" = {
            type = "zfs_fs";
            options.mountpoint = "none";
            mountpoint = null;
          };
          "root/nixos" = {
            type = "zfs_fs";
            options.mountpoint = "/";
            mountpoint = "/";
          };
        };
      };
    };
  };
}
```

Next, add the main NixOS configuration. We already have the Hetzner hardware
configuration in [SrvOS](https://github.com/nix-community/srvos), which saves
us a few steps here.

> This led Mic92 and I to re-think why the hostId is needed. It won't be
> necessary once <https://github.com/nix-community/srvos/pull/465> is merged.

[$ hosts/odoo1/configuration.nix](hosts/odoo1/configuration.nix) as nix

```nix
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
```

```console
# Add some blank odoo config for now.
$ echo '{}' > hosts/odoo1/odoo.nix
$ git add hosts/odoo1
```

Now, we have almost everything needed to deploy a blank machine.

### Bootstrap SOPS (6 steps)

We lean on SOPS and sops-nix to share secrets between the deployer (me) and
the machine. The nice thing about this approach is that it doesn't require
extra infrastructure like Vault to store the secrets while still keeping them
encrypted at rest.

We generate the target machine SSH host key so we know what its public
certificate is going to be in advance.

```console
# Generate a SSH key for the host
$ ssh-keygen -t ed25519 -N "" -f hosts/odoo1/ssh_host_ed25519_key
# Configure sops
$ cat <<SOPS > .sops.yaml

creation_rules:
  - path_regex: ^hosts/odoo1/secrets.yaml$
    key_groups:
      - age:
        - $(ssh-to-age -i hosts/odoo1/ssh_host_ed25519_key.pub)
        - $(ssh-to-age -i users/$USER/authorized_keys)
SOPS
# Generate the host secret file

cat <<SECRETS > hosts/odoo1/secrets.yaml

ssh_host_ed25519_key: |
$(sed "s/^/  /" < hosts/odoo1/ssh_host_ed25519_key)
SECRETS
# Now encrypt the file
$ sops --encrypt --in-place hosts/odoo1/secrets.yaml
# Remove the unencrypted private host key
$ rm hosts/odoo1/ssh_host_ed25519_key
# Add things to git for flakes
$ git add hosts/odoo1
```

### Bootstrap the host (8 steps)

It's time to deploy the host.

We use [nixos-anywhere](https://github.com/nix-community/nixos-anywhere) to
live-replace the target machine with our desired disk partitioning and NixOS
configuration. This saves us a lot of steps as we don't have to faff around
with ISOs, or figuring how the host provider handles IPXE or other system
images. If the host provider supports Ubuntu, Debian or Fedora, we just
replace it.

```console
# Prepare the SSH host key to upload
$ temp=$(mktemp -d)
$ install -d -m755 "$temp/etc/ssh"
$ sops --decrypt --extract '["ssh_host_ed25519_key"]' hosts/odoo1/secrets.yaml > "$temp/etc/ssh/ssh_host_ed25519_key"
$ chmod 600 "$temp/etc/ssh/ssh_host_ed25519_key"

# Deploy!
$ nixos-anywhere --extra-files "$temp" --flake .#odoo1 root@odoo.ntd.one
<snip>
copying path '/nix/store/zqwbhdf7ljq6rh6rbb7qn078k4srcsva-linux-6.6.39-modules' from 'https://cache.nixos.org'...
copying path '/nix/store/kk8vvdihcbpw7gl5kdiddx19rdhak07q-firmware' from 'https://cache.nixos.org'...
copying path '/nix/store/8cjsjjf11pw52632q25zprjwz8r8bvaj-etc-modprobe.d-firmware.conf' from 'https://cache.nixos.org'...
### Installing NixOS ###
Pseudo-terminal will not be allocated because stdin is not a terminal.
installing the boot loader...
setting up /etc...
updating GRUB 2 menu...
installing the GRUB 2 boot loader into /boot0...
Installing for x86_64-efi platform.
Installation finished. No error reported.
updating GRUB 2 menu...
installing the GRUB 2 boot loader into /boot1...
Installing for x86_64-efi platform.
Installation finished. No error reported.
installation finished!
umount: /mnt/boot1 unmounted

umount: /mnt/boot0 unmounted

umount: /mnt (zroot/root/nixos) unmounted
### Waiting for the machine to become reachable again ###
Warning: Permanently added '65.21.223.114' (ED25519) to the list of known hosts.
### Done! ###

# Cleanup
$ rm -rf "$temp"
```

The machine should now be a blank machine with just SSH up and running. Let's
test this!

```console
# Add the host to our list of known hosts
$ echo "odoo.$domain $(< hosts/odoo1/ssh_host_ed25519_key.pub)" >> ~/.ssh/known_hosts
$ ssh root@65.21.223.114

Last login: Mon Jul 15 09:49:34 2024 from 178.196.175.78

[root@odoo1:~]# 
```

Ok, that works!

## Deploy Odoo

Now that the machine is up and running, let's deploy Odoo on it.

The general approach to configuring a NixOS service is to:

1. [Search the NixOS configuration](https://search.nixos.org/options?channel=24.05&from=0&size=50&sort=relevance&type=packages&query=odoo)
2. [Search Github](https://github.com/search?q=language%3ANix+odoo&type=code)

(1) lets you know if NixOS includes that service and all related options. And (2) shows you how other users are doing it.

> While writing this article I found that Odoo wasn't very well supported in nixpkgs. The rest of the article depends on those PRs being available in nixos-unstable. Always be upstreaming. <https://github.com/NixOS/nixpkgs/pull/327641> <https://github.com/NixOS/nixpkgs/pull/327729>

### NixOS modules (5 step)

Add the following to: [$ hosts/odoo1/odoo.nix](hosts/odoo1/odoo.nix) as nix

```nix
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
```

Add the secrets:

```console
$ sops --set '["restic_odoo_password"] "'$(pwgen 32 1)'"' hosts/odoo1/secrets.yaml
# Provided by Cloudflare R2
$ cat <<ENV_FILE > env_file
AWS_ACCESS_KEY_ID=e45ae998fe51bd166399c46bbe8be2e5
AWS_SECRET_ACCESS_KEY=6dddd70cbc95a81a73223e742d6d575c1bb11ef0f16fb86db838bdc58422399b
ENV_FILE
$ sops --set '["restic_odoo_environment'] '"$(jq -Rs . < env_file)" hosts/odoo1/secrets.yaml
$ rm env_file
```

This is the bare minimum.

We raise the bar from 99% of blog posts out there by including backup to the
bare minimum.

### Deploy changes (4 step)

```console
$ nixos-rebuild --flake .#odoo1 --target-host root@odoo.ntd.one switch
<snip>
```

The former blank machine now has Odoo running with some demo data, Nginx in
front with HTTPS, Postgres. <https://odoo.ntd.one> (default credentials are
admin/admin).

To test that backups are working, trigger them manually:

```console
$ ssh root@odoo.ntd.one

[root@odoo1:~]# systemctl start postgresqlBackup-odoo.service

[root@odoo1:~]# ls /var/backup/postgresql/
odoo.sql

[root@odoo1:~]# systemctl start restic-backups-odoo.service

[root@odoo1:~]# journalctl -u restic-backups-odoo.service --no-pager
<snip>
Jul 17 12:57:07 odoo1 restic[11533]: no parent snapshot found, will read all files

Jul 17 12:57:09 odoo1 restic[11533]: Files:        1135 new,     0 changed,     0 unmodified

Jul 17 12:57:09 odoo1 restic[11533]: Dirs:          489 new,     0 changed,     0 unmodified

Jul 17 12:57:09 odoo1 restic[11533]: Added to the repository: 53.299 MiB (12.709 MiB stored)
Jul 17 12:57:09 odoo1 restic[11533]: processed 1135 files, 65.890 MiB in 0:02

Jul 17 12:57:09 odoo1 restic[11533]: snapshot 6c40eb6f saved

Jul 17 12:57:12 odoo1 restic[11568]: Applying Policy: keep 5 daily, 3 weekly, 2 monthly snapshots

Jul 17 12:57:12 odoo1 restic[11568]: keep 1 snapshots:
Jul 17 12:57:12 odoo1 restic[11568]: ID        Time                 Host        Tags        Reasons           Paths

Jul 17 12:57:12 odoo1 restic[11568]: -----------------------------------------------------------------------------------------------
Jul 17 12:57:12 odoo1 restic[11568]: 6c40eb6f  2024-07-17 12:57:05  odoo1                   daily snapshot    /var/backup/postgresql

Jul 17 12:57:12 odoo1 restic[11568]:                                                        weekly snapshot   /var/lib/private/odoo

Jul 17 12:57:12 odoo1 restic[11568]:                                                        monthly snapshot

Jul 17 12:57:12 odoo1 restic[11568]: -----------------------------------------------------------------------------------------------
Jul 17 12:57:12 odoo1 restic[11568]: 1 snapshots

Jul 17 12:57:12 odoo1 systemd[1]: restic-backups-odoo.service: Deactivated successfully.
Jul 17 12:57:12 odoo1 systemd[1]: Finished restic-backups-odoo.service.
Jul 17 12:57:12 odoo1 systemd[1]: restic-backups-odoo.service: Consumed 4.860s CPU time, received 62.3K IP traffic, sent 12.8M IP traffic.
```

## Conclusion

One of the best feelings with NixOS is how few moving pieces there are. I know
this service will run for the next year with minimal intervention. If anything
breaks, I can rollback to a previous deployment. Or order another machine and
restore from backups. And there is zero vendor lock-in; I can replace all the
providers with an alternative.

To get there, 68 steps is still relatively substantial. It took me around a
day and a half to get everything up and running, including a few side quests
and taking those notes. For a novice, it would probably take a lot more trial
and errors. In particular:

* Getting the disk layout right (it takes a lot of reboots).
* Figuring out the proper project structure and how to glue everything together.
* SOPS secret bootstrapping.

A production environment would also include other aspects which I didn't have
time to cover in this article:

* Automated dependency updates.
* Monitoring.
* CI and binary cache.
* GitOps.
* Developer shell for Odoo addon development.

There is an opportunity to compress the number of steps needed, and I am
interested in making this happen one way or another. If you are working in
this area, ping me.

I hope you saw some interesting things in this article.

See you!
