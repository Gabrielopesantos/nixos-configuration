# Secrets via sops-nix. This is a SCAFFOLD - inert until bootstrapped.
#
# Bootstrap (after casper's first boot, when /etc/ssh host keys exist):
#   1. Derive casper's host age key from its SSH host key:
#        nix run nixpkgs#ssh-to-age -- < /etc/ssh/ssh_host_ed25519_key.pub
#      Put it as the `casper` recipient in ../.sops.yaml.
#   2. Your PERSONAL identity is the YubiKey GPG key (hardware-backed). Confirm
#      the card and grab the key fingerprint:
#        gpg --card-status      # checks the YubiKey is seen
#        gpg -K --with-colons   # find the fpr line for your key
#      Put that fingerprint as the `pgp` recipient (gabriel) in ../.sops.yaml.
#      gpg-agent must be running when you later edit secrets with `sops`.
#   3. Create the encrypted store:  sops secrets/secrets.yaml
#      e.g. `gabriel-password:` = output of `mkpasswd -m yescrypt`.
#   4. Uncomment defaultSopsFile below and set validateSopsFiles = true.
#   5. Declare the secret + switch the user to hashedPasswordFile (common.nix).
{ inputs, ... }:
{
  imports = [ inputs.sops-nix.nixosModules.sops ];

  # Decrypt on-host using the machine's SSH host key as an age identity.
  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

  # No encrypted store committed yet -> skip build-time validation. Set back to
  # true (the default) once secrets/secrets.yaml exists and is wired below.
  sops.validateSopsFiles = false;

  # Enable once secrets/secrets.yaml exists:
  # sops.defaultSopsFile = ../secrets/secrets.yaml;
  #
  # sops.secrets.gabriel-password = {
  #   neededForUsers = true; # decrypted early enough to set a login password
  # };
}
