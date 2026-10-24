#!/bin/bash
# preload-images.sh -- 预热自建镜像仓库(zot)缓存
#
# 为什么需要:
#   1. zot 是"预缓存式"仓库，不是 pull-through 代理 —— 缺镜像 = 拉取必然失败
#   2. 官方 registry.k8s.io 会 307 重定向到 GCS(europe-west3)，从本网络 i/o timeout
#   3. containerd 的 mirror 配置不做回退：zot 未命中 → 官方超时 → 失败
#
# 用法（在能访问上游的机器上执行，如开发机）:
#   bash preload-images.sh                 # 拉取并推送到 zot
#   bash preload-images.sh --check         # 只检查 zot 中是否已有
#
# 环境变量:
#   ZOT_REGISTRY   默认 http://192.168.5.103:20000
set -euo pipefail

ZOT_REGISTRY="${ZOT_REGISTRY:-http://192.168.5.103:20000}"
CHECK_ONLY=0
[ "${1:-}" = "--check" ] && CHECK_ONLY=1

# ── 镜像清单 ─────────────────────────────────────────────
# 格式: <上游完整镜像>|<zot 内路径>
# zot 路径规则: /v2/<namespace>/<repo>，namespace ∈ {docker, ghcr, gcr, k8s}
# 留空表示该上游不在 zot 的镜像命名空间内 → 由 containerd 直连拉取
IMAGES=(
    # ── k3s 内置组件 ──
    "registry.k8s.io/pause:3.10.2|k8s/pause:3.10.2"
    "registry.k8s.io/coredns/coredns:v1.13.1|k8s/coredns/coredns:v1.13.1"
    "registry.k8s.io/kube-proxy:v1.35.9|k8s/kube-proxy:v1.35.9"
    "registry.k8s.io/metrics-server/metrics-server:v0.9.0|k8s/metrics-server/metrics-server:v0.9.0"

    # ── ingress-nginx ──
    "registry.k8s.io/ingress-nginx/controller:v1.15.1|k8s/ingress-nginx/controller:v1.15.1"
    "registry.k8s.io/ingress-nginx/kube-webhook-certgen:v1.6.9|k8s/ingress-nginx/kube-webhook-certgen:v1.6.9"

    # ── cilium ──
    "quay.io/cilium/cilium:v1.18.11|"
    "quay.io/cilium/operator-generic:v1.18.11|"
    "quay.io/cilium/cilium-envoy:v1.18.11|"
    "quay.io/cilium/hubble-relay:v1.18.11|"
    "quay.io/cilium/hubble-ui:v0.13.3|"
    "quay.io/cilium/hubble-ui-backend:v0.13.3|"

    # ── metallb ──
    "quay.io/metallb/controller:v0.16.1|"
    "quay.io/metallb/speaker:v0.16.1|"
    "quay.io/metallb/frr-k8s:v0.0.25|"
    "quay.io/frrouting/frr:10.4.3|"

    # ── cert-manager ──
    "quay.io/jetstack/cert-manager-controller:v1.19.6|"
    "quay.io/jetstack/cert-manager-webhook:v1.19.6|"
    "quay.io/jetstack/cert-manager-cainjector:v1.19.6|"
    "quay.io/jetstack/cert-manager-startupapicheck:v1.19.6|"

    # ── nfs provisioner ──
    "registry.k8s.io/sig-storage/nfs-subdir-external-provisioner:v4.0.2|k8s/sig-storage/nfs-subdir-external-provisioner:v4.0.2"
    "docker.io/erichough/nfs-server:latest|docker/erichough/nfs-server:latest"

    # ── victoria-metrics ──
    "docker.io/victoriametrics/operator:v0.72.0|docker/victoriametrics/operator:v0.72.0"
    "docker.io/victoriametrics/operator:config-reloader-v0.72.0|docker/victoriametrics/operator:config-reloader-v0.72.0"
    "docker.io/victoriametrics/vmagent:v1.146.0|docker/victoriametrics/vmagent:v1.146.0"
    "docker.io/victoriametrics/vmalert:v1.146.0|docker/victoriametrics/vmalert:v1.146.0"
    "docker.io/victoriametrics/vmauth:v1.145.0|docker/victoriametrics/vmauth:v1.145.0"
    "docker.io/victoriametrics/victoria-logs:v1.51.0|docker/victoriametrics/victoria-logs:v1.51.0"
    "docker.io/grafana/grafana:13.0.1-security-01|docker/grafana/grafana:13.0.1-security-01"
    "docker.io/prom/alertmanager:v0.32.1|docker/prom/alertmanager:v0.32.1"
    "ghcr.io/victoriametrics/sync-job:v0.0.8|ghcr/victoriametrics/sync-job:v0.0.8"
    "docker.io/library/busybox:1.38.0|docker/library/busybox:1.38.0"

    # ── longhorn（可选组件，默认不装；启用时需要这些镜像）──
    # 实际镜像仓库是 docker.io/longhornio/*（不是 quay.io）
    "docker.io/longhornio/longhorn-manager:v1.12.0|docker/longhornio/longhorn-manager:v1.12.0"
    "docker.io/longhornio/longhorn-engine:v1.12.0|docker/longhornio/longhorn-engine:v1.12.0"
    "docker.io/longhornio/longhorn-ui:v1.12.0|docker/longhornio/longhorn-ui:v1.12.0"
    "docker.io/longhornio/longhorn-share-manager:v1.12.0|docker/longhornio/longhorn-share-manager:v1.12.0"
    # ⚠️ longhorn 的 CSI 组件镜像（longhorn-csi-plugin / instance-manager / csi-metadata）
    #    以及 csi-attacher/provisioner/resizer/snapshotter/livenessprobe
    #    不在 chart 模板里，而是由 longhorn-manager 在运行时按自身版本拉取，
    #    tag 随 longhorn 版本变化，无法在 chart 侧静态确定。
    #    → 启用 longhorn 后，用下面的命令拉取实际版本后再补推:
    #      kubectl -n longhorn-system get deploy longhorn-csi-plugin -o jsonpath='{.spec.template.spec.containers[*].image}'
    #    → 这些镜像走 registry.k8s.io / docker.io，containerd 会命中 zot 的对应命名空间

    # ── argocd ──
    # 上游默认指向 ecr-public.aws.com/docker/library/redis，
    # 该域名在本网络可达(401)，且不在 registries.yaml 的 mirror 覆盖范围 → 直连
    "quay.io/argoproj/argocd:v3.5.5|"
    "ecr-public.aws.com/docker/library/redis:8.6.4-alpine|"
)

# ── 检查 / 推送 ───────────────────────────────────────────
command -v docker >/dev/null 2>&1 || { echo "[ERR] 未找到 docker"; exit 1; }

MISSING=0
echo "======================================================================"
echo " 镜像预热清单检查 (zot: ${ZOT_REGISTRY})"
echo "======================================================================"

for entry in "${IMAGES[@]}"; do
    src="${entry%%|*}"
    dst="${entry##*|}"

    if [ -z "$dst" ]; then
        # 无 zot 命名空间映射 → 直连上游（无需预热）
        printf "  [直连] %-70s\n" "$src"
        continue
    fi

    repo="${dst%%:*}"
    tag="${dst##*:}"
    path="${repo}"
    if [ "$CHECK_ONLY" = "1" ]; then
        if curl -fsS --max-time 10 "${ZOT_REGISTRY}/v2/${path}/manifests/${tag}" >/dev/null 2>&1; then
            printf "  [OK]   %-70s\n" "$dst"
        else
            printf "  [缺失] %-70s\n" "$dst"
            MISSING=$((MISSING+1))
        fi
        continue
    fi

    echo ">> 拉取并推送 ${src} -> ${dst}"
    docker pull "$src"
    docker tag "$src" "${ZOT_REGISTRY}/${dst}"
    docker push "${ZOT_REGISTRY}/${dst}"
done

echo ""
if [ "$CHECK_ONLY" = "1" ]; then
    echo "缺失镜像数: ${MISSING}"
    [ "$MISSING" -gt 0 ] && exit 1
fi
echo "[OK] 镜像预热完成"
