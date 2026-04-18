# Fedora Custom Developer ISO (FedDev 43)

## Project Overview
This project demonstrates the creation of a custom Fedora 43 Live ISO using Kickstart and the `livemedia-creator` toolchain.

The goal was to build a reproducible, developer-focused Linux environment with preinstalled tools, system-level customization, and a validated build process.

---

## Objectives
- Automate OS image creation using Kickstart
- Customize package selection for development workflows
- Apply system-wide GNOME configuration
- Provide a ready-to-use developer environment
- Ensure reproducibility and stability of the build process

---

## Technologies Used
- Fedora 43
- Kickstart (ksflatten)
- livemedia-creator (Lorax)
- QEMU with KVM acceleration
- GNOME Desktop Environment

---

## Build Process

### Base Kickstart
```bash
ksflatten --config fedora-live-workstation.ks -o flat-workstation-base.ks
```

### ISO Build
```bash
systemd-inhibit --what=idle:sleep \
sudo livemedia-creator \
  --make-iso \
  --iso=Fedora-Everything-netinst-x86_64-43-1.6.iso \
  --ks=my-dev-workstation.ks \
  --resultdir=gnome-v1.4 \
  --logfile=gnome-v1.4.log \
  --project="FedDev" \
  --volid="FEDDEV43" \
  --iso-only \
  --iso-name="fedora-dev-gnome-v1.4.iso" \
  --releasever=43 \
  --ram=8192 \
  --vcpus=4 \
  --image-size=20480 \
  --no-virt
```

---

## Interactive ISO Builder (v1.6)

### Features
- Setup mode (kickstarts and template generation)
- Build mode with:
  - predefined profiles (Minimal, Developer, Enterprise)
  - custom package selection
  - optional extras (GNOME defaults, MOTD, dev-check)
- Test ISO mode (QEMU boot)
- Build listing and management
- Cleanup mode

---

## Usage
```bash
./tools/interactive-iso-builder.sh
```

---

## Build Profiles
- **Minimal**: basic tools and GNOME environment
- **Developer**: full development environment
- **Enterprise**: stable productivity setup
- **Custom**: user-defined configuration

---

## Key Features

### Developer Environment
- Git
- Node.js / npm
- Python 3
- Podman / Buildah
- CLI tools (ripgrep, fzf, jq, tree)

### System Customization
- GNOME dark mode
- Hidden files enabled
- List view default
- `/etc/skel` preconfigured
- MOTD with onboarding hint
- `dev-check` validation script

---

## Testing
```bash
qemu-system-x86_64 \
  -enable-kvm \
  -m 4096 \
  -cpu host \
  -smp 4 \
  -cdrom fedora-dev-gnome-v1.4.iso
```

---

## Screenshots

### Core System
![GRUB](screenshots/v1.4/grub.png)
![GNOME](screenshots/v1.4/gnome.png)
![Files](screenshots/v1.4/files.png)
![MOTD](screenshots/v1.4/motd.png)
![Dev Check](screenshots/v1.4/dev-check.png)

### Interactive Builder
![Main Menu](screenshots/v1.6/01-main-menu.png)
![Build Inputs](screenshots/v1.6/02-build-inputs.png)
![Custom Config](screenshots/v1.6/03-custom-config.png)
![Test ISO](screenshots/v1.6/04-test-iso.png)
![List Builds](screenshots/v1.6/05-list-builds.png)
![Final Desktop](screenshots/v1.6/07-final-desktop.png)

---

## Interactive GUI Builder (v2)

A lightweight GUI wrapper was introduced using Zenity to simplify interaction with the ISO builder.

It allows:

- Running setup and cleanup operations
- Viewing available ISO builds
- Selecting and testing ISOs using QEMU
- Launching the builder from the desktop (Run in Terminal)

### GUI Main Menu

![GUI Main](screenshots/v1.6/10-gui-main.png)

### List Builds (GUI)

![GUI List Builds](screenshots/v1.6/11-gui-list-builds.png)

### Test ISO Selection

![GUI Test Select](screenshots/v1.6/12-gui-test-select.png)

### QEMU Launch (GUI)

![GUI QEMU](screenshots/v1.6/13-gui-qemu-run.png)

---

## Repository Structure
```
kickstarts/
docs/
screenshots/
checksums/
logs/
tools/
```

---

## Notes
- Kickstart is generated dynamically per build
- Uses `livemedia-creator --no-virt`
- SELinux set to permissive during build
- ISO files are NOT stored in the repo

---

## Conclusion
A complete workflow for building a customized Fedora-based developer ISO with automation, configurability, and validation.
