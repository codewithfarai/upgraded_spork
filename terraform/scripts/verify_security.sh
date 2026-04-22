#!/bin/bash
# Verify Security Hardening Steps & NAT Connectivity
# Checks SSH config, Fail2Ban status, Kernel parameters, and outbound IP

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

failed=0
EXPECTED_NAT_IP=$1

log_pass() {
    echo -e "${GREEN}[PASS]${NC} $1"
}

log_fail() {
    echo -e "${RED}[FAIL]${NC} $1"
    failed=1
}

echo "Starting Security Verification on $(hostname)..."
echo "Target Node: $(hostname) ($(hostname -I | awk '{print $1}'))"

# Wait for node initialization to complete
echo "Waiting for node initialization marker (/tmp/node-init-complete)..."
timeout=300
elapsed=0
while [[ ! -f /tmp/node-init-complete ]] && [[ $elapsed -lt $timeout ]]; do
    sleep 5
    elapsed=$((elapsed + 5))
done

if [[ ! -f /tmp/node-init-complete ]]; then
    log_fail "Node initialization timed out after 5 minutes."
    exit 1
fi

# 1. SSH Configuration
echo "------------------------------------------------"
echo "Checking SSH Configuration..."
SSH_CONFIG="/etc/ssh/sshd_config"

check_ssh_param() {
    param=$1
    expected=$2
    if grep -qE "^${param}[[:space:]]+${expected}" "$SSH_CONFIG"; then
        log_pass "SSH: $param is set to $expected"
    else
        found=$(grep -E "^${param}" "$SSH_CONFIG" || echo "NOT FOUND")
        log_fail "SSH: $param is NOT set to $expected (Found: $found)"
    fi
}

check_ssh_param "PermitRootLogin" "no"
check_ssh_param "PasswordAuthentication" "no"
check_ssh_param "PubkeyAuthentication" "yes"
check_ssh_param "PermitEmptyPasswords" "no"
check_ssh_param "X11Forwarding" "no"
check_ssh_param "MaxAuthTries" "3"

# 2. Fail2Ban Status
echo "------------------------------------------------"
echo "Checking Fail2Ban Status..."
if systemctl is-active --quiet fail2ban; then
    log_pass "Fail2Ban service is active"
else
    log_fail "Fail2Ban service is NOT active"
fi

# Debug info: show active jails
echo "Active Fail2Ban Jails:"
sudo fail2ban-client status | grep "Jail list" || echo "No active jails found"

if sudo fail2ban-client status sshd >/dev/null 2>&1; then
    log_pass "Fail2Ban jail 'sshd' is active"
else
    log_fail "Fail2Ban jail 'sshd' is NOT active"
    echo "Last logs for fail2ban:"
    sudo tail -n 20 /var/log/fail2ban.log 2>/dev/null || sudo journalctl -u fail2ban --no-pager -n 20
fi

# 3. Kernel Hardening
echo "------------------------------------------------"
echo "Checking Kernel Hardening Parameters...."

check_sysctl() {
    param=$1
    expected=$2
    current=$(sysctl -n "$param" 2>/dev/null)
    if [[ "$current" == "$expected" ]]; then
        log_pass "Kernel: $param is $expected"
    else
        log_fail "Kernel: $param is $current (Expected: $expected)"
    fi
}

check_sysctl "net.ipv4.conf.all.rp_filter" "1"
check_sysctl "net.ipv4.conf.all.accept_redirects" "0"
check_sysctl "net.ipv4.conf.all.send_redirects" "0"
check_sysctl "net.ipv4.icmp_echo_ignore_broadcasts" "1"
check_sysctl "net.ipv4.tcp_syncookies" "1"
check_sysctl "vm.overcommit_memory" "1"

# 4. NAT Gateway Connectivity (for internal nodes)
if [[ "$(hostname)" != *"bastion"* && "$(hostname)" != *"edge"* ]]; then
    echo "------------------------------------------------"
    echo "Checking NAT Gateway / Outbound IP..."

    # Try multiple IP services with retries to avoid rate limits when multiple nodes verify simultaneously
    CURRENT_IP=""
    for service in "https://ipv4.icanhazip.com" "https://ifconfig.me/ip" "https://api.ipify.org"; do
        CURRENT_IP=$(curl -4s --connect-timeout 5 "$service" | tr -d '\n')
        if [[ -n "$CURRENT_IP" ]]; then
            break
        fi
        sleep 2
    done

    if [[ -n "$EXPECTED_NAT_IP" ]]; then
        # Check if current IP is in the list of expected IPs
        found_match=0
        for expected in $EXPECTED_NAT_IP; do
            if [[ "$CURRENT_IP" == "$expected" ]]; then
                found_match=1
                break
            fi
        done

        if [[ $found_match -eq 1 ]]; then
            log_pass "NAT: Outbound IP correctly matches one of the Edge IPs ($CURRENT_IP)"
        else
            if [[ -z "$CURRENT_IP" ]]; then
                log_fail "NAT: Could not reach any external IP service (Wait for DNS/NAT to stabilize)"
            else
                log_fail "NAT: Outbound IP ($CURRENT_IP) DOES NOT match any Edge IPs ($EXPECTED_NAT_IP)"
            fi
        fi
    else
        if [[ -z "$CURRENT_IP" ]]; then
            log_fail "NAT: Could not reach external IP service"
        else
            log_pass "NAT: Internet reachable (Outbound IP: $CURRENT_IP)"
        fi
    fi
fi

echo "------------------------------------------------"
if [[ $failed -eq 0 ]]; then
    echo -e "${GREEN}VERIFICATION PASSED: All security checks passed.${NC}"
    exit 0
else
    echo -e "${RED}VERIFICATION FAILED: One or more checks failed.${NC}"
    exit 1
fi
