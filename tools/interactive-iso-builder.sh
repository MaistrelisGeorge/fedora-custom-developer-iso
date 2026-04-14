#!/usr/bin/env bash

set -euo pipefail

PROJECT_ROOT="${HOME}/fedora-iso-builds"
KICKSTARTS_REPO="${PROJECT_ROOT}/fedora-kickstarts"
BASE_ISO="${PROJECT_ROOT}/Fedora-Everything-netinst-x86_64-43-1.6.iso"
BASE_KS="${PROJECT_ROOT}/flat-workstation-base.ks"
TEMPLATE_KS="${PROJECT_ROOT}/templates/base-template.ks"
GENERATED_DIR="${PROJECT_ROOT}/generated"
GENERATED_KS="${GENERATED_DIR}/generated-build.ks"
BUILDS_DIR="${PROJECT_ROOT}/builds"
LOGS_DIR="${PROJECT_ROOT}/logs"
TEMP_DIR="${PROJECT_ROOT}/tmp"

FEDORA_KS_SOURCE="${KICKSTARTS_REPO}/fedora-live-workstation.ks"
FEDORA_BRANCH="f43"

PROJECT_NAME="FedDev"
VOLID="FEDDEV43"
RELEASEVER="43"

PACKAGES_DEV_BASICS=$(cat <<'EOF'
git
vim-enhanced
tmux
htop
curl
wget
EOF
)

PACKAGES_PYTHON=$(cat <<'EOF'
python3
python3-pip
EOF
)

PACKAGES_NODE=$(cat <<'EOF'
nodejs
npm
EOF
)

PACKAGES_CONTAINERS=$(cat <<'EOF'
podman
buildah
skopeo
toolbox
EOF
)

PACKAGES_CLI_PRODUCTIVITY=$(cat <<'EOF'
jq
tree
bat
ripgrep
fzf
fd-find
EOF
)

PACKAGES_BUILD_TOOLS=$(cat <<'EOF'
gcc
gcc-c++
make
ShellCheck
EOF
)

PACKAGES_NETWORKING=$(cat <<'EOF'
openssh-clients
EOF
)

PACKAGES_BOOT_CRITICAL=$(cat <<'EOF'
grub2-pc-modules
grub2-efi-x64
shim-x64
grub2-common
EOF
)

SELECTED_PACKAGES=""
ENABLE_GNOME_DEFAULTS=0
ENABLE_SKEL_DOTFILES=0
ENABLE_MOTD=0
ENABLE_DEV_CHECK=0

print_header() {
  echo
  echo "======================================"
  echo " Fedora Interactive ISO Builder"
  echo "======================================"
  echo
}

pause() {
  read -r -p "Press Enter to continue..."
}

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "ERROR: Missing command: $cmd"
    exit 1
  fi
}

ensure_dirs() {
  mkdir -p "$PROJECT_ROOT" "$GENERATED_DIR" "$BUILDS_DIR" "$LOGS_DIR" "$TEMP_DIR" "${PROJECT_ROOT}/templates"
}

confirm() {
  local prompt="$1"
  local answer
  read -r -p "$prompt [y/N]: " answer
  [[ "${answer,,}" == "y" || "${answer,,}" == "yes" ]]
}

validate_build_tools() {
  require_cmd git
  require_cmd ksflatten
  require_cmd livemedia-creator
  require_cmd sudo
  require_cmd systemd-inhibit
  require_cmd python3
  require_cmd qemu-system-x86_64
}

cleanup_build_artifacts() {
  echo
  echo "Cleaning build leftovers..."

  sudo pkill -f anaconda || true
  sudo pkill -f livemedia-creator || true
  sudo pkill -f qemu || true

  sudo umount -l /mnt/sysimage/run/user/0 2>/dev/null || true
  sudo umount -l /mnt/sysimage/run 2>/dev/null || true
  sudo umount -l /mnt/sysimage 2>/dev/null || true
  sudo umount -l /mnt/sysroot/run/user/0 2>/dev/null || true
  sudo umount -l /mnt/sysroot/run 2>/dev/null || true
  sudo umount -l /mnt/sysroot 2>/dev/null || true

  sudo rm -f /run/user/0/anaconda.pid || true
  sudo rm -rf /var/tmp/lmc-* || true
  sudo rm -rf /var/tmp/lmc-work-* || true

  rm -f "${TEMP_DIR}/post-section.txt" || true
  rm -f "${TEMP_DIR}/packages-section.txt" || true

  echo "Cleanup completed."
}

set_selinux_permissive() {
  echo "Setting SELinux to permissive..."
  sudo setenforce 0
}

restore_selinux_enforcing() {
  echo "Restoring SELinux to enforcing..."
  sudo setenforce 1
  getenforce || true
}

reset_package_and_extra_selection() {
  SELECTED_PACKAGES="$PACKAGES_BOOT_CRITICAL"$'\n'
  ENABLE_GNOME_DEFAULTS=0
  ENABLE_SKEL_DOTFILES=0
  ENABLE_MOTD=0
  ENABLE_DEV_CHECK=0
}

dedupe_selected_packages() {
  SELECTED_PACKAGES=$(printf "%s\n" "$SELECTED_PACKAGES" | awk 'NF && !seen[$0]++')
}

apply_profile_minimal() {
  reset_package_and_extra_selection
  SELECTED_PACKAGES+="$PACKAGES_DEV_BASICS"$'\n'
  SELECTED_PACKAGES+="$PACKAGES_NETWORKING"$'\n'
  ENABLE_GNOME_DEFAULTS=1
  ENABLE_SKEL_DOTFILES=1
  dedupe_selected_packages
}

apply_profile_developer() {
  reset_package_and_extra_selection
  SELECTED_PACKAGES+="$PACKAGES_DEV_BASICS"$'\n'
  SELECTED_PACKAGES+="$PACKAGES_PYTHON"$'\n'
  SELECTED_PACKAGES+="$PACKAGES_NODE"$'\n'
  SELECTED_PACKAGES+="$PACKAGES_CONTAINERS"$'\n'
  SELECTED_PACKAGES+="$PACKAGES_CLI_PRODUCTIVITY"$'\n'
  SELECTED_PACKAGES+="$PACKAGES_BUILD_TOOLS"$'\n'
  SELECTED_PACKAGES+="$PACKAGES_NETWORKING"$'\n'
  ENABLE_GNOME_DEFAULTS=1
  ENABLE_SKEL_DOTFILES=1
  ENABLE_MOTD=1
  ENABLE_DEV_CHECK=1
  dedupe_selected_packages
}

apply_profile_enterprise() {
  reset_package_and_extra_selection
  SELECTED_PACKAGES+="$PACKAGES_DEV_BASICS"$'\n'
  SELECTED_PACKAGES+="$PACKAGES_PYTHON"$'\n'
  SELECTED_PACKAGES+="$PACKAGES_CLI_PRODUCTIVITY"$'\n'
  SELECTED_PACKAGES+="$PACKAGES_BUILD_TOOLS"$'\n'
  SELECTED_PACKAGES+="$PACKAGES_NETWORKING"$'\n'
  ENABLE_GNOME_DEFAULTS=1
  ENABLE_SKEL_DOTFILES=1
  ENABLE_MOTD=1
  dedupe_selected_packages
}

select_package_groups() {
  SELECTED_PACKAGES="$PACKAGES_BOOT_CRITICAL"$'\n'

  echo
  echo "Select package groups:"
  echo "1) Dev basics"
  echo "2) Python"
  echo "3) Node.js"
  echo "4) Containers"
  echo "5) CLI productivity"
  echo "6) Build tools"
  echo "7) Networking/SSH"
  echo
  echo "Example: 1 2 4 5"
  echo

  read -r -p "Enter selections: " selections

  for choice in $selections; do
    case "$choice" in
      1) SELECTED_PACKAGES+="$PACKAGES_DEV_BASICS"$'\n' ;;
      2) SELECTED_PACKAGES+="$PACKAGES_PYTHON"$'\n' ;;
      3) SELECTED_PACKAGES+="$PACKAGES_NODE"$'\n' ;;
      4) SELECTED_PACKAGES+="$PACKAGES_CONTAINERS"$'\n' ;;
      5) SELECTED_PACKAGES+="$PACKAGES_CLI_PRODUCTIVITY"$'\n' ;;
      6) SELECTED_PACKAGES+="$PACKAGES_BUILD_TOOLS"$'\n' ;;
      7) SELECTED_PACKAGES+="$PACKAGES_NETWORKING"$'\n' ;;
      *) echo "Ignoring invalid package group: $choice" ;;
    esac
  done

  dedupe_selected_packages
}

select_extras() {
  ENABLE_GNOME_DEFAULTS=0
  ENABLE_SKEL_DOTFILES=0
  ENABLE_MOTD=0
  ENABLE_DEV_CHECK=0

  echo
  echo "Select extras:"
  echo "1) GNOME defaults"
  echo "2) /etc/skel dotfiles"
  echo "3) MOTD"
  echo "4) dev-check utility"
  echo
  echo "Example: 1 2 3 4"
  echo

  read -r -p "Enter selections: " selections

  for choice in $selections; do
    case "$choice" in
      1) ENABLE_GNOME_DEFAULTS=1 ;;
      2) ENABLE_SKEL_DOTFILES=1 ;;
      3) ENABLE_MOTD=1 ;;
      4) ENABLE_DEV_CHECK=1 ;;
      *) echo "Ignoring invalid extra: $choice" ;;
    esac
  done
}

select_build_profile() {
  echo
  echo "Select build profile:"
  echo "1) Minimal"
  echo "2) Developer"
  echo "3) Enterprise"
  echo "4) Custom"
  echo

  read -r -p "Enter choice: " profile_choice

  case "$profile_choice" in
    1)
      apply_profile_minimal
      PROFILE_NAME="minimal"
      ;;
    2)
      apply_profile_developer
      PROFILE_NAME="developer"
      ;;
    3)
      apply_profile_enterprise
      PROFILE_NAME="enterprise"
      ;;
    4)
      PROFILE_NAME="custom"
      select_package_groups
      select_extras
      ;;
    *)
      echo "Invalid choice. Defaulting to Developer profile."
      apply_profile_developer
      PROFILE_NAME="developer"
      ;;
  esac
}

generate_post_block() {
  local post_file="${TEMP_DIR}/post-section.txt"
  : > "$post_file"

  {
    if [[ "$ENABLE_GNOME_DEFAULTS" -eq 1 ]]; then
      cat <<'EOF'
# GNOME defaults
mkdir -p /etc/dconf/db/local.d
mkdir -p /etc/dconf/profile

cat > /etc/dconf/profile/user <<EOD
user-db:user
system-db:local
EOD

cat > /etc/dconf/db/local.d/00-feddev <<EOD
[org/gnome/desktop/interface]
color-scheme='prefer-dark'
clock-show-weekday=true

[org/gnome/nautilus/preferences]
show-hidden-files=true
default-folder-viewer='list-view'

[org/gnome/desktop/peripherals/touchpad]
tap-to-click=true
EOD

dconf update

EOF
    fi

    if [[ "$ENABLE_MOTD" -eq 1 ]]; then
      cat <<'EOF'
# MOTD
cat > /etc/motd <<EOD
FedDev Custom Fedora ISO
Built with the Interactive ISO Builder
EOD

EOF
    fi

    if [[ "$ENABLE_SKEL_DOTFILES" -eq 1 ]]; then
      cat <<'EOF'
# /etc/skel dotfiles
cat > /etc/skel/.bashrc <<'EOD'
EOF

      if [[ "$ENABLE_MOTD" -eq 1 ]]; then
        echo "cat /etc/motd"
      fi

      cat <<'EOF'
alias ll='ls -lah'
alias gs='git status'
alias gp='git pull'
alias dc='dev-check'

if [ -x /usr/local/bin/dev-check ]; then
  echo "Run 'dev-check' or 'dc' to verify installed developer tools."
fi
EOD

cat > /etc/skel/.gitconfig <<'EOD'
[init]
    defaultBranch = main
[pull]
    rebase = false
EOD

cat > /etc/skel/.vimrc <<'EOD'
set number
syntax on
set tabstop=4
set shiftwidth=4
set expandtab
EOD

EOF
    fi

    if [[ "$ENABLE_DEV_CHECK" -eq 1 ]]; then
      cat <<'EOF'
# dev-check
cat > /usr/local/bin/dev-check <<'EOD'
#!/usr/bin/env bash
echo "=== Dev Tool Check ==="
command -v git >/dev/null 2>&1 && git --version || echo "git: not installed"
command -v node >/dev/null 2>&1 && node --version || echo "node: not installed"
command -v npm >/dev/null 2>&1 && npm --version || echo "npm: not installed"
command -v python3 >/dev/null 2>&1 && python3 --version || echo "python3: not installed"
command -v podman >/dev/null 2>&1 && podman --version || echo "podman: not installed"
command -v rg >/dev/null 2>&1 && rg --version | head -n1 || echo "ripgrep: not installed"
command -v fzf >/dev/null 2>&1 && fzf --version || echo "fzf: not installed"
EOD

chmod +x /usr/local/bin/dev-check

EOF
    fi
  } > "$post_file"

  echo "$post_file"
}

create_template_from_base() {
  if [[ ! -f "$BASE_KS" ]]; then
    echo "ERROR: Base KS not found: $BASE_KS"
    return 1
  fi

  python3 - "$BASE_KS" "$TEMPLATE_KS" <<'PY'
import sys
from pathlib import Path

base_path = Path(sys.argv[1])
template_path = Path(sys.argv[2])

text = base_path.read_text()

pkg_start = text.find("%packages")
if pkg_start == -1:
    raise SystemExit("Could not find %packages block in base KS")

pkg_end = text.find("%end", pkg_start)
if pkg_end == -1:
    raise SystemExit("Could not find %end for %packages block")

text = text[:pkg_end] + "### CUSTOM_PACKAGES ###\n" + text[pkg_end:]
text += "\n%post\n### CUSTOM_POST ###\n%end\n"

template_path.write_text(text)
PY

  echo "Template created:"
  echo "  $TEMPLATE_KS"
}

generate_kickstart() {
  if [[ ! -f "$TEMPLATE_KS" ]]; then
    echo "ERROR: Template KS not found: $TEMPLATE_KS"
    echo "Run Setup mode first."
    return 1
  fi

  local post_file packages_file
  post_file="$(generate_post_block)"
  packages_file="${TEMP_DIR}/packages-section.txt"

  printf "%s\n" "$SELECTED_PACKAGES" > "$packages_file"

  python3 - "$TEMPLATE_KS" "$GENERATED_KS" "$packages_file" "$post_file" <<'PY'
import sys
from pathlib import Path

template_path = Path(sys.argv[1])
output_path = Path(sys.argv[2])
packages_path = Path(sys.argv[3])
post_path = Path(sys.argv[4])

template = template_path.read_text()
packages = packages_path.read_text().rstrip() + "\n"
post = post_path.read_text().rstrip() + "\n"

template = template.replace("### CUSTOM_PACKAGES ###", packages)
template = template.replace("### CUSTOM_POST ###", post)

output_path.write_text(template)
PY

  echo "Generated Kickstart:"
  echo "  $GENERATED_KS"
}

validate_required_files() {
  local ok=1

  if [[ ! -f "$BASE_ISO" ]]; then
    echo "ERROR: Base ISO not found:"
    echo "  $BASE_ISO"
    ok=0
  fi

  if [[ ! -f "$BASE_KS" ]]; then
    echo "ERROR: Flattened base KS not found:"
    echo "  $BASE_KS"
    ok=0
  fi

  if [[ ! -f "$TEMPLATE_KS" ]]; then
    echo "ERROR: Template KS not found:"
    echo "  $TEMPLATE_KS"
    ok=0
  fi

  if [[ "$ok" -eq 0 ]]; then
    echo
    echo "Run Setup mode first."
    return 1
  fi

  return 0
}

list_iso_files() {
  find "$BUILDS_DIR" -mindepth 2 -maxdepth 2 -type f -name "*.iso" | sort
}

print_build_list() {
  mapfile -t ISO_LIST < <(list_iso_files)

  if [[ "${#ISO_LIST[@]}" -eq 0 ]]; then
    echo "No ISO builds found."
    return 1
  fi

  echo
  echo "Available ISO builds:"
  local i=1
  for iso in "${ISO_LIST[@]}"; do
    echo "$i) $iso"
    ((i++))
  done

  return 0
}

select_iso_from_list() {
  mapfile -t ISO_LIST < <(list_iso_files)

  if [[ "${#ISO_LIST[@]}" -eq 0 ]]; then
    echo "No ISO builds found."
    return 1
  fi

  echo
  echo "Available ISO builds:"
  local i=1
  for iso in "${ISO_LIST[@]}"; do
    echo "$i) $iso"
    ((i++))
  done
  echo

  local choice
  read -r -p "Select ISO number: " choice

  if ! [[ "$choice" =~ ^[0-9]+$ ]]; then
    echo "Invalid selection."
    return 1
  fi

  if (( choice < 1 || choice > ${#ISO_LIST[@]} )); then
    echo "Selection out of range."
    return 1
  fi

  SELECTED_ISO="${ISO_LIST[$((choice - 1))]}"
  return 0
}

run_setup_mode() {
  print_header
  echo "Running setup mode..."
  echo

  validate_build_tools
  ensure_dirs

  if [[ ! -d "$KICKSTARTS_REPO/.git" ]]; then
    echo "Cloning fedora-kickstarts..."
    git clone https://pagure.io/fedora-kickstarts.git "$KICKSTARTS_REPO"
  else
    echo "fedora-kickstarts already exists. Updating..."
    git -C "$KICKSTARTS_REPO" fetch --all --tags
  fi

  echo "Checking out branch: $FEDORA_BRANCH"
  git -C "$KICKSTARTS_REPO" checkout "$FEDORA_BRANCH"
  git -C "$KICKSTARTS_REPO" pull --ff-only || true

  echo
  echo "Flattening base kickstart..."
  ksflatten \
    --config "$FEDORA_KS_SOURCE" \
    -o "$BASE_KS"

  echo
  echo "Creating template kickstart..."
  create_template_from_base

  echo
  echo "Setup validation:"
  [[ -f "$BASE_KS" ]] && echo "OK: Flattened base KS exists"
  [[ -f "$TEMPLATE_KS" ]] && echo "OK: Template KS exists"
  [[ -f "$BASE_ISO" ]] && echo "OK: Base ISO exists" || echo "WARNING: Base ISO not found: $BASE_ISO"

  echo
  echo "Setup completed."
}

run_build_mode() {
  print_header
  echo "Running build mode..."
  echo

  validate_build_tools
  ensure_dirs
  validate_required_files || return 1

  local version iso_name ram cpus image_size
  local result_dir log_file
  local do_cleanup=0
  local manage_selinux=0
  local selinux_changed=0
  PROFILE_NAME="custom"

  read -r -p "Enter version (e.g. v1.5): " version
  read -r -p "Enter ISO filename (e.g. fedora-dev-gnome-v1.5.iso): " iso_name
  # Ensure .iso extension
  if [[ "$iso_name" != *.iso ]]; then
    iso_name="${iso_name}.iso"
  fi
  read -r -p "Enter RAM in MB [8192]: " ram
  read -r -p "Enter number of vCPUs [4]: " cpus
  read -r -p "Enter image size in MB [20480]: " image_size

  ram="${ram:-8192}"
  cpus="${cpus:-4}"
  image_size="${image_size:-20480}"

  result_dir="${BUILDS_DIR}/gnome-${version}"
  log_file="${LOGS_DIR}/gnome-${version}.log"

  select_build_profile
  generate_kickstart

  echo
  echo "Build summary:"
  echo "Version:      $version"
  echo "ISO name:     $iso_name"
  echo "Profile:      $PROFILE_NAME"
  echo "Result dir:   $result_dir"
  echo "Log file:     $log_file"
  echo "RAM:          $ram"
  echo "vCPUs:        $cpus"
  echo "Image size:   $image_size"
  echo

  if confirm "Run cleanup before build?"; then
    do_cleanup=1
  fi

  if confirm "Temporarily set SELinux to permissive during build?"; then
    manage_selinux=1
  fi

  if ! confirm "Proceed with build?"; then
    echo "Build cancelled."
    return 0
  fi

  if [[ "$do_cleanup" -eq 1 ]]; then
    cleanup_build_artifacts
    generate_kickstart
  fi

  if [[ -d "$result_dir" ]]; then
    echo "Removing existing result directory..."
    rm -rf "$result_dir"
  fi

  if [[ "$manage_selinux" -eq 1 ]]; then
    set_selinux_permissive
    selinux_changed=1
  fi

  set +e
  systemd-inhibit --what=idle:sleep \
  sudo livemedia-creator \
    --make-iso \
    --iso="$BASE_ISO" \
    --ks="$GENERATED_KS" \
    --resultdir="$result_dir" \
    --logfile="$log_file" \
    --project="$PROJECT_NAME" \
    --volid="$VOLID" \
    --iso-only \
    --iso-name="$iso_name" \
    --releasever="$RELEASEVER" \
    --ram="$ram" \
    --vcpus="$cpus" \
    --image-size="$image_size" \
    --no-virt
  local build_status=$?
  set -e

  if [[ "$selinux_changed" -eq 1 ]]; then
    restore_selinux_enforcing
  fi

  echo
  if [[ "$build_status" -eq 0 ]]; then
    echo "Build completed successfully."
  else
    echo "Build failed with exit code: $build_status"
  fi

  echo "Generated KS: $GENERATED_KS"
  echo "Result dir:   $result_dir"
  echo "Log file:     $log_file"

  if [[ -d "$result_dir" ]]; then
    echo
    ls -lah "$result_dir" || true
  fi

  if [[ "$build_status" -eq 0 ]]; then
    if confirm "Test this ISO now in QEMU?"; then
      qemu-system-x86_64 \
        -enable-kvm \
        -m 4096 \
        -cpu host \
        -smp 4 \
        -cdrom "$result_dir/$iso_name"
    fi
  fi

  return "$build_status"
}

run_test_mode() {
  print_header
  echo "Running Test ISO mode..."
  echo

  validate_build_tools
  ensure_dirs

  if ! select_iso_from_list; then
    return 1
  fi

  local ram cpus
  read -r -p "RAM in MB [4096]: " ram
  read -r -p "vCPUs [4]: " cpus

  ram="${ram:-4096}"
  cpus="${cpus:-4}"

  echo
  echo "Starting QEMU with:"
  echo "$SELECTED_ISO"
  echo

  qemu-system-x86_64 \
    -enable-kvm \
    -m "$ram" \
    -cpu host \
    -smp "$cpus" \
    -cdrom "$SELECTED_ISO"
}

run_list_builds_mode() {
  print_header
  echo "Listing available builds..."
  echo
  print_build_list || true
}

run_clean_mode() {
  print_header
  cleanup_build_artifacts
}

main_menu() {
  while true; do
    print_header
    echo "Select mode:"
    echo "1) Setup"
    echo "2) Build"
    echo "3) Test ISO"
    echo "4) List Builds"
    echo "5) Clean"
    echo "6) Exit"
    echo

    read -r -p "Enter choice: " choice

    case "$choice" in
      1)
        run_setup_mode
        pause
        ;;
      2)
        run_build_mode || true
        pause
        ;;
      3)
        run_test_mode || true
        pause
        ;;
      4)
        run_list_builds_mode
        pause
        ;;
      5)
        run_clean_mode
        pause
        ;;
      6)
        echo "Goodbye."
        exit 0
        ;;
      *)
        echo "Invalid choice."
        pause
        ;;
    esac
  done
}

main_menu
