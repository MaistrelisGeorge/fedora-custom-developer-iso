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

## 🔧 Interactive ISO Builder (v1.6)

The project now includes an interactive build system that allows dynamic customization of Fedora ISO images.

### Main Menu

![Main Menu](screenshots/v1.6/01-main-menu.png)

### Build Configuration

![Build Inputs](screenshots/v1.6/02-build-inputs.png)  
![Custom Config](screenshots/v1.6/03-custom-config.png)

### ISO Testing & Management

![Test ISO](screenshots/v1.6/04-test-iso.png)  
![List Builds](screenshots/v1.6/05-list-builds.png)

### Final System

![Desktop](screenshots/v1.6/07-final-desktop.png)  
![Dev Check](screenshots/v1.6/08-dev-check.png)  
![MOTD](screenshots/v1.6/09-motd.png)

---

## Build Process

### 1. Base Kickstart

The official Fedora Workstation Kickstart was flattened into a single file:

```bash
ksflatten \
  --config fedora-live-workstation.ks \
  -o flat-workstation-base.ks
