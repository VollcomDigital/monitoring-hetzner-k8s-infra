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
MONITORING_USE_EPHEMERAL_STORAGE="${MONITORING_USE_EPHEMERAL_STORAGE:-true}"

MONITORING_KPS_EXTRA_ARGS=()
MONITORING_LOKI_EXTRA_ARGS=()
if [[ "$MONITORING_USE_EPHEMERAL_STORAGE" == "true" ]]; then
  MONITORING_KPS_EXTRA_ARGS=( -f "$PROJECT_DIR/helm/kube-prometheus-stack/values-ephemeral.yaml" )
  MONITORING_LOKI_EXTRA_ARGS=( -f "$PROJECT_DIR/helm/loki/values-ephemeral.yaml" )
fi
if [[ "${MONITORING_UI_VIA_LB_IP:-false}" == "true" ]]; then
  MONITORING_KPS_EXTRA_ARGS+=( -f "$PROJECT_DIR/helm/kube-prometheus-stack/values-lb-ip-ui.yaml" )
else
  MONITORING_KPS_EXTRA_ARGS+=( -f "$PROJECT_DIR/helm/kube-prometheus-stack/values-prometheus-ingress-host.yaml" )
fi

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

if [[ "$MONITORING_USE_EPHEMERAL_STORAGE" == "true" ]]; then
  echo "MONITORING_USE_EPHEMERAL_STORAGE=true: installing without PVCs (set to false when hcloud volumes bind)."
fi

kubectl apply -k "$PROJECT_DIR/kubernetes/core/hcloud-ccm/"
kubectl apply -k "$PROJECT_DIR/kubernetes/core/hcloud-csi/"

helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx >/dev/null 2>&1 || true
helm repo add external-dns https://kubernetes-sigs.github.io/external-dns >/dev/null 2>&1 || true
helm repo add jetstack https://charts.jetstack.io >/dev/null 2>&1 || true
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1 || true
helm repo add grafana https://grafana.github.io/helm-charts >/dev/null 2>&1 || true
helm repo update

kubectl apply -f "$PROJECT_DIR/monitoring/alertmanager/alertmanager-config.yaml"

helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --version 61.7.2 \
  --values "$PROJECT_DIR/helm/kube-prometheus-stack/values.yaml" \
  "${MONITORING_KPS_EXTRA_ARGS[@]+"${MONITORING_KPS_EXTRA_ARGS[@]}"}" \
  --set grafana.adminPassword="${GRAFANA_ADMIN_PASSWORD:-admin}" \
  --wait --timeout 15m

helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace monitoring \
  --create-namespace \
  --version 4.11.2 \
  --values "$PROJECT_DIR/helm/nginx-ingress/values.yaml" \
  --set controller.service.annotations."load-balancer\.hetzner\.cloud/location"="$HCLOUD_REGION" \
  --wait --timeout 10m

if [[ "${ENABLE_EXTERNAL_DNS:-false}" == "true" ]]; then
  case "${EXTERNAL_DNS_PROVIDER:-cloudflare}" in
    cloudflare)
      if [[ -z "${CF_API_TOKEN:-}" || -z "${EXTERNAL_DNS_DOMAIN_FILTER:-}" ]]; then
        echo "ERROR: ENABLE_EXTERNAL_DNS=true with cloudflare requires CF_API_TOKEN and EXTERNAL_DNS_DOMAIN_FILTER."
        exit 1
      fi
      kubectl -n monitoring create secret generic external-dns-credentials \
        --from-literal=cf_api_token="$CF_API_TOKEN" \
        --dry-run=client -o yaml | kubectl apply -f -
      helm upgrade --install external-dns external-dns/external-dns \
        --namespace monitoring \
        --version 1.19.0 \
        --values "$PROJECT_DIR/helm/external-dns/values-cloudflare.yaml" \
        --set "domainFilters[0]=${EXTERNAL_DNS_DOMAIN_FILTER}" \
        --wait --timeout 10m
      ;;
    hetzner)
      echo "ERROR: EXTERNAL_DNS_PROVIDER=hetzner is not installed by this script."
      echo "Upstream external-dns has no built-in Hetzner DNS provider; use Cloudflare here, point records manually to the ingress LB, or deploy external-dns with a Hetzner webhook provider chart."
      exit 1
      ;;
    *)
      echo "ERROR: Only EXTERNAL_DNS_PROVIDER=cloudflare is automated; got '${EXTERNAL_DNS_PROVIDER:-}'."
      exit 1
      ;;
  esac
fi

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

  kubectl rollout status deployment/cert-manager -n monitoring --timeout=180s
  kubectl rollout status deployment/cert-manager-cainjector -n monitoring --timeout=180s
  kubectl rollout status deployment/cert-manager-webhook -n monitoring --timeout=180s

  issuer_apply_ok=false
  for attempt in {1..18}; do
    if sed "s#\${ACME_EMAIL}#${ACME_EMAIL}#g" \
      "$PROJECT_DIR/kubernetes/cert-manager/cluster-issuers.yaml" | kubectl apply -f -; then
      issuer_apply_ok=true
      break
    fi
    echo "cert-manager webhook not ready yet; retry ${attempt}/18 in 10s..."
    sleep 10
  done
  if [[ "$issuer_apply_ok" != "true" ]]; then
    echo "WARN: Admission webhooks block ClusterIssuer create; removing webhook configs once, then restoring via Helm."
    kubectl delete validatingwebhookconfiguration cert-manager-webhook --ignore-not-found
    kubectl delete mutatingwebhookconfiguration cert-manager-webhook --ignore-not-found
    sleep 3
    if sed "s#\${ACME_EMAIL}#${ACME_EMAIL}#g" \
      "$PROJECT_DIR/kubernetes/cert-manager/cluster-issuers.yaml" | kubectl apply -f -; then
      issuer_apply_ok=true
    fi
    helm upgrade --install cert-manager jetstack/cert-manager \
      --namespace monitoring \
      --version v1.15.3 \
      --values "$PROJECT_DIR/helm/cert-manager/values.yaml" \
      --wait --timeout 10m
  fi
  if [[ "$issuer_apply_ok" != "true" ]]; then
    echo "ERROR: ClusterIssuers still not applied. Check: kubectl -n monitoring logs deploy/cert-manager-webhook"
    exit 1
  fi
fi

helm upgrade --install loki grafana/loki \
  --namespace monitoring \
  --version 6.11.0 \
  --values "$PROJECT_DIR/helm/loki/values.yaml" \
  "${MONITORING_LOKI_EXTRA_ARGS[@]+"${MONITORING_LOKI_EXTRA_ARGS[@]}"}" \
  --wait --timeout 20m

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

if [[ "${MONITORING_UI_VIA_LB_IP:-false}" == "true" ]]; then
  kubectl delete ingress grafana-by-lb-ip -n monitoring --ignore-not-found
  kubectl apply -f "$PROJECT_DIR/kubernetes/monitoring/monitoring-ui-lb-ip.yaml"
else
  kubectl delete ingress monitoring-ui-by-lb-ip grafana-by-lb-ip -n monitoring --ignore-not-found
fi

if [[ "${MONITORING_UI_VIA_LB_IP:-false}" == "true" ]]; then
  lb_ip="$(kubectl -n monitoring get svc ingress-nginx-controller \
    -o jsonpath='{.status.loadBalancer.ingress[0].ip}{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)"
  if [[ -n "$lb_ip" ]]; then
    helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
      --namespace monitoring \
      --version 61.7.2 \
      --reuse-values \
      --set "prometheus.prometheusSpec.externalUrl=http://${lb_ip}/prometheus" \
      --wait --timeout 10m
  fi
elif [[ -n "${PROMETHEUS_HOST:-}" ]]; then
  helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
    --namespace monitoring \
    --version 61.7.2 \
    --reuse-values \
    --set "prometheus.prometheusSpec.externalUrl=https://${PROMETHEUS_HOST}/" \
    --wait --timeout 10m
fi

echo ""
echo "Monitoring platform deployed successfully."
if [[ "${MONITORING_UI_VIA_LB_IP:-false}" == "true" ]]; then
  lb_ip="${lb_ip:-$(kubectl -n monitoring get svc ingress-nginx-controller \
    -o jsonpath='{.status.loadBalancer.ingress[0].ip}{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)}"
  if [[ -n "$lb_ip" ]]; then
    echo "HTTP via load balancer (no DNS):"
    echo "  Grafana:     http://${lb_ip}/"
    echo "  Prometheus:  http://${lb_ip}/prometheus/"
    echo "  Loki API:    http://${lb_ip}/loki/  (Grafana Explore uses the in-cluster URL; this is for curl / tools)"
  else
    echo "MONITORING_UI_VIA_LB_IP: wait for ingress-nginx-controller EXTERNAL-IP, then use http://<ip>/, /prometheus/, /loki/"
  fi
fi
echo "Grafana URL (hostname ingress): https://${GRAFANA_HOST:-<set-GRAFANA_HOST-or-use-MONITORING_UI_VIA_LB_IP>}"
echo "Grafana user: admin"
