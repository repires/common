#!/usr/bin/env bash
# DX-Next full health check — automated checks + readable status summary.
# Usage: ./scripts/dx-next-health.sh
#        DX_HEALTH_SKIP_DOCKER_PULL=1 ./scripts/dx-next-health.sh   # skip hello-world pulls

set -u

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERIFY="${REPO_ROOT}/scripts/dx-next-verify.sh"

echo "══════════════════════════════════════════════════════════════"
echo "  DX-Next health check — $(date '+%Y-%m-%d %H:%M:%S %Z')"
echo "══════════════════════════════════════════════════════════════"
echo ""

if [ -x "$VERIFY" ]; then
    echo "── Automated checks (dx-next-verify.sh) ──"
    bash "$VERIFY" || VERIFY_EXIT=$?
    VERIFY_EXIT=${VERIFY_EXIT:-0}
    echo ""
else
    echo "WARN: ${VERIFY} not found; skipping automated checks."
    VERIFY_EXIT=1
fi

section() { echo ""; echo "── $1 ──"; }

section "Services"
printf '  libvirt-dx=%s  dockerd-dx=%s  incus-dx=%s  cockpit-dx=%s  user-docker=%s\n' \
    "$(systemctl is-active libvirt-dx 2>/dev/null || echo missing)" \
    "$(systemctl is-active dockerd-dx 2>/dev/null || echo missing)" \
    "$(systemctl is-active incus-dx 2>/dev/null || echo missing)" \
    "$(systemctl is-active cockpit-dx 2>/dev/null || echo missing)" \
    "$(systemctl --user is-active docker.service 2>/dev/null || echo missing)"

section "Groups (reboot if libvirt/docker/incus missing from id)"
echo "  groups: $(groups)"
getent group libvirt docker incus-admin 2>/dev/null | sed 's/^/  /' || true

section "Docker contexts"
docker context ls 2>/dev/null | sed 's/^/  /' || echo "  (docker not on PATH)"

section "Virt (libvirt-dx)"
if [ -x "${HOME}/.local/bin/virsh" ]; then
    echo "  virsh uri: $("${HOME}/.local/bin/virsh" uri 2>/dev/null || echo '?')"
    "${HOME}/.local/bin/virsh" net-list --all 2>/dev/null | sed 's/^/  /' || true
    "${HOME}/.local/bin/virsh" list --all 2>/dev/null | sed 's/^/  /' || true
else
    echo "  WARN: ~/.local/bin/virsh missing — run: ./scripts/dx-next-dev.sh debug virt"
fi
if command -v virt-manager >/dev/null && [ -x "${HOME}/.local/bin/virt-manager" ]; then
    echo "  virt-manager: $(command -v virt-manager)"
else
    echo "  virt-manager: $(command -v virt-manager 2>/dev/null || echo 'not on PATH')"
fi
ls -la /run/libvirt-dx/libvirt-sock 2>/dev/null | sed 's/^/  /' || echo "  socket: missing"
ls -la /var/lib/libvirt-dx/images/ 2>/dev/null | head -5 | sed 's/^/  /' || true

section "Incus"
if command -v incus >/dev/null; then
    incus storage list 2>/dev/null | sed 's/^/  /' || true
    incus profile show default 2>/dev/null | grep -E '^(name|devices:|  root:|  eth0:)' | sed 's/^/  /' || true
    incus list 2>/dev/null | sed 's/^/  /' || true
else
    echo "  incus CLI not on PATH"
fi

section "Cockpit"
if systemctl is-active --quiet cockpit-dx 2>/dev/null; then
    code=$(curl -k -s -o /dev/null -w '%{http_code}' https://localhost:9090/ 2>/dev/null || echo "000")
    echo "  cockpit-dx active — https://localhost:9090/ → HTTP ${code}"
else
    echo "  cockpit-dx not active"
fi

section "DX-Tools (sample)"
for cmd in code lima kind podman-compose; do
    if command -v "$cmd" >/dev/null; then
        echo "  OK  $cmd → $(command -v "$cmd")"
    else
        echo "  --  $cmd not found"
    fi
done

if [ "${DX_HEALTH_SKIP_DOCKER_PULL:-0}" != "1" ]; then
    section "Docker smoke (hello-world)"
    if docker run --rm hello-world >/dev/null 2>&1; then
        echo "  OK  rootfull hello-world"
    else
        echo "  FAIL rootfull hello-world"
        VERIFY_EXIT=1
    fi
    if docker -H "unix:///run/user/$(id -u)/docker.sock" run --rm hello-world >/dev/null 2>&1; then
        echo "  OK  rootless hello-world"
    else
        echo "  FAIL rootless hello-world"
        VERIFY_EXIT=1
    fi
else
    echo ""
    echo "  (skipped docker hello-world — set DX_HEALTH_SKIP_DOCKER_PULL=0 to enable)"
fi

echo ""
echo "══════════════════════════════════════════════════════════════"
if [ "${VERIFY_EXIT:-0}" -eq 0 ]; then
    echo "  Overall: HEALTHY (automated checks passed)"
else
    echo "  Overall: ISSUES DETECTED (see FAIL lines above)"
fi
echo "══════════════════════════════════════════════════════════════"

exit "${VERIFY_EXIT:-0}"
