#!/bin/bash
# Node initialization script - SSH Hardening & Host Security Only
set -e

# Variables passed from Terraform
NODE_TYPE="${node_type}"
NODE_INDEX="${node_index}"
MANAGER_IP="${manager_ip}"
NETWORK_GATEWAY="${network_gateway}"
WORKER_COUNT="${worker_count}"
ENABLE_HARDENING="${enable_hardening}"

# 1. Provision dedicated 'provision' user IMMEDIATELY (Before network wait)
# This ensures we can always SSH in to debug even if internet/NAT is not up yet.
if [[ "$ENABLE_HARDENING" == "true" ]]; then
    if ! id "provision" &>/dev/null; then
        echo "Creating 'provision' user and preparing SSH access.."
        useradd -m -s /bin/bash provision
        echo "provision ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/provision
        chmod 0440 /etc/sudoers.d/provision

        # Copy authorized keys from root
        mkdir -p /home/provision/.ssh
        cp /root/.ssh/authorized_keys /home/provision/.ssh/
        chown -R provision:provision /home/provision/.ssh
        chmod 700 /home/provision/.ssh
        chmod 600 /home/provision/.ssh/authorized_keys
    fi
fi

# Permanent DNS Configuration (Required for Private Nodes)
echo "Configuring persistent DNS..."
sed -i 's/#DNS=/DNS=185.12.64.2 185.12.64.1/' /etc/systemd/resolved.conf
systemctl restart systemd-resolved

# Default Route via Network Gateway (Internal Nodes Only)
if [[ "$NODE_TYPE" != "edge" && "$NODE_TYPE" != "bastion" ]]; then
    echo "Setting default route via $NETWORK_GATEWAY..."
    # Add route if it doesn't exist
    ip route add default via "$NETWORK_GATEWAY" || true

    # Wait for NAT Gateway/Connectivity (Wait until we can reach an external nameserver)
    echo "Waiting for NAT Gateway (Edge) to provide internet access..."
    until curl -s -m 2 https://1.1.1.1 >/dev/null 2>&1; do
        echo "Internet not reachable yet. Sleeping 5s.."
        sleep 5
    done
    echo "✅ Internet is reachable via NAT. Proceeding with init..."
fi

# NAT Gateway Setup (Edge Nodes Only)
if [[ "$NODE_TYPE" == "edge" ]]; then
    echo "Configuring NAT Gateway on Edge node..."
    # Enable IP forwarding
    echo 1 > /proc/sys/net/ipv4/ip_forward
    # Persistent IP forwarding
    sed -i 's/#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/' /etc/sysctl.conf

    # Setup Masquerading - allow the entire private network
    iptables -t nat -A POSTROUTING -s '10.0.0.0/16' -o eth0 -j MASQUERADE

    # Install iptables-persistent to keep rules across reboots
    export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y iptables-persistent
fi

# Update and install base packages
apt-get update
apt-get dist-upgrade -y
apt-get install -y python3 python3-pip net-tools curl jq

# Configure Docker MTU and logging to prevent hangs and disk exhaustion
mkdir -p /etc/docker
cat > /etc/docker/daemon.json << EOL
{
  "mtu": 1450,
  "iptables": true,
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
EOL

# Extract fail2ban config values from the JSON-like string using jq
FAIL2BAN_CONFIG_JSON='${fail2ban_config}'
FAIL2BAN_BANTIME=$(echo "$FAIL2BAN_CONFIG_JSON" | jq -r '.bantime')
FAIL2BAN_FINDTIME=$(echo "$FAIL2BAN_CONFIG_JSON" | jq -r '.findtime')
FAIL2BAN_MAXRETRY=$(echo "$FAIL2BAN_CONFIG_JSON" | jq -r '.maxretry')
FAIL2BAN_SSH_MAXRETRY=$(echo "$FAIL2BAN_CONFIG_JSON" | jq -r '.ssh_maxretry')



# Configure hosts file for internal DNS
# Management nodes
echo "$MANAGER_IP manager-1" >> /etc/hosts

# Worker nodes in Application subnet (10.0.3.30+)
for i in $(seq 1 $WORKER_COUNT); do
    echo "10.0.3.$((29 + i)) worker-$i" >> /etc/hosts
done

# 2. Hardening & Fail2Ban
if [[ "$ENABLE_HARDENING" == "true" ]]; then
    echo "Applying SSH security hardening..."
    # SSH Configuration - Prevent brute force and unauthorized access
    sed -i 's/^#*PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
    sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
    sed -i 's/^#*PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config
    sed -i 's/^#*PermitEmptyPasswords.*/PermitEmptyPasswords no/' /etc/ssh/sshd_config
    sed -i 's/^#*X11Forwarding.*/X11Forwarding no/' /etc/ssh/sshd_config
    sed -i 's/^#*MaxAuthTries.*/MaxAuthTries 3/' /etc/ssh/sshd_config
    sed -i 's/^#*ClientAliveInterval.*/ClientAliveInterval 300/' /etc/ssh/sshd_config
    sed -i 's/^#*ClientAliveCountMax.*/ClientAliveCountMax 2/' /etc/ssh/sshd_config

    # Restart SSH to apply changes
    systemctl restart ssh
    echo "SSH hardening applied successfully"

    echo "Installing fail2ban for SSH protection..."
    apt-get install -y fail2ban python3-systemd

    # Configure fail2ban with SSH protection
    # We use 'backend = auto' to let fail2ban decide between polling and systemd
    cat > /etc/fail2ban/jail.local << EOL
[DEFAULT]
bantime = $FAIL2BAN_BANTIME
findtime = $FAIL2BAN_FINDTIME
maxretry = $FAIL2BAN_MAXRETRY
backend = auto

[sshd]
enabled = true
port = ssh
maxretry = $FAIL2BAN_SSH_MAXRETRY
EOL

    # Enable and start fail2ban service
    systemctl daemon-reload
    systemctl enable fail2ban
    systemctl restart fail2ban

    # Wait for fail2ban to be fully operational
    echo "Waiting for Fail2Ban to start..."
    sleep 5


    # Verify fail2ban is working for SSH
    echo "Fail2Ban SSH protection status:"
    if fail2ban-client status sshd >/dev/null 2>&1; then
        echo "✅ Fail2Ban SSH protection is ACTIVE"
        fail2ban-client status sshd | grep -E "(Status|Currently banned)"

        # Create completion marker for Ansible
        touch /tmp/fail2ban-ready
        echo "FAIL2BAN_STATUS=active" >> /tmp/node-info
    else
        echo "⚠ Fail2Ban SSH protection failed to start"
        systemctl status fail2ban --no-pager -l
        echo "FAIL2BAN_STATUS=failed" >> /tmp/node-info
    fi
fi

# Kernel hardening - Host-level security
if [[ "$ENABLE_HARDENING" == "true" ]]; then
    echo "Applying kernel-level security hardening..."

    # Use a high-priority conf file to ensure settings stick (overrides cloud-init/hetzner defaults)
    cat > /etc/sysctl.d/99-hardened.conf << 'EOL'
# IP Spoofing protection
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# Ignore ICMP redirects
net.ipv4.conf.all.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0

# Ignore send redirects
net.ipv4.conf.all.send_redirects = 0

# Disable source packet routing
net.ipv4.conf.all.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0

# Log Martians
net.ipv4.conf.all.log_martians = 1

# Ignore ICMP ping requests
net.ipv4.icmp_echo_ignore_broadcasts = 1

# Ignore Directed pings
net.ipv4.icmp_ignore_bogus_error_responses = 1

# TCP/IP parameters
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_syn_backlog = 2048
net.ipv4.tcp_synack_retries = 2
net.ipv4.tcp_syn_retries = 5

# Redis performance & reliability
vm.overcommit_memory = 1

# IP forwarding for Docker (required)
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
EOL

    # Apply kernel settings - forcing refresh from all config files
    sysctl --system
    echo "Kernel hardening completed successfully"

    # Install and configure unattended-upgrades for automatic security patching
    echo "Configuring automated security updates..."
    apt-get install -y unattended-upgrades

    # Ensure it's enabled and configured to only install security updates
    cat > /etc/apt/apt.conf.d/20auto-upgrades << EOL
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOL
    echo "Automated security updates enabled successfully"
fi

# Create final completion markers for Ansible
touch /tmp/security-hardening-started
echo "NODE_TYPE=$NODE_TYPE" > /tmp/node-info
echo "SECURITY_HARDENING=$ENABLE_HARDENING" >> /tmp/node-info
echo "INIT_COMPLETED=$(date -Iseconds)" >> /tmp/node-info

# Final marker for Ansible to know everything is ready
touch /tmp/node-init-complete

# Log initialization complete
echo "=========================================="
echo "Node initialization completed successfully"
echo "Type: $NODE_TYPE, Index: $NODE_INDEX"
echo "SSH Hardening: $ENABLE_HARDENING"
echo "Fail2Ban Protection: $ENABLE_HARDENING"
echo "Initialization timestamp: $(date -Iseconds)"
echo "=========================================="
