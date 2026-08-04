# Graphical NixOS VM test

The `hyprland-greetd-vm-test` package runs a disposable `aarch64-linux`
graphical NixOS machine for checking the shared Hyprland/ReGreet login
configuration. It imports and enables the real
`flakes/nixos-modules/modules/hyprland-desktop.nix` module, but deliberately does
not import a host configuration. It therefore uses no physical hardware or disk
layout, production users, network credentials, or secrets.

The VM selects the pinned Hyprland and `xdg-desktop-portal-hyprland` packages
from the repository's `hyprland` flake input. This keeps the compositor under
test aligned with tater and thorny's production pin rather than silently testing
nixpkgs's default Hyprland. Thorny also uses the input portal directly; tater
uses the nixpkgs portal overridden to the same Hyprland because of its stricter
closure-size policy.

The smoke test waits for greetd, Hyprland, ReGreet, the Wayland socket, and the
Hyprland control socket. Because ReGreet displays an asynchronous loading window
before its model is ready, process and socket startup alone are not considered
UI readiness. The test waits for ReGreet's post-user-discovery initialization
marker and then uses OCR for the large, stable `Welcome back` greeting. It then
checks QEMU monitor access, sends a keyboard event, verifies the graphical
processes remain alive, and writes
`hyprland-greetd-ready.png` to the test result. Readiness is based on service,
process, socket, application-initialization, and one stable text signal rather
than exact pixels. The screenshot is a human/agent diagnostic artifact, not a
pixel test. Failures also capture a screenshot and print greetd, AccountsService,
ReGreet, Hyprland, process, and runtime-socket diagnostics.

The login screen contains a disposable account with username `vmtest` and
password `vmtest`. These credentials are public test data, not a secret. They
must never be copied to a real host or reused for any persistent VM.
ReGreet 0.4 asks AccountsService for cached users, and a newly created VM account
has no login history, so the test seeds an AccountsService cache record for this
account. This is VM-only state; production machines build that cache through
normal local login history.

The test is intentionally a package rather than a flake check. Routine
`nix flake check` therefore evaluates its output shape but does not build the
large Linux graphical closure or require an ARM Linux builder. Run it explicitly
when testing graphical login behavior.

## Apple Silicon macOS

Recent nixpkgs supports an `aarch64-darwin` NixOS test driver. The host-side
driver and QEMU are Darwin binaries, while the guest is automatically paired
with `aarch64-linux`. The test asks the Nix daemon for the `apple-virt` system
feature and uses Apple's virtualization acceleration.

The guest closure still contains machine-specific generated derivations, so the
Mac's Nix daemon must also have a configured `aarch64-linux` builder. Cached
Linux packages alone are not sufficient. This can be a nix-darwin Linux builder,
a remote Apple Silicon NixOS machine, or another trusted builder advertising
`aarch64-linux`; no x86 builder is needed. Once that builder is available, run
the complete unattended smoke test explicitly with:

```bash
nix build -L .#hyprland-greetd-vm-test
open result/hyprland-greetd-ready.png
```

This requires an Apple Silicon Mac, `apple-virt`, and the Linux builder described
above. It is not an x86 emulation target and is not available on Intel macOS.
Check the local feature and builder setup with:

```bash
nix config show system-features
nix store ping --store 'ssh-ng://your-aarch64-linux-builder'
```

The first build is large because it includes a real Hyprland, ReGreet, GTK,
fonts, and the graphical NixOS closure. A `Required system: 'aarch64-linux';
Current system: 'aarch64-darwin'` error means Nix could not route an uncached
guest derivation to a Linux builder; it is not a QEMU or Hyprland failure.

The same guest can run under an `aarch64-linux` Nix builder (KVM by default):

```bash
nix build -L .#packages.aarch64-linux.hyprland-greetd-vm-test
```

That explicit Linux output may be sent to a configured remote builder; it is not
a macOS executable. Prefer the `aarch64-darwin` output for local Apple Silicon
execution.

## Driver and interactive use

The normal driver runs the test script immediately and exits success or failure.
Running it directly is useful while iterating because the VM is outside the Nix
build sandbox, but it is still automated and does not provide a Python prompt:

```bash
nix build .#hyprland-greetd-vm-driver
./result/bin/nixos-test-driver
```

The interactive driver does not automatically run the test script. It opens the
test-driver Python REPL and, when `start_all()` is called from a normal macOS
terminal, a native QEMU display window:

```bash
nix build .#hyprland-greetd-vm-driver-interactive
./result/bin/nixos-test-driver
```

At the interactive prompt, start and inspect the VM with:

```python
start_all()
machine.wait_for_unit("greetd.service")
machine.send_key("tab")
machine.screenshot("manual-greeter")
print(machine.send_monitor_command("info qtree"))
```

Both driver packages still require an `aarch64-linux` builder when their guest
closure has uncached generated derivations. Building a Darwin driver does not
move those Linux derivations onto macOS.

The test driver creates private QEMU monitor and QMP Unix sockets in its runtime
state directory. Prefer the supported `machine.send_monitor_command(...)`,
`machine.send_key(...)`, `machine.screenshot(...)`, and
`machine.wait_for_qmp_event(...)` APIs rather than depending on those temporary
socket paths. The interactive driver uses QEMU's native macOS display; this POC
does not add a network-listening VNC server. Keeping VNC disabled avoids exposing
an unauthenticated observation endpoint and avoids conflicts with the driver's
automatic display selection.

On `aarch64-linux`, use full flake paths for Linux-native outputs:

```bash
nix build .#packages.aarch64-linux.hyprland-greetd-vm-test
nix build .#packages.aarch64-linux.hyprland-greetd-vm-driver
nix build .#packages.aarch64-linux.hyprland-greetd-vm-driver-interactive
```

Do not try to execute the Linux driver binaries directly on macOS.
