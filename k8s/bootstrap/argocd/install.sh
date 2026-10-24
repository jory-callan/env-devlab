#!/bin/bash
# install.sh -- 引导安装 ArgoCD（GitOps 引擎）
#
# 定位: 这是 GitOps 的"引导层"，一次性执行。
# 装完之后，集群内三层（infra-core / platform / apps）由 ArgoCD 持续调谐。
#
# 前置条件:
#   - Cilium 已就绪（Pod 网络可用）
#   - kubectl / helm 可用且能连上集群
#
# 用法:
#   bash install.sh                       # 使用默认仓库地址
#   bash install.sh --repo <git-url>      # 指定 Git 仓库
#   bash install.sh --ssh-key <path>      # 指定 deploy key 私钥（SSH 方式时需要）
set -euo pipefail

ARGOCD_VERSION="10.11.1"      # chart 版本 (ArgoCD v3.5.5)
ARGOCD_APP_VERSION="v3.5.5"
NAMESPACE="argocd"
RELEASE="argocd"
DIR="$(cd "$(dirname "$0")" && pwd)"

# ── 可覆盖参数 ───────────────────────────────────────────
REPO_URL="ssh://git@github.com/jory-callan/env-devlab.git"
REPO_REVISION="main"
SSH_KEY_FILE=""
REPO_SECRET_NAME="argocd-repo-secret"

while [ $# -gt 0 ]; do
    case "$1" in
        --repo)       REPO_URL="$2"; shift 2 ;;
        --revision)   REPO_REVISION="$2"; shift 2 ;;
        --ssh-key)    SSH_KEY_FILE="$2"; shift 2 ;;
        -h|--help)
            sed -n '2,20p' "$0"; exit 0 ;;
        *) echo "[ERR] 未知参数: $1"; exit 1 ;;
    esac
done

# ── 前置检查 ─────────────────────────────────────────────
command -v kubectl >/dev/null 2>&1 || { echo "[ERR] 未找到 kubectl"; exit 1; }
command -v helm    >/dev/null 2>&1 || { echo "[ERR] 未找到 helm"; exit 1; }
kubectl get node >/dev/null 2>&1 || { echo "[ERR] 无法连接集群"; exit 1; }

echo ">> 检查 CNI 是否就绪 ..."
if ! kubectl get pods -n kube-system -l k8s-app=cilium -o name 2>/dev/null | grep -q .; then
    echo "[ERR] 未检测到 Cilium Pod，Pod 网络不可用，无法安装 ArgoCD"
    echo "      请先执行: bash ../install.sh cilium"
    exit 1
fi

# ── chart ────────────────────────────────────────────────
# 上游 chart 来自 argoproj/argo-helm release（官方维护）;
# 本地已 vendored，仅在缺失时兜底下载
CHART_FILE="$DIR/argo-cd-${ARGOCD_VERSION}.tgz"
CHART_URL="https://github.com/argoproj/argo-helm/releases/download/argo-cd-${ARGOCD_VERSION}/argo-cd-${ARGOCD_VERSION}.tgz"
if [ ! -f "$CHART_FILE" ]; then
    echo ">> 本地 chart 未找到，从官方源下载 ArgoCD chart ${ARGOCD_VERSION} ..."
    curl -fsSL "$CHART_URL" -o "$CHART_FILE" --connect-timeout 30 --retry 3
fi

# ── 安装 / 升级 ─────────────────────────────────────────
echo ">> 安装 ArgoCD (${ARGOCD_APP_VERSION}) ..."
helm upgrade --install "$RELEASE" "$CHART_FILE" \
    --namespace "$NAMESPACE" --create-namespace \
    --values "$DIR/values.yaml" \
    --set global.image.tag="$ARGOCD_APP_VERSION" \
    --wait --timeout 10m

# ── 仓库凭据 ─────────────────────────────────────────────
# ArgoCD 需要凭据读取 Git 仓库。优先使用 SSH deploy key（只读、范围最小），
# 未提供私钥时跳过并提示（ArgoCD 仍可安装，只是拉不到仓库）。
if [ -n "$SSH_KEY_FILE" ]; then
    if [ ! -f "$SSH_KEY_FILE" ]; then
        echo "[ERR] SSH 私钥不存在: $SSH_KEY_FILE"
        exit 1
    fi
    echo ">> 创建仓库凭据 Secret: $REPO_SECRET_NAME ..."
    kubectl -n "$NAMESPACE" create secret generic "$REPO_SECRET_NAME" \
        --from-file=sshPrivateKey="$SSH_KEY_FILE" \
        --from-literal=type=git \
        --from-literal=url="$REPO_URL" \
        --dry-run=client -o yaml | kubectl apply -f -

    # known_hosts: 用 ssh-keyscan 现场取，防止 host key 伪造
    HOST=$(printf '%s' "$REPO_URL" | sed -E 's#^ssh://git@([^:/]+).*#\1#')
    echo ">> 采集 $HOST 的 host key ..."
    ssh-keyscan -t rsa,ecdsa,ed25519 "$HOST" 2>/dev/null > "$DIR/known_hosts" || true
    if [ ! -s "$DIR/known_hosts" ]; then
        echo "[ERR] 无法采集 $HOST 的 host key，SSH 拉取会被拒绝"
        exit 1
    fi
    kubectl -n "$NAMESPACE" create secret generic "$REPO_SECRET_NAME" \
        --from-file=sshPrivateKey="$SSH_KEY_FILE" \
        --from-file=known_hosts="$DIR/known_hosts" \
        --from-literal=type=git \
        --from-literal=url="$REPO_URL" \
        --dry-run=client -o yaml | kubectl apply -f -
else
    echo "[WARN] 未提供 --ssh-key，跳过仓库凭据创建"
    echo "       ArgoCD 已安装，但无法拉取 Git 仓库；"
    echo "       稍后可用 kubectl -n argocd create secret generic $REPO_SECRET_NAME \\"
    echo "         --from-file=sshPrivateKey=<key> --from-literal=type=git --from-literal=url=$REPO_URL"
fi

# ── 预建业务 namespace ─────────────────────────────────────
# AppProject "apps" 的 clusterResourceWhitelist 为空（业务应用层不得创建集群级资源），
# 因此 Namespace 不能由 apps 层自己声明，须在引导阶段预建。
echo ">> 预建业务 namespace: apps ..."
for ns in apps; do
    if kubectl get namespace "$ns" >/dev/null 2>&1; then
        echo "     [SKIP] namespace $ns 已存在"
    else
        kubectl create namespace "$ns" >/dev/null
        echo "     [OK] namespace $ns 已创建"
    fi
done

# ── 下发根应用 ───────────────────────────────────────────
# root App-of-Apps 的 repoURL 需要与环境实际使用的仓库一致，
# 这里按传入值渲染后再 apply（模板里的占位符替换）
ROOT_APP="$DIR/../../gitops/root/root-app.yaml"
if [ -f "$ROOT_APP" ]; then
    echo ">> 下发 root App-of-Apps ..."
    sed -e "s#__REPO_URL__#${REPO_URL}#" \
        -e "s#__REPO_REVISION__#${REPO_REVISION}#" \
        "$ROOT_APP" | kubectl apply -f -
else
    echo "[WARN] 未找到 $ROOT_APP，跳过 root 应用下发"
fi

echo ""
echo "[OK] ArgoCD 安装完成"
echo ""
echo "   访问方式(NodePort):"
NODE_IP=$(kubectl get node -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
echo "     http://${NODE_IP}:30800   (用户名 admin, 初始密码见下)"
echo ""
echo "   查看初始密码:"
echo "     kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo"
echo ""
echo "   仓库: ${REPO_URL} @ ${REPO_REVISION}"
echo "   凭据 Secret: ${REPO_SECRET_NAME}"
echo ""
echo "   下一步: 等待 ArgoCD 收敛三层 (infra-core / platform / apps)"
echo "     kubectl -n argocd get applications -w"
