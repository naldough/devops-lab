# DevOps Lab — Go + Terraform + Kubernetes (K3s)

A minimal end-to-end DevOps pipeline: a Go HTTP API deployed to a K3s Kubernetes cluster on AWS EC2, with infrastructure managed by Terraform and CI/CD driven by GitHub Actions. The goal is a small "internal cloud" lab for spinning up and testing environments on demand.

## Architecture

```
GitHub Actions
  ├── deploy.yml  → builds Docker image, pushes to ECR, rolls it out to K3s via SSM
  └── terraform.yml → plans on PRs, applies on merge to main

AWS
  ├── ECR          → container registry
  ├── EC2 (t3.small, Amazon Linux 2023) → runs K3s
  │     ├── Traefik ingress → ports 80/443, routes api.ronaldoauguste.com
  │     └── Deployment "api" → 2 replicas of the Go binary in a distroless,
  │                             non-root container, with health probes
  └── IAM / VPC / Security Groups → managed by Terraform
```

## Project Structure

```
app/          Go API source + Dockerfile
infra/        Terraform (VPC, EC2, ECR, IAM, Security Groups)
k8s/          Kubernetes manifests (Deployment, Service, Ingress) + one-time setup.sh
ops/          Previous Docker Compose + Caddy setup (kept for reference)
.github/
  workflows/
    deploy.yml      CI/CD pipeline (build → push → SSM deploy)
    terraform.yml   Terraform fmt/validate/plan/apply
```

## API Endpoints

| Method | Path       | Description                          |
|--------|------------|--------------------------------------|
| GET    | `/health`  | Returns `{"status":"ok","time":"..."}` |
| GET    | `/version` | Returns build version, commit SHA, and build time |

## Prerequisites

- AWS account with an IAM role named `GitHubActions` that trusts GitHub OIDC
- Terraform state backend configured (or use local state for experimentation)
- GitHub repository secrets: none required — auth uses OIDC

## Infrastructure

Managed in [infra/](infra/). Key defaults:

| Variable        | Default      |
|-----------------|--------------|
| `aws_region`    | `us-east-1`  |
| `project`       | `devops-lab` |
| `instance_type` | `t3.micro`   |

To apply manually:

```bash
cd infra
terraform init
terraform apply
```

## CI/CD

**On push to `main` (app changes):**
1. Checks out code and authenticates to AWS via OIDC (no stored credentials)
2. Builds and pushes a Docker image to ECR, tagged with the short commit SHA
3. Finds the running EC2 instance by tag and sends a deploy command via SSM:
   - Refreshes the ECR pull secret in the cluster (ECR tokens expire after 12 hours)
   - Runs `kubectl set image` for a zero-downtime rolling update
   - Waits for `kubectl rollout status` and fails the pipeline if the rollout fails

**On PRs touching `infra/`:** runs `terraform fmt`, `validate`, and `plan`  
**On merge to `main` touching `infra/`:** runs `terraform apply`

## Security Scanning

Every pull request and push that touches `infra/` or `k8s/` runs two static scanners (`.github/workflows/security-scan.yml`):

- **tfsec** scans the Terraform for AWS misconfigurations
- **Checkov** scans the Terraform and the Kubernetes manifests

They run in soft-fail mode: findings show in the job log without blocking deploys, so accepted lab risks don't stop the pipeline.

**Fixed from the first scan:**

- EC2 now requires IMDSv2 session tokens (blocks SSRF-style credential theft through the metadata service)
- ECR scans every pushed image for known CVEs
- Every security group rule has a description
- Pods drop the service account token, use the `RuntimeDefault` seccomp profile, and have a CPU limit

**Known and accepted for this lab (next candidates to fix):**

- Ports 80/443 open to the internet: intended, it's a public web endpoint
- Public subnet / public IP: single-instance lab with no load balancer
- Root volume not encrypted: fixing it replaces the instance, planned for the next rebuild
- VPC flow logs, detailed monitoring, KMS-encrypted ECR: skipped for cost
- Mutable ECR tags: images are tagged by commit SHA; immutability would break re-running a failed deploy

## Local Development

```bash
cd app
go run .
# API available at http://localhost:8080
```

Or with Docker:

```bash
docker build -t devops-lab-api ./app
docker run -p 8080:8080 devops-lab-api
```

## Kubernetes (K3s)

The API runs as a Deployment with 2 replicas in the `devops-lab` namespace:

- Readiness and liveness probes on `/health`; Kubernetes restarts or reroutes around unhealthy pods
- Rolling updates with `maxUnavailable: 0`, so a deploy never drops below 2 running pods
- Hardened pod settings: non-root user, read-only root filesystem, all Linux capabilities dropped
- Images pulled from private ECR through an `imagePullSecret`
- Traefik (bundled with K3s) handles ingress for `api.ronaldoauguste.com`

One-time migration from Docker Compose, on the instance:

```bash
sudo bash k8s/setup.sh
```

Useful commands:

```bash
kubectl -n devops-lab get pods -o wide
kubectl -n devops-lab logs -l app=api --tail=20
kubectl -n devops-lab rollout history deployment/api
kubectl -n devops-lab rollout undo deployment/api
```

## Deployment Notes

The previous setup ran Docker Compose from `/home/ssm-user/devops-lab/ops`, with Caddy proxying to the API and handling HTTPS. It is kept in `ops/` for reference. HTTPS on K3s (cert-manager + Let's Encrypt) is the next planned step.

The Go binary is built with `-ldflags` to embed `version`, `commit_sha`, and `build_time` at build time, visible at `/version`.
