## v0.11.0 (2026-03-09)

### feat

- Add egress firewall rules for bastion to allow internal SSH, DNS, APT updates, and NTP.
- Harden Traefik security by encrypting the public overlay network, restricting web ingress to the load balancer, adding comprehensive egress firewall rules, and refining Traefik configurations.

## v0.10.0 (2026-03-08)

### feat

- Offload TLS termination and certificate management from Traefik to the Hetzner Load Balancer.

## v0.9.0 (2026-03-08)

### feat

- Implement Traefik and Socket Proxy deployment for edge load balancing and routing in the Swarm cluster.

## v0.8.0 (2026-03-08)

### feat

- Add direct SSH access targets for bastion, manager, and worker nodes via Makefile, and update the contributing guide to reflect these new commands.

## v0.7.0 (2026-03-08)

### feat

- Add Ansible playbooks, roles, and dynamic inventory for Docker Swarm cluster provisioning.

### refactor

- Add database server IP addresses to the `internal_ips` output.

## v0.6.0 (2026-03-08)

### feat

- Implement automatic DNS routing for environments using Hetzner DNS.

## v0.5.0 (2026-03-08)

### feat

- enable dynamic configuration of allowed SSH IPs via GitHub secrets for CI.

## v0.4.0 (2026-03-08)

### feat

- Replace single location variable with a list of locations to distribute resources across multiple data centers.

## v0.3.0 (2026-03-08)

### feat

- Multi Environment Orchestration & Security Verification (#4)

## v0.2.0 (2026-03-07)

### feat

- Terraform State Setup (#3)

## v0.1.3 (2026-03-07)

### build

- Add GitHub Actions Continuous Integration workflow for pre-com… (#2)

## v0.1.2 (2026-03-06)

### docs

- move detailed setup and contribution guidelines from README.md to a new CONTRIBUTING.md file

## v0.1.1 (2026-03-06)

### docs

- add README with Poetry installation and pre-commit hook setup instructions.

## v0.1.0 (2026-03-06)

### feat

- installed pre-commit dependency, including the pre-comit config file for terraform & commitizen

### chore

- linting via precomit rules
- terraform file
- checking precommit

## v0.0.1 (2026-03-06)

### chore

- set up project skeleton and automated versioning (#1)
