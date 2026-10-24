#!/bin/bash
# uninstall.sh — VictoriaMetrics K8s Stack 卸载
set -euo pipefail

NAMESPACE="monitoring"

echo ">>> 卸载 victoria-metrics-k8s-stack ..."
helm uninstall vm --namespace "$NAMESPACE" 2>/dev/null || true

echo ""
echo ">>> PVC（保留，如需清理手动执行）:"
kubectl get pvc -n "$NAMESPACE" -l 'app.kubernetes.io/instance=vm' -o name 2>/dev/null | head -5

echo ""
echo ">>> 如需删除命名空间:"
echo "    kubectl delete namespace $NAMESPACE --ignore-not-found"
echo ""
echo ">>> 如需清理 CRD:"
echo "    kubectl delete crd -l app.kubernetes.io/instance=vm"

echo ""
echo "✅ 卸载完成"
