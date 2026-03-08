#!/usr/bin/env python3
"""Generate Ansible JSON inventory from Terraform outputs."""

import json
import sys
import os


def flatten_ips(data, key):
    """Flatten nested IP lists [[ip1], [ip2]] -> [ip1, ip2]"""
    try:
        raw = data.get("internal_ips", {}).get("value", {}).get(key, [])
        if raw and isinstance(raw[0], list):
            return [ip for sublist in raw for ip in sublist]
        return raw
    except Exception:
        return []


def build_inventory(data, env, ssh_key_path):
    bastion_ip = data.get("bastion_public_ip", {}).get("value", "")

    if not bastion_ip:
        return {"_meta": {"hostvars": {}}}

    managers = flatten_ips(data, "managers")
    workers = flatten_ips(data, "workers")
    edge = flatten_ips(data, "edge")
    database = flatten_ips(data, "database")

    # StrictHostKeyChecking=no on BOTH the outer (target) and inner (bastion) connections
    proxy_cmd = (
        "-o StrictHostKeyChecking=no "
        "-o UserKnownHostsFile=/dev/null "
        f"-o ProxyCommand='ssh -W %h:%p -q -i {ssh_key_path} "
        f"-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "
        f"root@{bastion_ip}'"
    )

    all_vars = {
        "ansible_user": "root",
        "ansible_ssh_common_args": proxy_cmd,
        "ansible_ssh_private_key_file": ssh_key_path,
        "target_env": env,
    }

    hostvars = {}
    for ip in managers:
        hostvars[ip] = {"swarm_role": "manager"}
    for ip in workers:
        hostvars[ip] = {"swarm_role": "worker"}
    for ip in edge:
        hostvars[ip] = {"swarm_role": "worker"}
    for ip in database:
        hostvars[ip] = {"swarm_role": "worker"}

    return {
        "managers": {"hosts": managers},
        "workers": {"hosts": workers},
        "edge": {"hosts": edge},
        "database": {"hosts": database},
        "docker_nodes": {
            "children": ["managers", "workers", "edge", "database"]
        },
        "all": {"vars": all_vars},
        "_meta": {"hostvars": hostvars},
    }


if __name__ == "__main__":
    env = os.environ.get("ENV", "dev")
    ssh_key_path = os.environ.get("SSH_KEY_PATH", "")

    data = json.load(sys.stdin)
    inventory = build_inventory(data, env, ssh_key_path)
    print(json.dumps(inventory, indent=2))
