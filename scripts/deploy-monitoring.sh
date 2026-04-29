#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

if [[ -f "$PROJECT_DIR/.env" ]]; then
  # shellcheck disable=SC1091
  source "$PROJECT_DIR/.env"
fi

export KUBECONFIG="${KUBECONFIG:-$PROJECT_DIR/kubeconfig.yaml}"
HCLOUD_REGION="${HCLOUD_REGION:-nbg1}"
ENABLE_CERT_MANAGER="${ENABLE_CERT_MANAGER:-false}"
LETSENCRYPT_ISSUER="${LETSENCRYPT_ISSUER:-letsencrypt-staging}"

if [[ ! -f "$KUBECONFIG" ]]; then
  echo "ERROR: kubeconfig not found at $KUBECONFIG"
  echo "Run terraform apply first or set KUBECONFIG to a valid path."
  exit 1
fi

if ! kubectl version --client >/dev/null 2>&1; then
  echo "ERROR: kubectl is not installed."
  exit 1
fi

if ! helm version >/dev/null 2>&1; then
  echo "ERROR: helm is not installed."
  exit 1
fi

kubectl apply -f "$PROJECT_DIR/kubernetes/monitoring/namespace.yaml"

kubectl apply -k "$PROJECT_DIR/kubernetes/core/hcloud-ccm/"
kubectl apply -k "$PROJECT_DIR/kubernetes/core/hcloud-csi/"

helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx >/dev/null 2>&1 || true
helm repo add jetstack https://charts.jetstack.io >/dev/null 2>&1 || true
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1 || true
helm repo add grafana https://grafana.github.io/helm-charts >/dev/null 2>&1 || true
helm repo update

kubectl apply -f "$PROJECT_DIR/monitoring/alertmanager/alertmanager-config.yaml"

helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --version 61.7.2 \
  --values "$PROJECT_DIR/helm/kube-prometheus-stack/values.yaml" \
  --set grafana.adminPassword="${GRAFANA_ADMIN_PASSWORD:-admin}" \
  --wait --timeout 15m

helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace monitoring \
  --create-namespace \
  --version 4.11.2 \
  --values "$PROJECT_DIR/helm/nginx-ingress/values.yaml" \
  --set controller.service.annotations."load-balancer\.hetzner\.cloud/location"="$HCLOUD_REGION" \
  --wait --timeout 10m

if [[ "$ENABLE_CERT_MANAGER" == "true" ]]; then
  if [[ -z "${ACME_EMAIL:-}" ]]; then
    echo "ERROR: ENABLE_CERT_MANAGER=true requires ACME_EMAIL."
    exit 1
  fi

  helm upgrade --install cert-manager jetstack/cert-manager \
    --namespace monitoring \
    --version v1.15.3 \
    --values "$PROJECT_DIR/helm/cert-manager/values.yaml" \
    --wait --timeout 10m

  sed "s#\${ACME_EMAIL}#${ACME_EMAIL}#g" \
    "$PROJECT_DIR/kubernetes/cert-manager/cluster-issuers.yaml" | kubectl apply -f -
fi

helm upgrade --install loki grafana/loki \
  --namespace monitoring \
  --version 6.11.0 \
  --values "$PROJECT_DIR/helm/loki/values.yaml" \
  --wait --timeout 10m

helm upgrade --install promtail grafana/promtail \
  --namespace monitoring \
  --version 6.16.6 \
  --values "$PROJECT_DIR/helm/promtail/values.yaml" \
  --wait --timeout 10m

kubectl apply -f "$PROJECT_DIR/monitoring/grafana/loki-datasource-configmap.yaml"

kubectl -n monitoring create configmap grafana-dashboard-cluster-overview \
  --from-file="$PROJECT_DIR/monitoring/grafana/dashboards/cluster-overview.json" \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl label configmap grafana-dashboard-cluster-overview -n monitoring grafana_dashboard=1 --overwrite

kubectl -n monitoring create configmap grafana-dashboard-node-metrics \
  --from-file="$PROJECT_DIR/monitoring/grafana/dashboards/node-metrics.json" \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl label configmap grafana-dashboard-node-metrics -n monitoring grafana_dashboard=1 --overwrite

kubectl -n monitoring create configmap grafana-dashboard-workload-metrics \
  --from-file="$PROJECT_DIR/monitoring/grafana/dashboards/workload-metrics.json" \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl label configmap grafana-dashboard-workload-metrics -n monitoring grafana_dashboard=1 --overwrite

kubectl apply -f "$PROJECT_DIR/monitoring/prometheus/rules/"

if [[ -n "${GRAFANA_HOST:-}" ]]; then
  sed \
    -e "s#\${GRAFANA_HOST}#${GRAFANA_HOST}#g" \
    -e "s#\${LETSENCRYPT_ISSUER}#${LETSENCRYPT_ISSUER}#g" \
    "$PROJECT_DIR/kubernetes/monitoring/grafana-ingress.yaml" | kubectl apply -f -
fi

if [[ -n "${PROMETHEUS_HOST:-}" ]]; then
  sed \
    -e "s#\${PROMETHEUS_HOST}#${PROMETHEUS_HOST}#g" \
    -e "s#\${LETSENCRYPT_ISSUER}#${LETSENCRYPT_ISSUER}#g" \
    "$PROJECT_DIR/kubernetes/monitoring/prometheus-ingress.yaml" | kubectl apply -f -
fi

if [[ -n "${LOKI_HOST:-}" ]]; then
  sed \
    -e "s#\${LOKI_HOST}#${LOKI_HOST}#g" \
    -e "s#\${LETSENCRYPT_ISSUER}#${LETSENCRYPT_ISSUER}#g" \
    "$PROJECT_DIR/kubernetes/monitoring/loki-ingress.yaml" | kubectl apply -f -
fi

echo ""
echo "Monitoring platform deployed successfully."
echo "Grafana URL: https://${GRAFANA_HOST:-<set-GRAFANA_HOST>}"
echo "Grafana user: admin"
