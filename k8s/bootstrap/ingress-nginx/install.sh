#!/bin/bash
# install.sh -- 安装 ingress-nginx
# 用法: bash install.sh
# 前置条件: Cilium + MetalLB 已就绪，kubectl 连接正常
set -euo pipefail

INGRESS_VERSION="4.15.1"
# 官方 release 直链(上游维护); 本地 chart 已 vendored, 仅在缺失时兜底下载
CHART_URL="https://github.com/kubernetes/ingress-nginx/releases/download/helm-chart-${INGRESS_VERSION}/ingress-nginx-${INGRESS_VERSION}.tgz"
CHART_FILE="$(cd "$(dirname "$0")" && pwd)/ingress-nginx-${INGRESS_VERSION}.tgz"
NAMESPACE="ingress-nginx"
RELEASE="ingress-nginx"

# ── 前置检查：MetalLB IPAddressPool ──────────────────────────────
# LoadBalancer Service 需要 MetalLB 分配 IP, 没有池子会一直 Pending
if ! kubectl get ipaddresspool -n metallb-system -o name 2>/dev/null | grep -q .; then
    POOL_FILE="$(cd "$(dirname "$0")/../metallb" && pwd)/pool.yaml"
    if [ -f "$POOL_FILE" ]; then
        echo ">> MetalLB IPAddressPool 未配置，自动 apply pool.yaml ..."
        kubectl apply -f "$POOL_FILE"
    else
        echo "[ERR] MetalLB 未安装且 pool.yaml 不存在，无法分配 LoadBalancer IP"
        echo "      请先执行: bash ../install.sh metallb"
        exit 1
    fi
fi

# ── 检查 helm release 状态 ──────────────────────────────────────
HELM_STATUS=$(helm list -n "$NAMESPACE" --filter "$RELEASE" -o json 2>/dev/null | jq -r '.[0].status // "not-found"')

if [ "$HELM_STATUS" = "deployed" ]; then
    echo "[INFO] ingress-nginx 已安装，执行升级（更新配置）..."
elif [ "$HELM_STATUS" = "failed" ]; then
    echo "[INFO] ingress-nginx 上次安装失败，执行 helm upgrade 修复 ..."
elif [ "$HELM_STATUS" = "not-found" ]; then
    echo ">> 安装 ingress-nginx ..."
fi

# ── 下载 chart ──────────────────────────────────────────────────
if [ ! -f "$CHART_FILE" ]; then
    echo ">> 本地 chart 未找到，从官方源下载 ingress-nginx ${INGRESS_VERSION} ..."
    curl -fsSL "$CHART_URL" -o "$CHART_FILE" --connect-timeout 30 --retry 3
fi

# ── 安装/升级 ────────────────────────────────────────────────────
echo ">> 安装 ingress-nginx (DaemonSet + LoadBalancer 模式)..."
VALUES_FILE="$(cd "$(dirname "$0")" && pwd)/values.yaml"
helm upgrade --install "$RELEASE" "$CHART_FILE" \
    --namespace "$NAMESPACE" --create-namespace \
    --values "$VALUES_FILE" \
    --set controller.kind=DaemonSet \
    --set controller.service.type=LoadBalancer \
    --set controller.service.externalTrafficPolicy=Local \
    --set controller.service.nodePorts.http=30080 \
    --set controller.service.nodePorts.https=30443 \
    --set controller.admissionWebhooks.enabled=true \
    --set controller.metrics.enabled=false \
    --set controller.progressDeadlineSeconds=600 \
    --wait --timeout 5m

echo "[OK] ingress-nginx 安装完成"
echo ""
echo "   查看分配的 LoadBalancer IP:"
echo "     kubectl -n ingress-nginx get svc ingress-nginx-controller"
echo ""
echo "   配置 DNS 将 *.czw-sre.internal 指向上述 IP"
echo ""
echo "   验证:"
echo "     curl -H 'Host: test.czw-sre.internal' http://<LB_IP>"
echo "     curl http://<任意节点IP>:30080"
