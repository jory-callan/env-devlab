#!/bin/bash
# download-plugins.sh — 预下载 Grafana 插件到本地目录
# 用法: bash download-plugins.sh [目标目录]
# 默认下载到脚本所在目录的 plugins/ 下
set -euo pipefail

DEST="${1:-$(cd "$(dirname "$0")" && pwd)/plugins}"
mkdir -p "$DEST"

echo ">>> 下载到: $DEST"
echo ""

# VictoriaMetrics Metrics Datasource
echo "⬇️  victoriametrics-metrics-datasource v0.25.2..."
curl -fSL --progress-bar -o "$DEST/vm-metrics.tar.gz" \
  "https://gh-proxy.com/https://github.com/VictoriaMetrics/victoriametrics-datasource/releases/download/v0.25.2/victoriametrics-metrics-datasource-v0.25.2.tar.gz"
echo "   ✅  $(ls -lh "$DEST/vm-metrics.tar.gz" | awk '{print $5}')"

# VictoriaLogs Datasource
echo "⬇️  victoriametrics-logs-datasource v0.29.0..."
curl -fSL --progress-bar -o "$DEST/vm-logs.tar.gz" \
  "https://gh-proxy.com/https://github.com/VictoriaMetrics/victorialogs-datasource/releases/download/v0.29.0/victoriametrics-logs-datasource-v0.29.0.tar.gz"
echo "   ✅  $(ls -lh "$DEST/vm-logs.tar.gz" | awk '{print $5}')"

echo ""
echo "✅ 下载完成"
echo "   手动注入到 Grafana PVC:"
echo "   GRAFANA_POD=\$(kubectl -n monitoring get pod -l app.kubernetes.io/name=grafana -o jsonpath='{.items[0].metadata.name}')"
echo "   kubectl cp $DEST/vm-metrics.tar.gz monitoring/\$GRAFANA_POD:/var/lib/grafana/plugins/"
echo "   kubectl cp $DEST/vm-logs.tar.gz monitoring/\$GRAFANA_POD:/var/lib/grafana/plugins/"
echo "   kubectl -n monitoring exec \$GRAFANA_POD -- tar -xzf /var/lib/grafana/plugins/vm-metrics.tar.gz -C /var/lib/grafana/plugins/"
echo "   kubectl -n monitoring exec \$GRAFANA_POD -- tar -xzf /var/lib/grafana/plugins/vm-logs.tar.gz -C /var/lib/grafana/plugins/"
echo "   kubectl -n monitoring exec \$GRAFANA_POD -- rm /var/lib/grafana/plugins/vm-metrics.tar.gz /var/lib/grafana/plugins/vm-logs.tar.gz"
echo "   kubectl -n monitoring rollout restart deployment/vm-grafana"
