# Secrets via sops-nix. Recipients live in ../.sops.yaml; edit the store with
# `sops secrets/secrets.yaml` (YubiKey inserted, gpg-agent running).
#
# Adding a machine: derive its age key from the host SSH key
#   nix run nixpkgs#ssh-to-age -- < /etc/ssh/ssh_host_ed25519_key.pub
# add it to ../.sops.yaml, then `sops updatekeys secrets/secrets.yaml`.
{ inputs, ... }:
{
  imports = [ inputs.sops-nix.nixosModules.sops ];

  # Decrypt on-host using the machine's SSH host key as an age identity.
  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

  sops.defaultSopsFile = ../secrets/secrets.yaml;

  # Reusable auth key from the Tailscale admin console, for unattended
  # enrollment of new machines (picked up automatically by
  # profiles/tailscale.nix).
  sops.secrets.tailscale-auth-key = { };

  # Future: login password via secret instead of initialPassword (common.nix).
  # sops.secrets.gabriel-password = {
  #   neededForUsers = true; # decrypted early enough to set a login password
  # };
}
