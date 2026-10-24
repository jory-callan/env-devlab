#!/bin/bash
# install.sh -- 安装 MetalLB LoadBalancer
# 用法: bash install.sh
# 前置条件: Cilium 或其它 CNI 已就绪，kubectl 连接正常
set -euo pipefail

METALLB_VERSION="0.16.1"
# 官方 release 直链(上游维护); 本地 chart 已 vendored, 仅在缺失时兜底下载
CHART_URL="https://github.com/metallb/metallb/releases/download/metallb-chart-${METALLB_VERSION}/metallb-${METALLB_VERSION}.tgz"
CHART_FILE="$(cd "$(dirname "$0")" && pwd)/metallb-${METALLB_VERSION}.tgz"

# 检查是否已安装
if helm list -n metallb-system 2>/dev/null | grep -q metallb; then
    echo "[INFO]  MetalLB 已安装，跳过"
    exit 0
fi

# 本地 chart 不存在时，从官方 release 下载
if [ ! -f "$CHART_FILE" ]; then
    echo ">> 本地 chart 未找到，从官方源下载 MetalLB ${METALLB_VERSION} ..."
    curl -fsSL "$CHART_URL" -o "$CHART_FILE" --connect-timeout 30 --retry 3
fi

echo ">> 安装 MetalLB ..."
helm upgrade --install metallb "$CHART_FILE" \
    --namespace metallb-system --create-namespace \
    --wait --timeout 5m

# 应用 IP 地址池(L2 模式); 已存在则跳过, 保证脚本可重复执行
POOL_FILE="$(cd "$(dirname "$0")" && pwd)/pool.yaml"
if kubectl get ipaddresspool -n metallb-system default-pool >/dev/null 2>&1; then
    echo "[INFO]  IPAddressPool default-pool 已存在，跳过"
else
    echo ">> 创建 IPAddressPool ..."
    kubectl apply -f "$POOL_FILE"
fi

echo "[OK] MetalLB 安装完成"
echo ""
echo "   IP 地址池: $(kubectl get ipaddresspool -n metallb-system default-pool -o jsonpath='{.spec.addresses}' 2>/dev/null)"
echo ""
echo "   下一步: 安装 ingress-nginx (LoadBalancer 会从这里分配 IP)"
