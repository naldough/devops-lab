#!/bin/bash
# One-time move from Docker Compose to K3s. Run on the EC2 instance as root:
#   sudo bash k8s/setup.sh
set -euo pipefail

REGION="us-east-1"
REPO="devops-lab-api"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "==> Stopping Docker Compose (frees ports 80/443 for Traefik)"
if [ -f "$SCRIPT_DIR/../ops/docker-compose.yml" ]; then
  (cd "$SCRIPT_DIR/../ops" && docker compose down) || true
fi

echo "==> Installing K3s"
if ! command -v k3s >/dev/null 2>&1; then
  curl -sfL https://get.k3s.io | INSTALL_K3S_SKIP_SELINUX_RPM=true \
    INSTALL_K3S_EXEC="--write-kubeconfig-mode 644" sh -
fi
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
KUBECTL=/usr/local/bin/kubectl

echo "==> Waiting for the node to be Ready"
until $KUBECTL get nodes 2>/dev/null | grep -q " Ready"; do sleep 3; done
$KUBECTL get nodes

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGISTRY="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"
TAG=$(aws ecr describe-images --region "$REGION" --repository-name "$REPO" \
  --query 'sort_by(imageDetails,&imagePushedAt)[-1].imageTags[0]' --output text)
IMAGE="${REGISTRY}/${REPO}:${TAG}"
echo "==> Latest image: $IMAGE"

echo "==> Creating namespace and ECR pull secret"
$KUBECTL create namespace devops-lab --dry-run=client -o yaml | $KUBECTL apply -f -
$KUBECTL -n devops-lab create secret docker-registry ecr-creds \
  --docker-server="$REGISTRY" --docker-username=AWS \
  --docker-password="$(aws ecr get-login-password --region "$REGION")" \
  --dry-run=client -o yaml | $KUBECTL apply -f -

echo "==> Deploying"
sed "s|IMAGE_PLACEHOLDER|${IMAGE}|" "$SCRIPT_DIR/api.yaml" | $KUBECTL apply -f -
$KUBECTL -n devops-lab rollout status deployment/api --timeout=120s
$KUBECTL -n devops-lab get pods,svc,ingress -o wide

echo "==> Done. Test with: curl -H 'Host: api.ronaldoauguste.com' http://localhost/health"
