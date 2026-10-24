#!/bin/bash
# install.sh — kube-prometheus-stack (Prometheus + Grafana + Loki + Promtail)
# 用法: bash install.sh
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACE="monitoring"

# 创建命名空间
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# ── 1. kube-prometheus-stack ──────────────────────────
echo ">> 安装 kube-prometheus-stack ..."
# operator 管理的组件不加 --wait，避免异步调谐导致超时
helm upgrade --install prometheus "$SCRIPT_DIR/kube-prometheus-stack.tgz" \
  --namespace "$NAMESPACE" \
  --values "$SCRIPT_DIR/values-kps.yaml" \
  --timeout 10m

# ── 2. Loki ───────────────────────────────────────────
echo ">> 安装 Loki ..."
helm upgrade --install loki "$SCRIPT_DIR/loki-6.32.0.tgz" \
  --namespace "$NAMESPACE" \
  --values "$SCRIPT_DIR/values-loki.yaml" \
  --timeout 5m --wait

# ── 3. Promtail ───────────────────────────────────────
echo ">> 安装 Promtail ..."
helm upgrade --install promtail "$SCRIPT_DIR/promtail-6.16.6.tgz" \
  --namespace "$NAMESPACE" \
  --values "$SCRIPT_DIR/values-promtail.yaml" \
  --timeout 5m --wait

# ── 4. Prometheus WebUI Ingress ──────────────────────
echo ">> 创建 Prometheus WebUI Ingress ..."
kubectl apply -f "$SCRIPT_DIR/prometheus-ingress.yaml"

echo ""
echo "✅ kube-prometheus-stack 部署完成"
echo "   Grafana: https://grafana.czw-sre.internal (admin/admin)"
echo "   Prometheus: https://prometheus.czw-sre.internal"
echo "   Loki API: https://loki.czw-sre.internal"
