#!/bin/bash
# install.sh -- 安装 cert-manager
# 用法: bash install.sh
# 前置条件: kubectl 连接正常
set -euo pipefail

CERT_VERSION="v1.19.6"
# 官方 chart 仓库(上游维护); 本地 chart 已 vendored, 仅在缺失时兜底下载
CHART_URL="https://charts.jetstack.io/charts/cert-manager-${CERT_VERSION}.tgz"
CHART_FILE="$(cd "$(dirname "$0")" && pwd)/cert-manager-${CERT_VERSION}.tgz"

# 检查是否已安装
if helm list -n cert-manager 2>/dev/null | grep -q cert-manager; then
    echo "[INFO] cert-manager 已安装，跳过"
    exit 0
fi

# 本地 chart 不存在时，从官方源下载
if [ ! -f "$CHART_FILE" ]; then
    echo ">> 本地 chart 未找到，从官方源下载 cert-manager ${CERT_VERSION} ..."
    curl -fsSL "$CHART_URL" -o "$CHART_FILE" --connect-timeout 30 --retry 3
fi

echo ">> 安装 cert-manager ${CERT_VERSION} ..."
helm upgrade --install cert-manager "$CHART_FILE" \
    --namespace cert-manager --create-namespace \
    --set crds.enabled=true \
    --set webhook.timeoutSeconds=30 \
    --wait --timeout 5m

echo "[OK] cert-manager 安装完成"
echo ""
echo "   验证:"
echo "     kubectl -n cert-manager get pods"
echo "     kubectl get crd | grep cert-manager"
echo ""
echo "   配置证书签发器（本目录）:"
echo "     kubectl apply -f cluster-issuer.yaml"
