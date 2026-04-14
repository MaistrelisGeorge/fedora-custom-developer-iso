# Interactive ISO Builder (v1.6)

The project includes an interactive build system for generating custom Fedora ISO images.

## Features

- Setup mode (kickstarts and template generation)
- Build mode with:
  - predefined profiles (Minimal, Developer, Enterprise)
  - custom package selection
  - optional extras (GNOME defaults, MOTD, dev-check utility)
- Test ISO mode (QEMU boot)
- Build listing and management
- Cleanup mode

## Usage

```bash
./tools/interactive-iso-builder.sh

## Build Profiles

- **Minimal**: basic tools and GNOME environment
- **Developer**: full development environment (Python, Node.js, containers, build tools)
- **Enterprise**: stable setup with productivity tools
- **Custom**: user-defined packages and extras

## Notes

- The builder dynamically generates a Kickstart file for each build.
- Builds are performed using `livemedia-creator --no-virt`.
- SELinux is temporarily set to permissive during the build process.
- ISO files are stored locally and are not included in the GitHub repository.
