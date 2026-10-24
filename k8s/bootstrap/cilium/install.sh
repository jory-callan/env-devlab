#!/bin/bash
# install.sh -- 安装 Cilium CNI + Hubble
# 用法: bash install.sh
# 前置条件: k3s 已安装且 flannel-backend: none
set -euo pipefail

CILIUM_VERSION="1.18.11"
# 官方 helm 仓库(上游维护); 本地 chart 已 vendored, 仅在缺失时兜底下载
CHART_REPO_URL="https://helm.cilium.io"
CHART_FILE="$(cd "$(dirname "$0")" && pwd)/cilium-${CILIUM_VERSION}.tgz"

# 检查是否已安装
if helm list -n kube-system 2>/dev/null | grep -q cilium; then
    echo "[INFO]  Cilium 已安装，跳过"
    exit 0
fi

# 本地 chart 不存在时，从官方 helm 仓库下载
if [ ! -f "$CHART_FILE" ]; then
    echo ">> 本地 chart 未找到，从官方源下载 Cilium ${CILIUM_VERSION} ..."
    curl -fsSL "${CHART_REPO_URL}/cilium-${CILIUM_VERSION}.tgz" \
      -o "$CHART_FILE" --connect-timeout 30 --retry 3
fi

# 安装
echo ">> 安装 Cilium + Hubble ..."
helm upgrade --install cilium "$CHART_FILE" \
    --namespace kube-system \
    --set kubeProxyReplacement=false \
    --set cni.exclusive=false \
    --set ipam.mode=cluster-pool \
    --set ipam.operator.clusterPoolIPv4PodCIDRList=10.42.0.0/16 \
    --set ipam.operator.clusterPoolIPv4MaskSize=24 \
    --set hubble.enabled=true \
    --set hubble.relay.enabled=true \
    --set hubble.ui.enabled=true \
    --set hubble.metrics.enabled="{dns,drop,tcp,flow,icmp,http}" \
    --set bpf.masquerade=false \
    --set autoDirectNodeRoutes=true \
    --set routingMode=native \
    --set ipv4NativeRoutingCIDR=10.42.0.0/16 \
    --set operator.replicas=1 \
    --set operator.prometheus.enabled=true \
    --set operator.prometheus.serviceMonitor.enabled=false \
    --wait --timeout 10m

echo "[OK] Cilium 安装完成"
echo "   Hubble UI: kubectl port-forward -n kube-system svc/hubble-ui 12000:80"
