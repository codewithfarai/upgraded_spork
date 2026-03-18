## v0.19.0 (2026-03-18)

### feat

- Add Authentik provider and resources to integrate with Traefik.
- Integrate Authentik with Terraform to manage the Traefik application, including API token provisioning via Ansible.
- Add Authentik Terraform provider and configure its API token and URL via Ansible.

## v0.18.0 (2026-03-15)

### feat

- Remove Authentik's Redis dependency, configure Redis memory limits, and enhance node provisioning with improved hardening and SSH keyscan.

## v0.17.0 (2026-03-15)

### feat

- Implement a dedicated 'provision' user for SSH access and disable direct root login for enhanced security and privilege escalation.

## v0.16.3 (2026-03-15)

### docs

- Add instructions for trusting host keys and a deployment flow summary to CONTRIBUTING.md.

## v0.16.2 (2026-03-15)

### refactor

- Enable strict SSH host key checking by removing related overrides and adding a Makefile target for host key management.

## v0.16.1 (2026-03-15)

### refactor

- Remove SUPERUSER privilege for the authentik user and change replication host authentication to md5.

## v0.16.0 (2026-03-15)

### feat

- Enforce SSL for PostgreSQL connections in Authentik and database HA.

## v0.15.1 (2026-03-15)

### fix

- Configure Authentik to prefer PostgreSQL SSL and enable SSL for the database.

## v0.15.0 (2026-03-14)

### feat

- Add tasks to wait for PostgreSQL master readiness via pgpool and idempotently create the Authentik database.

## v0.14.0 (2026-03-14)

### feat

- Configure PostgreSQL SSL, enhance HAProxy health checks and DNS resolution, update poetry lock, and ignore new authentication and script files.
- Extract Authentik's PostgreSQL HA cluster into a new `database_ha` role and stack, and reduce default node counts.

## v0.13.1 (2026-03-10)

### fix

- Use traefik.swarm.network instead of traefik.docker.network for the authentik-outpost service.

### chore

- better ssh_commands & using -system instead of -p
- replaced curl

## v0.13.0 (2026-03-10)

### feat

- Enhance Authentik database resilience with Patroni integration, increased replicas, and improved HAProxy configuration, and add a database SSH helper.

## v0.12.0 (2026-03-09)

### feat

- Implement Authentik for centralized authentication and integrate it with Traefik, alongside network security enhancements.
- Add Authentik SSO deployment, including secret generation, Ansible role, and Traefik integration.

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
