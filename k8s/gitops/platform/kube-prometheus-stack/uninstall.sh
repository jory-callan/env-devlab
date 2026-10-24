#!/bin/bash
# uninstall.sh — kube-prometheus-stack 卸载
# 用法: bash uninstall.sh
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACE="monitoring"

echo ">> 卸载 Promtail ..."
helm uninstall promtail -n "$NAMESPACE" --ignore-not-found --wait

echo ">> 卸载 Loki ..."
helm uninstall loki -n "$NAMESPACE" --ignore-not-found --wait

echo ">> 卸载 kube-prometheus-stack ..."
helm uninstall prometheus -n "$NAMESPACE" --ignore-not-found --wait

echo ">> 清理 Prometheus/Loki Ingress ..."
kubectl delete -f "$SCRIPT_DIR/prometheus-ingress.yaml" --ignore-not-found 2>/dev/null

echo ""
echo "✅ kube-prometheus-stack 已完全卸载"
echo ""
echo ">> 如需删除命名空间:"
echo "    kubectl delete namespace $NAMESPACE --ignore-not-found"
