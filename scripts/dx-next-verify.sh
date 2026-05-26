#!/usr/bin/env bash
# Verify DX-Next install — safe to run in a terminal (does not close on failure).
# Usage: ./scripts/dx-next-verify.sh

ok=0
fail=0

check() {
    local label=$1
    shift
    if "$@" >/dev/null 2>&1; then
        echo "OK   ${label}"
        ok=$((ok + 1))
    else
        echo "FAIL ${label}"
        fail=$((fail + 1))
    fi
}

echo "=== Services ==="
check "libvirt-dx" systemctl is-active --quiet libvirt-dx
check "dockerd-dx (rootfull)" systemctl is-active --quiet dockerd-dx
check "docker.service (rootless)" systemctl --user is-active --quiet docker.service
check "incus-dx" systemctl is-active --quiet incus-dx
check "cockpit-dx" systemctl is-active --quiet cockpit-dx

echo ""
echo "=== DX config ==="
check "dx-groups.conf" test -f /etc/sysusers.d/dx-groups.conf
check "libvirt-dx quadlet" test -f /etc/containers/systemd/libvirt-dx.container
check "dockerd-dx unit" test -f /etc/systemd/system/dockerd-dx.service
check "rootfull dockerd binary" test -x /usr/local/libexec/dx-next/docker/dockerd
check "incus-dx quadlet" test -f /etc/containers/systemd/incus-dx.container
check "cockpit-dx quadlet" test -f /etc/containers/systemd/cockpit-dx.container

echo ""
echo "=== CLIs ==="
check "code" command -v code
check "lima" command -v lima
check "kind" command -v kind
check "ydotool" command -v ydotool
check "podman-compose" command -v podman-compose
check "podman-tui" command -v podman-tui
check "podman" command -v podman
check "incus" command -v incus

echo ""
echo "=== Docker ==="
check "docker info (rootfull)" docker -H unix:///run/docker.sock info
check "docker info (rootless)" docker -H "unix:///run/user/$(id -u)/docker.sock" info

echo ""
echo "=== Virt ergonomics ==="
check "virt ISO directory" test -d /var/lib/libvirt-dx/images
check "virsh wrapper" bash -c 'test -x "${HOME}/.local/bin/virsh" && grep -q dx-next-virsh-wrapper "${HOME}/.local/bin/virsh"'
check "virt-manager wrapper" bash -c 'test -x "${HOME}/.local/bin/virt-manager" && grep -q dx-next-virt-manager-wrapper "${HOME}/.local/bin/virt-manager"'
check "virsh via wrapper" "${HOME}/.local/bin/virsh" list
check "libvirt default network" bash -c '"${HOME}/.local/bin/virsh" net-info default 2>/dev/null | grep -qE "^Active:[[:space:]]+yes"'
check "virt-manager autoconnect" bash -c 'flatpak run --command=gsettings org.virt_manager.virt-manager get org.virt-manager.virt-manager.connections autoconnect | grep -q libvirt-dx/libvirt-sock'

echo ""
echo "=== Quick functional ==="
check "podman ps" podman ps
check "incus list" incus list
check "incus storage pool" incus storage info default
check "incus default root disk" bash -c 'incus profile show default | grep -q "^  root:"'
check "incusbr0 firewalld" bash -c 'if ! ip link show incusbr0 >/dev/null 2>&1; then exit 0; fi; command -v firewall-cmd >/dev/null 2>&1 || exit 0; firewall-cmd --permanent --zone=trusted --query-interface=incusbr0'

echo ""
printf "Result: %s passed, %s failed\n" "$ok" "$fail"

# Only pause when something failed (avoids hanging on success); set DX_VERIFY_PAUSE=1 to always pause.
if [ "$fail" -gt 0 ] || [ "${DX_VERIFY_PAUSE:-0}" = "1" ]; then
    if [ -t 0 ] && [ -t 1 ]; then
        read -r -p "Press Enter to close..." _ </dev/tty 2>/dev/null || read -r -p "Press Enter to close..." _
    fi
fi

exit "$fail"
