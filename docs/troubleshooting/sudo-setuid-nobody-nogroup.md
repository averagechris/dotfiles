# Sudo setuid permission error: `nobody:nogroup` ownership

## Symptoms

- `sudo` fails with a setuid-related permission error
- Running `ls -la /run/wrappers/bin/sudo` shows ownership as `nobody:nogroup` instead of `root:root`
- All files in `/run/wrappers/` are owned by `nobody:nogroup`
- All files in `/nix/store/` appear to be owned by `nobody:nogroup`
- `pkexec`, `su`, and other setuid binaries also fail

Example output when the issue is present:

```
$ ls -la /run/wrappers/bin/sudo
-r-s--x--x 1 nobody nogroup 70712 Jan 20 20:00 /run/wrappers/bin/sudo

$ ls -la /nix/store/ | head -5
drwxrwxr-t 2711 nobody nogroup 1785856 Jan 26 16:07 .
```

## Root cause

This issue occurs when the NixOS system was **installed from within a user namespace** where UID 0 (root) was mapped to an unprivileged user. This can happen when:

1. Installing NixOS from within a container or VM with UID remapping
2. Using `nix-user-chroot` or similar tools during installation
3. Running `disko` or `nixos-install` in an environment with user namespace isolation
4. The installation ISO/environment had unusual namespace configuration

When files are created or `chown`ed to "root" inside a user namespace, they actually get owned by the mapped UID (typically `nobody`/65534) when viewed from outside the namespace.

**Important**: The ownership issue is a **display/mapping problem at runtime**, not necessarily an on-disk corruption. The on-disk ownership may actually be correct, but the running system's UID mapping causes it to display as `nobody:nogroup`.

## Diagnosis

### Step 1: Check current ownership

```bash
ls -la /run/wrappers/bin/sudo
ls -la /nix/store/ | head -5
ls -la /nix/
```

If everything shows `nobody:nogroup`, proceed to Step 2.

### Step 2: Boot from NixOS Live USB and verify on-disk ownership

```bash
# Open LUKS if encrypted
sudo cryptsetup open /dev/nvme0n1p3 cryptroot  # adjust device as needed

# Mount root filesystem
sudo mount /dev/mapper/cryptroot /mnt  # or /dev/nvme0n1pX for unencrypted

# Check actual on-disk ownership
ls -la /mnt/nix/
ls -la /mnt/nix/store/ | head -5
```

**If on-disk shows `root:root` and `root:nixbld`**: The issue is runtime UID mapping, not disk corruption. A reboot may fix it, or there's something in the initrd/boot process causing the mapping issue.

**If on-disk shows `nobody:nogroup`**: The files were actually written with wrong ownership during installation. Proceed to the fix.

## Fix

### Boot from NixOS Live USB

1. Download NixOS ISO and create bootable USB
2. Boot from the USB

### Mount the installed system

```bash
# For LUKS-encrypted systems
sudo cryptsetup open /dev/nvme0n1p3 cryptroot
sudo mount /dev/mapper/cryptroot /mnt

# For unencrypted systems
sudo mount /dev/nvme0n1pX /mnt  # adjust partition as needed

# Mount boot partition if separate
sudo mount /dev/nvme0n1p1 /mnt/boot  # adjust as needed
```

### Fix ownership

```bash
# Fix /nix directory
sudo chown root:root /mnt/nix

# Fix /nix/var
sudo chown -R root:root /mnt/nix/var

# Fix /nix/store (this may take a minute)
sudo chown -R root:root /mnt/nix/store

# Set correct permissions on store (sticky bit + group writable for nixbld)
sudo chmod 1775 /mnt/nix/store
```

### Verify the fix

```bash
ls -la /mnt/nix/
# Should show: drwxr-xr-x root root for . and var
# Should show: drwxrwxr-t root root (or root nixbld) for store
```

### Unmount and reboot

```bash
sudo umount /mnt/boot  # if mounted
sudo umount /mnt
sudo cryptsetup close cryptroot  # if using LUKS
sudo reboot
```

### Verify after reboot

After booting into the installed system:

```bash
ls -la /run/wrappers/bin/sudo
# Should show: -r-s--x--x 1 root root ...

sudo whoami
# Should output: root
```

## Prevention

When installing NixOS:

1. **Use the official NixOS installer ISO** directly, not from within containers or VMs with UID remapping
2. **Avoid running `nixos-install` or `disko`** from environments that use user namespaces
3. **If using a custom installation environment**, ensure UID 0 maps to real root (check with `cat /proc/self/uid_map`)

## Related issues

- Affects all setuid binaries: `sudo`, `su`, `pkexec`, `mount`, `umount`, `passwd`, etc.
- The `suid-sgid-wrappers.service` runs correctly but the resulting files have wrong ownership
- NixOS creates wrappers fresh on each boot in `/run/wrappers` (tmpfs), so the issue recurs every boot until the underlying `/nix/store` ownership is fixed

## Technical details

NixOS uses a wrapper system for setuid binaries located at `/run/wrappers/bin/`. The `suid-sgid-wrappers.service` runs during early boot to:

1. Create a tmpfs at `/run/wrappers`
2. Copy security wrapper binaries from `/nix/store/`
3. `chown root:root` and `chmod u+s` the wrappers

When the `/nix/store` files are owned by `nobody`, the copied wrappers inherit this ownership, and the `chown` command may silently fail or be ineffective due to the UID mapping issue.
