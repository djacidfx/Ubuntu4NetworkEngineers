# Backup your toolchain

If you are a network engineer you will undoubtedly install many tools using:

- homebrew
- apt
- GitHub
- and others

If you want to:

- reinstall Ubuntu and overwrite your current setup
- spin up a new laptop
- or your laptop is stolen

You need to get back up to speed quickly, you don't want to start from scratch remembering what you installed over time. Claude wrote a shell script for me when I was migrating from Ubuntu 25.04 to 26.04. I wanted do to a fresh install so that I got Dracut as the Init system.

## The theory

1. Use the Free Open Source Software (FOSS) **Clonezilla** to create an image on an external drive. Download Clonezilla [Here:](https://clonezilla.org/downloads.php). Select the `stable` link. The page will update to the `Downloads` page. Select the following:

----------------------------------------------------------------

~![screenshot](./img/clonezilla-dowload.png)

----------------------------------------------------------------

### Make a bootable flash drive

Then use [Impression](CH02-Install-Tools.md/#gnome-circle-apps) to create a bootable flash drive. Reboot into the flash drive and follow the onscreen instructions. You can find the Clonezilla live Docs [Here:](https://clonezilla.org/clonezilla-live-doc.php){: target="_blank" rel="noopener" }

----------------------------------------------------------------

The Clonezilla image is your rollback-of-last-resort; a manifest is your *actual* rebuild path — and it's better than booting back into 25.04 repeatedly, because you get a checklist you work through once instead of a system you keep context-switching into.

----------------------------------------------------------------

### Run the script

A few design decisions worth knowing before you run it:

The apt capture uses `apt-mark showmanual`, not `dpkg -l`. That gives you only the packages *you* explicitly asked for — not the thousand-package dependency closure — which is the list you actually reinstall from. And since `nala` writes to the same `dpkg` database, this catches your `nala` installs too; `nala's` a front-end, not a separate inventory. For `Homebrew` it uses `brew bundle dump`, which produces a `Brewfile` you restore with one `brew bundle install` — taps, formulae, and casks in a single restorable artifact.

Two warnings baked into the script that matter for *you* specifically: your netplan files and NetworkManager connections hold the customer WiFi profiles and their PSKs — real secrets — so those go into a clearly-marked `SENSITIVE/` subdir, and you decide whether they're allowed near Insync/Google Drive. And the output lands in `$HOME` on the drive you're about to wipe, so the script ends by reminding you to copy it *off*. That covers your list plus the things easy to forget until you're mid-rebuild and cursing. The extras I added beyond what you asked for, and why they're in there for *you* specifically:

#### Group memberships (`system/groups.txt`)

The reinstall note calls out `dialout` explicitly. That's your serial-console access to Cisco gear; forget it and your USB-serial adapters won't open until you re-add yourself and log out/in. `libvirt`, `kvm`, `wireshark` are in there too.

#### Netplan + NetworkManager connections

Your br0 bridge on enp60s0, the VLAN 10/11 split, and all those `90-NM-*` customer WiFi profiles with their PSKs. These land in `SENSITIVE/` because they carry passwords. One firm caveat baked into the notes: don't blind-copy plucky netplan onto 26.04 — interface names usually survive but the syntax and defaults can shift, so review before applying.

#### APT sources + keyrings

Reference only, since the ubuntu.sources codename changes on 26.04.

#### libvirt VM XML
Dumps the definition for your Ubuntu-24.04-LegacySSH VM (and any others) so you can `virsh define` them back. But the loud warning: **the qcow2 disk images live on the 2TB drive you're wiping.** The XML is tiny; the disks aren't.

----------------------------------------------------------------

`sudo virsh domblklist <vm>` shows their paths — copy those to the 1TB separately or that legacy-SSH runtime is gone. The KVM section does a lot more than list paths, and the extras are the ones that actually save you:

**It walks the backing chain, not just the top disk.** You mentioned your legacy-SSH VM is backed up as a *flattened* qcow2 — but if any VM uses a base+overlay setup, `virsh domblklist` shows only the overlay. Copy that alone and you've orphaned it from its base: a dead VM on the other side. So for each disk it runs `qemu-img info --backing-chain` and pulls *every* member of the chain into the copy list. If a VM is genuinely flattened, the chain is just one file and you get exactly that — no harm, no duplication.

**It sizes everything and totals it.** `kvm/disk-images.txt` is the human-readable report (VM, target device, size, path, with base images tagged `~base1`), and the run prints a grand total — so before you start you know whether your VM images fit on the 1TB alongside the Clonezilla image and your existing backups. Given NVMe prices drove this whole conversation, knowing the number up front matters.

**It generates `copy-vm-disks.sh`** — a ready-to-run helper that rsyncs every image (chain included) to a destination you pass in, with `--sparse` so qcow2 files don't balloon and `--info=progress2` so you can watch it. De-duped, so a base image shared by two VMs copies once.

### Two things before you run it

The whole output folder lands in `$HOME` on the drive you're about to wipe. The script screams about this at the end, but it bears repeating — copy it to the 1TB (or push the non-sensitive parts through `~/Insync`) before you boot the 26.04 installer. A manifest that gets wiped with the system it describes is a cruel joke.

And `SENSITIVE/` holds WiFi passwords and your ssh config. If you route that folder through Insync to Google Drive, you're uploading customer WiFi PSKs to the cloud — your call, but given your line of work I'd keep that subdir on the local 1TB only, or tar+encrypt it. Private ssh keys aren't auto-copied for the same reason; handle `~/.ssh/id_*` yourself.

Run it as your normal user, not under sudo — brew and gh and code all need user context, and the script sudo's itself only for the handful of `/etc` reads that require it. Give it a look before running since it touches sudo, then let me know what it caught and what came back `[skip]` — the skips sometimes point at something worth grabbing by hand.

## The workflow when you're ready to wipe

- Run the script
- Verify the size of the VM qcow2 files
- Copy the VMs to the backup drive

```bash
./system-manifest.sh                                    # inventory
cat ~/system-manifest-*/kvm/disk-images.txt             # eyeball sizes + total
sudo ~/system-manifest-*/kvm/copy-vm-disks.sh /media/mhubbard/Backup/vm-images
```

Here is the output of the script:

```bash hl_lines='1'
┌─[mhubbard@1S1K-G5] - [~/Insync/GD/05_Ubuntu] - [9885]
└─[$] ./system-manifest.sh
```

```bash title='Command Output'
Writing manifest to: /home/mhubbard/system-manifest-1S1K-G5-2026-08-08

=== Package managers ===
  [ok]   apt manual packages          -> packages/apt-manual.txt
  [ok]   dpkg full (reference)        -> packages/dpkg-full.txt
  [ok]   apt auto-installed           -> packages/apt-auto.txt
  [ok]   nala history                 -> packages/nala-history.txt
  [ok]   snap packages                -> packages/snap.txt
  [ok]   flatpak apps                 -> packages/flatpak.txt
  [ok]   Brewfile (taps+formulae+casks) -> packages/Brewfile
  [ok]   brew leaves (top-level)      -> packages/brew-leaves.txt
  [ok]   pip (system)                 -> packages/pip-freeze.txt
  [ok]   pip3 (system)                -> packages/pip3-freeze.txt
  [ok]   go version                   -> packages/go-version.txt

=== Dev tooling ===
  [ok]   git global config            -> dev/
  [skip] git ignore global            (not found)
  [ok]   local git repos            -> dev/local-git-repos.txt

=== Shell / zsh ===
  [ok]   .zshrc                       -> shell/
  [ok]   .zshenv                      -> shell/
  [skip] .zprofile                    (not found)
  [skip] .zlogin                      (not found)
  [skip] .p10k.zsh                    (not found)
  [skip] .aliases                     (not found)
  [skip] .functions                   (not found)
  [ok]   zsh history                  -> shell/
  [warn] oh-my-zsh custom             (copy failed)
  [skip] tmux.conf                    (not found)

=== Network config  (br0 / VLANs / customer WiFi) ===
[sudo] password for mhubbard:
  [ok]   /etc/netplan              -> SENSITIVE/netplan/
  [ok]   NM system-connections      -> SENSITIVE/  (has WiFi passwords)
  [ok]   ip addr snapshot             -> network/ip-addr.txt
  [ok]   ip route snapshot            -> network/ip-route.txt
  [ok]   /etc/hosts                   -> network/

=== APT sources + keyrings  (your cleaned config) ===
  [ok]   /etc/apt/sources.list.d    -> system/apt-sources.list.d/
  [ok]   /etc/apt/keyrings          -> system/apt-keyrings/

=== System state ===
  [ok]   groups (id)                  -> system/groups.txt
  [skip] crontab (user)               (not present / no output)
  [ok]   enabled user units           -> system/systemd-user.txt
  [ok]   enabled sys units            -> system/systemd-system.txt
  [ok]   default target               -> system/systemd-target.txt
  [ok]   timezone/locale              -> system/locale.txt
  [ok]   foreign arches               -> system/dpkg-arches.txt
  [ok]   dconf (GNOME settings)     -> system/dconf-dump.ini
  [ok]   user fonts                   -> system/

=== SSH config  (legacy Cisco kex etc.) ===
  [ok]   ssh config                   -> SENSITIVE/
  [ok]   ssh known_hosts              -> SENSITIVE/
  note: private keys NOT auto-copied. Handle ~/.ssh/id_* yourself, encrypted.

=== KVM / libvirt  (VM definitions + disk image paths) ===
  [ok]   VM list -> kvm/vms.txt
  [ok]   dumpxml ghostlock-test-ubuntu
  [ok]   dumpxml Kali-2025.2
  [ok]   dumpxml Ubuntu-24.04-LegacySSH
  [ok]   disk image report -> kvm/disk-images.txt
  [ok]   copy list         -> kvm/disk-copy-list.txt
  >> Total VM disk data to copy off: 132G
  [ok]   copy helper       -> kvm/copy-vm-disks.sh
  !! Disk images live on the drive you will wipe. Run:
        sudo /home/mhubbard/system-manifest-1S1K-G5-2026-08-08/kvm/copy-vm-disks.sh /media/mhubbard/Backup/vm-images

=== Writing reinstall notes ===
  [ok]   REINSTALL-NOTES.md

=== Done ===

Manifest complete: /home/mhubbard/system-manifest-1S1K-G5-2026-08-08  (19M)

  SENSITIVE/  holds WiFi PSKs and ssh config — treat accordingly.
              Do NOT sync to cloud unless you're OK with that.

NEXT (important): this folder is on the drive you're about to wipe.
Copy it off NOW, e.g.:
    cp -a "/home/mhubbard/system-manifest-1S1K-G5-2026-08-08" /media/mhubbard/Backup/     # your 1TB
  or (non-sensitive parts) into ~/Insync to reach Google Drive.

Optional tarball:
    tar czf "/home/mhubbard/system-manifest-1S1K-G5-2026-08-08.tar.gz" -C "/home/mhubbard" "system-manifest-1S1K-G5-2026-08-08"
```

----------------------------------------------------------------

!!! warning
    One caveat on the total: if a VM is running when you copy its image, you're grabbing a live/inconsistent disk. For a clean copy, `virsh shutdown <vm>` first — fine for a migration since you're archiving them anyway, just don't rsync a running VM and expect it to boot cleanly on the other side.

----------------------------------------------------------------

### Check VM qcow2 size

After running the script and before reinstalling run this command to check the VM sizes.
```bash hl_lines='2'
┌─[mhubbard@1S1K-G5] - [~/Insync/GD/05_Ubuntu] - [9887]
└─[$] cat ~/system-manifest-*/kvm/disk-images.txt
```

```bash Linenums='1' title='Command Output'
     File: /home/mhubbard/system-manifest-1S1K-G5-2026-08-08/kvm/disk-images.txt
   1 VM                           TARGET       SIZE      SOURCE (chain member)
   2 ghostlock-test-ubuntu        vda          13G       /var/lib/libvirt/images/ghostlock-test-ubuntu.qcow2
   3 Kali-2025.2                  vda          42G       /var/lib/libvirt/images/Kali-2025.2.qcow2
   4 Ubuntu-24.04-LegacySSH       vda          78G       /var/lib/libvirt/images/Ubuntu-24.04-LegacySSH.qcow2
```

----------------------------------------------------------------

### Copy the VM qcow2 files

My drive is named Backup and vm-images is where I keep VM. Change the name to whatever your disk is named.

```bash hl_lines='1'
sudo ~/system-manifest-*/kvm/copy-vm-disks.sh /media/mhubbard/Backup/vm-images
```

## The script

Here is the `system-manifest.sh` shell script. It's also in the repo if you want to download it.

To use the script

- Open a terminal
- change to the home directory `cd ~`
- `touch system-manifest.sh`
- nano system-manifest.sh
- Copy the code below and paste it into nano
- Save and exit - `ctrl-s`, `ctrl-x`
- Make the script executable - `chmod +x system-manifest.sh`
- Run the script, follow the instructions above

```bash linenums='1' hl_lines='1'
#!/usr/bin/env bash
# ============================================================================
# system-manifest.sh
# Capture a full tool + config inventory before an OS reinstall, so you can
# rebuild your environment from a checklist instead of memory.
#
# Run as your NORMAL USER (not sudo) — brew/code/gh must run in user context.
# The script calls sudo itself only for the few system files that need it.
#
# Usage:
#   chmod +x system-manifest.sh
#   ./system-manifest.sh
#
# Output: ~/system-manifest-<host>-<date>/   (copy this OFF the drive you wipe)
# ============================================================================

set -uo pipefail   # NOT -e: we want to continue past individual failures

OUTDIR="$HOME/system-manifest-$(hostname)-$(date +%Y-%m-%d)"
mkdir -p "$OUTDIR"/{packages,dev,shell,network,system,kvm,SENSITIVE}
chmod 700 "$OUTDIR/SENSITIVE"

have() { command -v "$1" >/dev/null 2>&1; }
sec()  { printf '\n\033[1;36m=== %s ===\033[0m\n' "$1"; }
cap()  { # cap <label> <outfile> <command...>
  local label="$1" out="$2"; shift 2
  if "$@" >"$out" 2>/dev/null; then
    printf '  [ok]   %-28s -> %s\n' "$label" "${out#$OUTDIR/}"
  else
    printf '  [skip] %-28s (not present / no output)\n' "$label"
    rm -f "$out"
  fi
}
copy() { # copy <label> <src> <destdir>
  local label="$1" src="$2" dest="$3"
  if [ -e "$src" ]; then
    cp -a "$src" "$dest"/ 2>/dev/null \
      && printf '  [ok]   %-28s -> %s\n' "$label" "${dest#$OUTDIR/}/" \
      || printf '  [warn] %-28s (copy failed)\n' "$label"
  else
    printf '  [skip] %-28s (not found)\n' "$label"
  fi
}

echo "Writing manifest to: $OUTDIR"

# ---------------------------------------------------------------------------
sec "Package managers"
# apt: MANUALLY installed only — this is your rebuild list (covers nala too)
cap "apt manual packages"   "$OUTDIR/packages/apt-manual.txt"        apt-mark showmanual
cap "dpkg full (reference)" "$OUTDIR/packages/dpkg-full.txt"         dpkg -l
cap "apt auto-installed"    "$OUTDIR/packages/apt-auto.txt"          apt-mark showauto
have nala    && cap "nala history"      "$OUTDIR/packages/nala-history.txt"  nala history
have snap    && cap "snap packages"     "$OUTDIR/packages/snap.txt"          snap list
have flatpak && cap "flatpak apps"      "$OUTDIR/packages/flatpak.txt"       flatpak list --app --columns=application,name

# Homebrew — Brewfile is the one-shot restore artifact
if have brew; then
  brew bundle dump --force --file="$OUTDIR/packages/Brewfile" >/dev/null 2>&1 \
    && echo "  [ok]   Brewfile (taps+formulae+casks) -> packages/Brewfile"
  cap "brew leaves (top-level)" "$OUTDIR/packages/brew-leaves.txt" brew leaves --installed-on-request
fi

# Language/dev package managers
have pipx  && cap "pipx apps"        "$OUTDIR/packages/pipx.txt"        pipx list
have pip   && cap "pip (system)"     "$OUTDIR/packages/pip-freeze.txt"  pip freeze
have pip3  && cap "pip3 (system)"    "$OUTDIR/packages/pip3-freeze.txt" pip3 freeze
have cargo && cap "cargo installed"  "$OUTDIR/packages/cargo.txt"       cargo install --list
have npm   && cap "npm global"       "$OUTDIR/packages/npm-global.txt"  npm ls -g --depth=0
have go    && cap "go version"       "$OUTDIR/packages/go-version.txt"  go version

# ---------------------------------------------------------------------------
sec "Dev tooling"
have code && cap "VS Code extensions" "$OUTDIR/dev/vscode-extensions.txt" code --list-extensions
if have gh; then
  cap "gh extensions"  "$OUTDIR/dev/gh-extensions.txt" gh extension list
  cap "gh auth status" "$OUTDIR/dev/gh-auth.txt"       gh auth status
  cap "gh own repos"   "$OUTDIR/dev/gh-repos.txt"      gh repo list --limit 200
fi
copy "git global config" "$HOME/.gitconfig"     "$OUTDIR/dev"
copy "git ignore global" "$HOME/.gitignore"     "$OUTDIR/dev"
# Find local git repos (working copies you'll want to re-clone or re-sync)
find "$HOME" -maxdepth 5 -type d -name .git 2>/dev/null \
  | sed 's|/.git$||' > "$OUTDIR/dev/local-git-repos.txt" \
  && echo "  [ok]   local git repos            -> dev/local-git-repos.txt"

# ---------------------------------------------------------------------------
sec "Shell / zsh"
for f in .zshrc .zshenv .zprofile .zlogin .p10k.zsh .aliases .functions; do
  copy "$f" "$HOME/$f" "$OUTDIR/shell"
done
copy "zsh history"    "$HOME/.zsh_history"        "$OUTDIR/shell"
copy "oh-my-zsh custom" "$HOME/.oh-my-zsh/custom" "$OUTDIR/shell"
[ -d "$HOME/.config/zsh" ] && copy ".config/zsh" "$HOME/.config/zsh" "$OUTDIR/shell"
copy "tmux.conf"      "$HOME/.tmux.conf"          "$OUTDIR/shell"
# Snapshot resolved aliases/functions as readable reference
if [ -n "${ZSH_VERSION:-}" ] || have zsh; then
  zsh -ic 'alias' 2>/dev/null > "$OUTDIR/shell/aliases-resolved.txt" || true
fi

# ---------------------------------------------------------------------------
sec "Network config  (br0 / VLANs / customer WiFi)"
# netplan — root-readable; captured to SENSITIVE (may embed keys)
if [ -d /etc/netplan ]; then
  sudo cp -a /etc/netplan "$OUTDIR/SENSITIVE/netplan" 2>/dev/null \
    && sudo chown -R "$USER":"$USER" "$OUTDIR/SENSITIVE/netplan" \
    && echo "  [ok]   /etc/netplan              -> SENSITIVE/netplan/"
fi
# NetworkManager system connections — CONTAIN WiFi PSKs
if [ -d /etc/NetworkManager/system-connections ]; then
  sudo cp -a /etc/NetworkManager/system-connections "$OUTDIR/SENSITIVE/NM-system-connections" 2>/dev/null \
    && sudo chown -R "$USER":"$USER" "$OUTDIR/SENSITIVE/NM-system-connections" \
    && echo "  [ok]   NM system-connections      -> SENSITIVE/  (has WiFi passwords)"
fi
cap "ip addr snapshot"  "$OUTDIR/network/ip-addr.txt"   ip -br a
cap "ip route snapshot" "$OUTDIR/network/ip-route.txt"  ip route
copy "/etc/hosts"       "/etc/hosts"                    "$OUTDIR/network"

# ---------------------------------------------------------------------------
sec "APT sources + keyrings  (your cleaned config)"
sudo cp -a /etc/apt/sources.list.d "$OUTDIR/system/apt-sources.list.d" 2>/dev/null \
  && sudo chown -R "$USER":"$USER" "$OUTDIR/system/apt-sources.list.d" \
  && echo "  [ok]   /etc/apt/sources.list.d    -> system/apt-sources.list.d/"
sudo cp -a /etc/apt/keyrings "$OUTDIR/system/apt-keyrings" 2>/dev/null \
  && sudo chown -R "$USER":"$USER" "$OUTDIR/system/apt-keyrings" \
  && echo "  [ok]   /etc/apt/keyrings          -> system/apt-keyrings/"
[ -d /etc/apt/preferences.d ] && sudo cp -a /etc/apt/preferences.d "$OUTDIR/system/apt-preferences.d" 2>/dev/null \
  && sudo chown -R "$USER":"$USER" "$OUTDIR/system/apt-preferences.d"

# ---------------------------------------------------------------------------
sec "System state"
cap "groups (id)"          "$OUTDIR/system/groups.txt"          id
cap "crontab (user)"       "$OUTDIR/system/crontab-user.txt"    crontab -l
cap "enabled user units"   "$OUTDIR/system/systemd-user.txt"    systemctl --user list-unit-files --state=enabled
cap "enabled sys units"    "$OUTDIR/system/systemd-system.txt"  systemctl list-unit-files --state=enabled
cap "default target"       "$OUTDIR/system/systemd-target.txt"  systemctl get-default
cap "timezone/locale"      "$OUTDIR/system/locale.txt"          localectl status
cap "foreign arches"       "$OUTDIR/system/dpkg-arches.txt"     dpkg --print-foreign-architectures
# Desktop settings
have dconf && dconf dump / > "$OUTDIR/system/dconf-dump.ini" 2>/dev/null \
  && echo "  [ok]   dconf (GNOME settings)     -> system/dconf-dump.ini"
# Custom local binaries and udev rules you may have added
[ -d /usr/local/bin ] && ls -la /usr/local/bin > "$OUTDIR/system/usr-local-bin.txt" 2>/dev/null
sudo ls -la /etc/udev/rules.d 2>/dev/null > "$OUTDIR/system/udev-rules.txt"
# Fonts
copy "user fonts"  "$HOME/.local/share/fonts" "$OUTDIR/system"

# ---------------------------------------------------------------------------
sec "SSH config  (legacy Cisco kex etc.)"
copy "ssh config"      "$HOME/.ssh/config"      "$OUTDIR/SENSITIVE"
copy "ssh known_hosts" "$HOME/.ssh/known_hosts" "$OUTDIR/SENSITIVE"
echo "  note: private keys NOT auto-copied. Handle ~/.ssh/id_* yourself, encrypted."

# ---------------------------------------------------------------------------
sec "KVM / libvirt  (VM definitions — NOT disk images)"
if have virsh; then
  virsh list --all > "$OUTDIR/kvm/vms.txt" 2>/dev/null && echo "  [ok]   VM list -> kvm/vms.txt"
  for vm in $(virsh list --all --name 2>/dev/null); do
    [ -n "$vm" ] && virsh dumpxml "$vm" > "$OUTDIR/kvm/$vm.xml" 2>/dev/null \
      && echo "  [ok]   dumpxml $vm"
  done
  virsh net-list --all > "$OUTDIR/kvm/networks.txt" 2>/dev/null
  for net in $(virsh net-list --all --name 2>/dev/null); do
    [ -n "$net" ] && virsh net-dumpxml "$net" > "$OUTDIR/kvm/net-$net.xml" 2>/dev/null
  done
  echo "  !! qcow2 DISK IMAGES are large and live on the drive you will wipe."
  echo "     Copy them separately — check: virsh domblklist <vm>"
fi

# ---------------------------------------------------------------------------
sec "Writing reinstall notes"
cat > "$OUTDIR/REINSTALL-NOTES.md" <<'NOTES'
# Reinstall checklist  (26.04)

## 1. APT packages you asked for
    xargs -a packages/apt-manual.txt sudo apt install -y
Review the list first — some may be plucky-only or renamed on 26.04.

## 2. Homebrew
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    brew bundle install --file=packages/Brewfile

## 3. VS Code extensions
    while read ext; do code --install-extension "$ext"; done < dev/vscode-extensions.txt

## 4. pipx CLI tools  (see packages/pipx.txt)
    pipx install <each>

## 5. Shell — copy back .zshrc etc. from shell/, then re-source.
   Re-check any absolute paths that assumed plucky.

## 6. Groups — re-add yourself (see system/groups.txt). Likely:
    sudo usermod -aG libvirt,kvm,dialout,wireshark $USER
   (dialout = serial console to Cisco gear — easy to forget)

## 7. Network — DO NOT blind-copy plucky netplan onto 26.04.
   Interface names (enp60s0/wlp61s0) usually persist, but review
   SENSITIVE/netplan against a fresh 26.04 default before applying.
   Customer WiFi: SENSITIVE/NM-system-connections/*.nmconnection ->
   /etc/NetworkManager/system-connections/  (chmod 600, chown root:root).

## 8. APT sources — reference only. On 26.04 the ubuntu.sources codename
   differs. Re-add third-party repos (vscode w/ keyring, termius, gierens,
   insync, chrome, solaar) from system/apt-sources.list.d/ as reference.

## 9. libvirt VMs — redefine from kvm/*.xml AFTER copying qcow2 images back:
    virsh define kvm/<vm>.xml
NOTES
echo "  [ok]   REINSTALL-NOTES.md"

# ---------------------------------------------------------------------------
sec "Done"
SIZE=$(du -sh "$OUTDIR" 2>/dev/null | cut -f1)
cat <<EOF

Manifest complete: $OUTDIR  ($SIZE)

  SENSITIVE/  holds WiFi PSKs and ssh config — treat accordingly.
              Do NOT sync to cloud unless you're OK with that.

NEXT (important): this folder is on the drive you're about to wipe.
Copy it off NOW, e.g.:
    cp -a "$OUTDIR" /media/mhubbard/Backup/     # your 1TB
  or (non-sensitive parts) into ~/Insync to reach Google Drive.

Optional tarball:
    tar czf "$OUTDIR.tar.gz" -C "$HOME" "$(basename "$OUTDIR")"
EOF
```
