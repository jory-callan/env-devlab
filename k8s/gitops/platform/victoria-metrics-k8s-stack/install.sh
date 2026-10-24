#!/bin/bash
# install.sh — VictoriaMetrics K8s Stack（指标 + 日志，单 Chart）
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACE="monitoring"
CHART_FILE="$SCRIPT_DIR/victoria-metrics-k8s-stack-0.85.9.tgz"

[ -f "$CHART_FILE" ] || { echo "❌ 缺少 chart 文件: $CHART_FILE"; exit 1; }

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

echo ">>> 安装 victoria-metrics-k8s-stack（指标 + 日志）..."
# operator 管理的组件不加 --wait，避免异步调谐导致超时
helm upgrade --install vm "$CHART_FILE" \
  --namespace "$NAMESPACE" \
  --values "$SCRIPT_DIR/values-vmstack.yaml" \
  --timeout 10m

echo ""
echo "============================================"
echo "✅ VictoriaMetrics K8s Stack 部署完成"
echo "============================================"
echo ""
echo "   访问地址:"
echo "   Grafana:  https://vm-grafana.czw-sre.internal  (admin / admin123)"
echo "   Metrics:  https://vm-metrics.czw-sre.internal"
echo "   Logs:     https://vm-logs.czw-sre.internal"
echo ""
echo "   Grafana 内置 3 个数据源（自动配置）:"
echo "   - VictoriaMetrics           — PromQL 兼容查询"
echo "   - VictoriaMetrics (Native)  — MetricsQL 原生查询"
echo "   - VictoriaLogs              — LogsQL 日志查询"
echo ""
echo "   查看 Pod:  kubectl -n $NAMESPACE get pods -l 'app.kubernetes.io/instance=vm'"
