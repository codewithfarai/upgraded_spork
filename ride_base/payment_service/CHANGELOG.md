## payment_service-v0.2.0 (2026-04-04)

### feat

- integrate Resend API to send payment confirmation emails via webhooks
- Prevent multiple active subscriptions during checkout
- Add payment service API documentation and implement subscription management features
- add default self-signed certificate key pair to OIDC provider configuration
- configure Authentik SMTP, restrict proxy access to admins, and implement custom Google/email enrollment flows
- migrate RideBase to OAuth2 provider, add Google social login, and update domain references to ridebase.tech
- add RabbitMQ monitoring dashboard and scrape configuration to the monitoring stack
- add etcd persistence, update monitoring dashboards, and migrate prometheus to dynamic swarm service discovery
- add Docker Hub authentication to mitigate pull rate limits
- Implement comprehensive monitoring for the database stack, including Prometheus scrape jobs, database exporters, Grafana dashboards, and alert rules.
- Configure Authentik HTTP listen address and trusted proxies, and include the host URL in outpost updates.
- Adjust HighContainerRestarts alert to trigger faster by reducing its evaluation window and duration.
- Introduce a comprehensive bootstrap script for environment setup, integrate the Ridebase application into Authentik, and enhance deployment Makefiles with argument passing and a new Ansible cleanup target.
- add Docker Swarm task desired state and network filtering to Prometheus scrape configurations.
- Add rabbitmq_auth_backend_oauth2 to enabled plugins.
- configure rabbitmq haproxy and mqtt listener
- Add RabbitMQ service to the database stack, including HAProxy, Traefik, Prometheus, and Authentik integration, and update SSH proxy command to use environment-specific known hosts.
- Implement RabbitMQ in the database HA stack with Prometheus monitoring and Authentik integration, and add PostgreSQL and Redis exporters.
- Add Redis Sentinel for high availability and secure Redis communication with password management.
- Enhance monitoring alert summaries with emojis and improve Discord notification formatting with status indicators and detailed fields.
- Add Hetzner MTU and iptables configuration to Docker daemon.
- Configure Docker log rotation, Loki log retention and compaction, and Prometheus TSDB retention.
- Introduce standalone monitoring for bastion hosts and update the security overview dashboard.
- add new security-related Loki panels for login failures, sudo commands, Traefik, and Fail2Ban events to the security overview dashboard.
- Add Loki and Promtail for log aggregation and a security overview dashboard to the monitoring stack.
- Introduce Loki, provision Grafana datasources, and add config hash labels for Prometheus and Grafana services.
- Add monitoring stack with Prometheus, Alertmanager, Grafana, and node-exporter dashboard.
- Implement a Docker Swarm monitoring stack with Prometheus, Grafana, and Alertmanager, managed by Ansible.
- Extract Authentik Terraform configuration into a dedicated module, refactoring outpost binding to use `null_resource` with API calls.
- Add Authentik provider and resources to integrate with Traefik.
- Integrate Authentik with Terraform to manage the Traefik application, including API token provisioning via Ansible.
- Add Authentik Terraform provider and configure its API token and URL via Ansible.
- Remove Authentik's Redis dependency, configure Redis memory limits, and enhance node provisioning with improved hardening and SSH keyscan.
- Implement a dedicated 'provision' user for SSH access and disable direct root login for enhanced security and privilege escalation.
- Enforce SSL for PostgreSQL connections in Authentik and database HA.
- Add tasks to wait for PostgreSQL master readiness via pgpool and idempotently create the Authentik database.
- Configure PostgreSQL SSL, enhance HAProxy health checks and DNS resolution, update poetry lock, and ignore new authentication and script files.
- Extract Authentik's PostgreSQL HA cluster into a new `database_ha` role and stack, and reduce default node counts.
- Enhance Authentik database resilience with Patroni integration, increased replicas, and improved HAProxy configuration, and add a database SSH helper.
- Implement Authentik for centralized authentication and integrate it with Traefik, alongside network security enhancements.
- Add Authentik SSO deployment, including secret generation, Ansible role, and Traefik integration.
- Add egress firewall rules for bastion to allow internal SSH, DNS, APT updates, and NTP.
- Harden Traefik security by encrypting the public overlay network, restricting web ingress to the load balancer, adding comprehensive egress firewall rules, and refining Traefik configurations.
- Offload TLS termination and certificate management from Traefik to the Hetzner Load Balancer.
- Implement Traefik and Socket Proxy deployment for edge load balancing and routing in the Swarm cluster.
- Add direct SSH access targets for bastion, manager, and worker nodes via Makefile, and update the contributing guide to reflect these new commands.
- Add Ansible playbooks, roles, and dynamic inventory for Docker Swarm cluster provisioning.
- Implement automatic DNS routing for environments using Hetzner DNS.
- enable dynamic configuration of allowed SSH IPs via GitHub secrets for CI.
- Replace single location variable with a list of locations to distribute resources across multiple data centers.
- Multi Environment Orchestration & Security Verification (#4)
- Terraform State Setup (#3)
- installed pre-commit dependency, including the pre-comit config file for terraform & commitizen

### fix

- update prometheus relabeling for shared-backend network and correct postgres-exporter database connection string
- Update jq filter to robustly extract internal IP addresses from Terraform output using `select(type=="string")`.
- Update Traefik network labels from `docker` to `swarm` in database and monitoring stacks.
- monitoring stack to use traefik.docker instead of swarm
- Tune alert thresholds and durations for NodeDown, HostOutOfMemory, and SuspiciousNetworkTraffic alerts, and improve Discord alert message formatting.
- Trigger Docker service restart after logging configuration updates.
- Update Traefik security probe dashboard to use regex service matching and the DownstreamStatus field.
- Configure Authentik to prefer PostgreSQL SSL and enable SSL for the database.
- Use traefik.swarm.network instead of traefik.docker.network for the authentik-outpost service.

### build

- Add GitHub Actions Continuous Integration workflow for pre-com… (#2)

### refactor

- standardize service naming conventions and add service-specific Makefiles and automated version bumping workflows
- decouple Authentik sync and event processing by migrating to asynchronous RabbitMQ consumers
- migrate stack configurations to Docker configs, update deployment commands, and optimize replica scaling and monitoring metrics.
- disable certificate destroy prevention and refine internal IP parsing in Makefile.
- Refactor Ansible password generation and Terraform token synchronization, update database connection parameters, and add `StrictHostKeyChecking=accept-new` to Makefile SSH commands.
- remove Authentik bootstrap and admin secret management from Ansible and persist the database password idempotently.
- relocate Docker daemon log rotation configuration task to an earlier position in the playbook.
- Remove Node Exporter and cAdvisor ingress rules from firewall.
- Enable strict SSH host key checking by removing related overrides and adding a Makefile target for host key management.
- Remove SUPERUSER privilege for the authentik user and change replication host authentication to md5.
- Add database server IP addresses to the `internal_ips` output.

### chore

- add dev dependencies and documentation to onboarding service and update node init script
- initialize virtual environment dependencies for onboarding service
- Subscription and Payment Service for RideBase  Setup
- updated gitignore
- remove commented-out lifecycle block from certificate resource
- remove deprecated trusted proxy configuration variables from authentik stack template
- Add retry logic and suppress logs for database readiness and creation tasks.
- Refine internal IP extraction logic, prevent ACM certificate destruction, and explicitly connect Traefik to the public network.
- Reduce default stage instance count and add null provider version constraint.
- better ssh_commands & using -system instead of -p
- replaced curl
- linting via precomit rules
- terraform file
- checking precommit
- set up project skeleton and automated versioning (#1)

### docs

- Update 'High restart rate' alert description duration from 15 minutes to 5 minutes.
- Update deployment instructions in `CONTRIBUTING.md` to detail a new 3-phase deployment process and add a quick start guide to `README.md`.
- Add instructions for trusting host keys and a deployment flow summary to CONTRIBUTING.md.
- move detailed setup and contribution guidelines from README.md to a new CONTRIBUTING.md file
- add README with Poetry installation and pre-commit hook setup instructions.
