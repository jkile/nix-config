# Secrets setup (sops-nix)

Secrets are encrypted with [sops](https://github.com/getsops/sops) using
[age](https://github.com/FiloSottile/age) recipients and committed to this repo
in `./secrets/`. Each machine decrypts them at activation using an age key
derived from its SSH host key (`/etc/ssh/ssh_host_ed25519_key`). Wiring lives in
`configuration.nix` (`sops` block), the recipient policy in `.sops.yaml`.

## First-time setup (this machine)

Run these once, in order. They produce key material that must NOT be reformatted
or committed in plaintext. This flow needs only ONE rebuild.

> The `sops`, `age`, and `ssh-to-age` CLIs are declared in `home.nix`, but that
> only installs them *after* the first rebuild. For the bootstrap commands below,
> prefix them with a throwaway shell:
> `nix shell nixpkgs#sops nixpkgs#age nixpkgs#ssh-to-age` (then run them inside).

> **Why we pre-create the host key (step 1):** sops decrypts at activation using
> the machine's SSH host key, so the build can't succeed until that key exists
> and is a sops recipient. Normally the host key only appears *after* a rebuild
> — a chicken-and-egg. Creating it by hand first breaks the cycle; OpenSSH
> adopts an existing key rather than regenerating one.

### 1. Pre-create this machine's SSH host key

```sh
sudo ssh-keygen -t ed25519 -f /etc/ssh/ssh_host_ed25519_key -N ""
```

### 2. Generate your GitHub SSH key (no passphrase — sops protects it at rest)

```sh
ssh-keygen -t ed25519 -C "jake@overview.app" -N "" -f ~/.ssh/id_github
cat ~/.ssh/id_github.pub   # add this at https://github.com/settings/keys
```

### 3. Create your personal age key (lets *you* edit secrets)

```sh
mkdir -p ~/.config/sops/age
age-keygen -o ~/.config/sops/age/keys.txt
age-keygen -y ~/.config/sops/age/keys.txt   # prints your age PUBLIC key
```

Put that public key in `.sops.yaml` as `&admin_jakek`.

### 4. Get this machine's age public key (from the host key from step 1)

```sh
sudo ssh-to-age < /etc/ssh/ssh_host_ed25519_key.pub
```

Put that in `.sops.yaml` as `&host_nixos`, and remove the two TODO comments.

### 5. Create the encrypted secrets file

```sh
mkdir -p secrets
sops secrets/secrets.yaml
```

`sops` opens `$EDITOR` on a decrypted buffer. Add your key as a YAML block
scalar (mind the indentation — the whole PEM body is indented under the `|`):

```yaml
github_ssh_key: |
  -----BEGIN OPENSSH PRIVATE KEY-----
  b3BlbnNzaC1rZXk...
  ...
  -----END OPENSSH PRIVATE KEY-----
```

Paste the contents of `~/.ssh/id_github` verbatim, keeping the trailing newline.
Save & quit — sops writes the file encrypted. Safe to `git add`.

> You can add more secrets to the same file later (e.g. a `github_pat:` line for
> HTTPS/API access) and declare each with its own `sops.secrets."<name>"` entry.

### 6. Rebuild

```sh
sudo nixos-rebuild switch --flake .#jakek
```

On activation, sops decrypts `github_ssh_key` to `/run/secrets/github_ssh_key`
(owned by `jakek`, mode 0600). Verify:

```sh
ssh -T git@github.com   # -> "Hi <you>! You've successfully authenticated..."
```

## Adding another machine later

1. On the new machine, get its host age key: `sudo ssh-to-age < /etc/ssh/ssh_host_ed25519_key.pub`
2. Add it to `.sops.yaml` as a new `&host_<name>` under `keys:` and `creation_rules`.
3. Re-encrypt to the new recipient set: `sops updatekeys secrets/secrets.yaml`
4. Commit, pull on the new machine, rebuild.

## Rotating / editing secrets

- Edit: `sops secrets/secrets.yaml`
- After changing `.sops.yaml` recipients: `sops updatekeys secrets/secrets.yaml`
