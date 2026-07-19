# Encrypted restic backups of app state directories, with an optional
# healthchecks.io heartbeat per job (ping on success, <url>/fail on failure)
# so silence raises an alert.
#
# Opt-in per host. The flake itself is never backed up (it lives in git);
# only unrecoverable runtime state goes in `paths` - add each new app's
# state directory when the app lands on the host.
#
# Usage on a host:
#
#   imports = [ outputs.nixosModules.backup ];
#
#   services.backup = {
#     enable = true;
#     repository = "b2:my-bucket:restic";
#     paths = [ "/var/lib/myapp" ];
#     # sops key whose content is the healthchecks.io ping URL; null disables
#     healthchecksUrlFile = config.sops.secrets.healthchecks-url.path;
#   };
#
# Secrets (sops keys the host must provide):
#   restic-password   password for the restic repository (generate once, e.g.
#                     `openssl rand -base64 32`; losing it = losing backups)
#   restic-env        env file with backend credentials, e.g. for B2:
#                       B2_ACCOUNT_ID=<keyID>
#                       B2_ACCOUNT_KEY=<applicationKey>
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.backup;
in
{
  options.services.backup = {
    enable = lib.mkEnableOption "restic backups of app state directories";

    repository = lib.mkOption {
      type = lib.types.str;
      description = "restic repository URL (credentials come from the restic-env secret).";
      example = "b2:my-bucket:restic";
    };

    paths = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      description = "State directories to back up.";
      example = [ "/var/lib/myapp" ];
    };

    healthchecksUrlFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "File containing the healthchecks.io ping URL (no trailing /fail), e.g. a sops secret path. null disables the heartbeat.";
    };
  };

  config = lib.mkIf cfg.enable {
    sops.secrets.restic-password = { };
    sops.secrets.restic-env = { };

    services.restic.backups.state = {
      repository = cfg.repository;
      passwordFile = config.sops.secrets.restic-password.path;
      environmentFile = config.sops.secrets.restic-env.path;
      initialize = true; # create the repo on first run

      paths = cfg.paths;

      timerConfig = {
        OnCalendar = "03:00";
        RandomizedDelaySec = "15m";
        Persistent = true; # catch up if the timer was missed (e.g. reboot)
      };

      pruneOpts = [
        "--keep-daily 7"
        "--keep-weekly 4"
        "--keep-monthly 6"
      ];

      # State is small (MBs-GBs), so verifying the whole repo after each
      # backup is cheap and replaces a separate integrity-check timer.
      runCheck = true;
    };

    # Heartbeat: ExecStartPost only runs when the service succeeds.
    systemd.services.restic-backups-state = lib.mkIf (cfg.healthchecksUrlFile != null) {
      onFailure = [ "restic-backups-state-ping-fail.service" ];
      serviceConfig.ExecStartPost = pkgs.writeShellScript "ping-healthchecks" ''
        ${lib.getExe pkgs.curl} -fsS -m 10 --retry 3 \
          "$(cat ${cfg.healthchecksUrlFile})" > /dev/null || true
      '';
    };

    systemd.services.restic-backups-state-ping-fail = lib.mkIf (cfg.healthchecksUrlFile != null) {
      description = "Signal healthchecks.io that the restic backup failed";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "ping-healthchecks-fail" ''
          ${lib.getExe pkgs.curl} -fsS -m 10 --retry 3 \
            "$(cat ${cfg.healthchecksUrlFile})/fail" > /dev/null || true
        '';
      };
    };
  };
}
