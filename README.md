# DevOps Lab — Go + Terraform + HTTPS

A minimal end-to-end DevOps pipeline: a Go HTTP API deployed to AWS EC2 via Docker, with infrastructure managed by Terraform and CI/CD driven by GitHub Actions.

## Architecture

```
GitHub Actions
  ├── deploy.yml  → builds Docker image, pushes to ECR, deploys via SSM
  └── terraform.yml → plans on PRs, applies on merge to main

AWS
  ├── ECR          → container registry
  ├── EC2 (t3.micro, Amazon Linux 2023) → runs Docker Compose
  │     ├── Caddy  → reverse proxy on :80, gzip, proxies to api:8080
  │     └── API    → Go binary in distroless container
  └── IAM / VPC / Security Groups → managed by Terraform
```

## Project Structure

```
app/          Go API source + Dockerfile
infra/        Terraform (VPC, EC2, ECR, IAM, Security Groups)
ops/          Docker Compose + Caddyfile for the EC2 host
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
   - Pulls the new image
   - Runs `docker compose up -d`
   - Prunes old images

**On PRs touching `infra/`:** runs `terraform fmt`, `validate`, and `plan`  
**On merge to `main` touching `infra/`:** runs `terraform apply`

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

## Deployment Notes

The EC2 instance runs Docker Compose from `/home/ssm-user/devops-lab/ops`. The Caddyfile proxies all traffic on port 80 to the Go API container on port 8080 with gzip compression enabled.

The Go binary is built with `-ldflags` to embed `version`, `commit_sha`, and `build_time` at build time, visible at `/version`.
