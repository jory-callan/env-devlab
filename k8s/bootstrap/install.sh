#!/bin/bash
# install.sh -- 引导层安装（一次性执行）
#
# 分层模型:
#   L1 引导层（本脚本）  → cilium（Pod 网络）+ argocd（GitOps 引擎）
#   L2 声明层（ArgoCD）  → infra-core / platform / apps 三层
#
# 引导层只装两样东西:
#   - cilium: ArgoCD 自身是 Pod，没有 CNI 就起不来（引导循环）
#   - argocd: 装完即交出控制权，其余组件由 ArgoCD 持续调谐
#
# 用法:
#   bash install.sh                          # cilium → argocd
#   bash install.sh cilium                   # 只装 Cilium
#   bash install.sh argocd --ssh-key <path>  # 指定 Git deploy key
#   bash install.sh argocd --repo <url>      # 指定 Git 仓库
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"

# 引导层组件（顺序不可调换: cilium 必须先于 argocd）
BOOTSTRAP_COMPONENTS=("cilium" "argocd")

# ── 前置检查：kubectl / helm 可用 ─────────────────────────────
if ! command -v kubectl >/dev/null 2>&1; then
    echo "[ERR] 未找到 kubectl，请先执行 install-k3s.sh"
    exit 1
fi
if ! command -v helm >/dev/null 2>&1; then
    echo "[ERR] 未找到 helm，请先执行 install-k3s.sh"
    exit 1
fi
if ! kubectl get node >/dev/null 2>&1; then
    echo "[ERR] 无法连接集群，请检查 ~/.kube/config"
    exit 1
fi

# ── 参数解析（仅 argocd 需要）────────────────────────────────
TARGET="$1"
shift || true
EXTRA_ARGS=("$@")

install_component() {
    local comp="$1"
    shift
    if [ ! -f "$comp/install.sh" ]; then
        echo "[ERR] 未知组件: $comp (未找到 $comp/install.sh)"
        exit 1
    fi
    echo ""
    echo "==============================================="
    echo ">> 安装 $comp ..."
    echo "==============================================="
    bash "$comp/install.sh" "$@"
    echo "[OK] $comp 完成"
}

if [ -n "$TARGET" ]; then
    case "$TARGET" in
        cilium|argocd)
            install_component "$TARGET" "${EXTRA_ARGS[@]:-}" ;;
        *)
            echo "[ERR] 引导层只支持: cilium | argocd"
            echo "      其余组件由 ArgoCD 接管（见 k8s/gitops/）"
            exit 1 ;;
    esac
else
    for comp in "${BOOTSTRAP_COMPONENTS[@]}"; do
        install_component "$comp" "${EXTRA_ARGS[@]:-}"
    done
fi

echo ""
echo "==============================================="
echo "[OK] 引导层安装完成"
echo "==============================================="
echo ""
echo "后续组件由 ArgoCD 自动接管（查看收敛进度）:"
echo "  kubectl -n argocd get applications -w"
echo ""
echo "ArgoCD UI:"
echo "  kubectl -n argocd port-forward svc/argocd-server 8080:80"
echo "  打开 http://localhost:8080"
