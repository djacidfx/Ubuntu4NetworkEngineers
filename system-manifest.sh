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
sec "KVM / libvirt  (VM definitions + disk image paths)"
# sudo so we hit qemu:///system where your VMs live. Plain user virsh talks to
# qemu:///session and would list NONE of your system VMs.
VIRSH="sudo virsh"
if have virsh; then
  $VIRSH list --all > "$OUTDIR/kvm/vms.txt" 2>/dev/null && echo "  [ok]   VM list -> kvm/vms.txt"

  : > "$OUTDIR/kvm/disk-copy-list.txt"
  printf '%-28s %-12s %-9s %s\n' "VM" "TARGET" "SIZE" "SOURCE (chain member)" \
    > "$OUTDIR/kvm/disk-images.txt"

  for vm in $($VIRSH list --all --name 2>/dev/null); do
    [ -n "$vm" ] || continue
    $VIRSH dumpxml "$vm" > "$OUTDIR/kvm/$vm.xml" 2>/dev/null && echo "  [ok]   dumpxml $vm"

    # file-backed disks only (skip cdroms and empty slots)
    $VIRSH domblklist "$vm" --details 2>/dev/null \
      | awk 'NR>2 && $1=="file" && $2=="disk" && $4!="-" {print $3" "$4}' \
      | while read -r target src; do
          [ -n "$src" ] || continue
          # Walk the backing chain so a flattened/overlay image never gets
          # separated from its base — copying only the overlay = dead VM.
          members=""
          if have qemu-img; then
            members=$(sudo qemu-img info --backing-chain "$src" 2>/dev/null \
                       | awk -F': ' '/^image:/{print $2}')
          fi
          [ -n "$members" ] || members="$src"
          n=0
          while read -r member; do
            [ -n "$member" ] || continue
            sz=$(sudo du -h "$member" 2>/dev/null | cut -f1)
            tag="$target"; [ "$n" -gt 0 ] && tag="$target~base$n"
            printf '%-28s %-12s %-9s %s\n' "$vm" "$tag" "${sz:-?}" "$member" \
              >> "$OUTDIR/kvm/disk-images.txt"
            echo "$member" >> "$OUTDIR/kvm/disk-copy-list.txt"
            n=$((n+1))
          done <<< "$members"
        done
  done

  # De-dup shared backing files across VMs
  sort -u "$OUTDIR/kvm/disk-copy-list.txt" -o "$OUTDIR/kvm/disk-copy-list.txt"
  echo "  [ok]   disk image report -> kvm/disk-images.txt"
  echo "  [ok]   copy list         -> kvm/disk-copy-list.txt"

  # libvirt networks
  $VIRSH net-list --all > "$OUTDIR/kvm/networks.txt" 2>/dev/null
  for net in $($VIRSH net-list --all --name 2>/dev/null); do
    [ -n "$net" ] && $VIRSH net-dumpxml "$net" > "$OUTDIR/kvm/net-$net.xml" 2>/dev/null
  done

  # Total footprint so you know if it fits on the 1TB before you start
  if [ -s "$OUTDIR/kvm/disk-copy-list.txt" ]; then
    total=$(sudo du -ch $(cat "$OUTDIR/kvm/disk-copy-list.txt") 2>/dev/null | tail -1 | cut -f1)
    echo "  >> Total VM disk data to copy off: ${total:-unknown}"
  fi

  # Ready-to-run helper that copies every image (chain included) to a target dir
  cat > "$OUTDIR/kvm/copy-vm-disks.sh" <<'CPEOF'
#!/usr/bin/env bash
# Copy all VM disk images (including backing files) off before you wipe.
# Usage: sudo ./copy-vm-disks.sh /media/mhubbard/Backup/vm-images
set -euo pipefail
DEST="${1:?usage: copy-vm-disks.sh <dest-dir>}"
mkdir -p "$DEST"
LIST="$(dirname "$0")/disk-copy-list.txt"
while read -r img; do
  [ -n "$img" ] || continue
  echo ">> $img"
  rsync -ah --info=progress2 --sparse "$img" "$DEST/"
done < "$LIST"
echo "Done -> $DEST"; ls -lh "$DEST"
CPEOF
  chmod +x "$OUTDIR/kvm/copy-vm-disks.sh"
  echo "  [ok]   copy helper       -> kvm/copy-vm-disks.sh"
  echo "  !! Disk images live on the drive you will wipe. Run:"
  echo "        sudo $OUTDIR/kvm/copy-vm-disks.sh /media/mhubbard/Backup/vm-images"
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
