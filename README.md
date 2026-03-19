# upgraded_spork

IaC template using Terraform, Ansible, and Docker Swarm on Hetzner Cloud.

## Quick Start (3-Phase Deployment)
1.  **Foundation**: `cd terraform && make apply ENV=dev`
2.  **Apps**: `cd ansible && make swarm ENV=dev`
3.  **SSO**: `cd terraform_authentik && make apply ENV=dev`

For detailed setup, troubleshooting, and contribution guidelines, see [CONTRIBUTING.md](./CONTRIBUTING.md).
