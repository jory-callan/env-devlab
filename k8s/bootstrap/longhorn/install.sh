#!/bin/bash
# install.sh -- 安装 Longhorn 分布式存储
#
# 前置条件:
#   - open-iscsi / iscsi-initiator-utils 已安装（linux-init 已配置）
#   - iscsi_tcp 内核模块已加载（linux-init 已配置）
#   - kubectl 连接正常
#   - K3S_DATA_DIR 与 k3s 实际 data-dir 一致
set -euo pipefail

NAMESPACE="longhorn-system"
LONGHORN_VERSION="1.12.0"
# 官方 helm 仓库(上游维护); 本地 chart 已 vendored, 仅在缺失时兜底下载
CHART_REPO_URL="https://charts.longhorn.io"
CHART_FILE="$(cd "$(dirname "$0")" && pwd)/longhorn-${LONGHORN_VERSION}.tgz"
# k3s 的 kubelet socket 路径，与 k3s data-dir 保持一致
# 默认取 k3s 实际 data-dir (/var/lib/rancher/k3s), 仅在自定义时用 K3S_DATA_DIR 覆盖
K3S_DATA_DIR="${K3S_DATA_DIR:-/var/lib/rancher/k3s}"

# 检查是否已安装
if helm list -n "$NAMESPACE" 2>/dev/null | grep -q longhorn; then
    echo "[INFO] Longhorn 已安装，跳过"
    exit 0
fi

# ==============================================
# Step 1: 前置检查
# ==============================================
echo ">> 检查前置依赖 ..."

# 检查 open-iscsi
if ! command -v iscsiadm &>/dev/null; then
    echo "[WARN] iscsiadm 未安装。Longhorn 依赖 open-iscsi/iscsi-initiator-utils"
    echo "       请先执行 Ansible linux-init playbook 安装，或手动安装:"
    echo "       RedHat: yum install -y iscsi-initiator-utils"
    echo "       Debian: apt install -y open-iscsi"
    echo ""
fi

# 检查 iscsi_tcp 内核模块
if ! lsmod 2>/dev/null | grep -q iscsi_tcp; then
    echo "[WARN] iscsi_tcp 模块未加载，尝试加载 ..."
    modprobe iscsi_tcp 2>/dev/null || echo "[WARN] 请手动加载: modprobe iscsi_tcp"
fi

# k3s 的 data-dir 可能被自定义, 从 systemd 单元读取真实值
K3S_DATA_DIR=$(systemctl show k3s --property=Environment --value 2>/dev/null \
  | grep -oE 'K3S_DATA_DIR=[^ ]+' | cut -d= -f2 || true)
K3S_DATA_DIR="${K3S_DATA_DIR:-/var/lib/rancher/k3s}"
echo "    K3S data-dir: ${K3S_DATA_DIR}"
echo "    K3S kubelet: ${K3S_DATA_DIR}/agent/kubelet"

# ==============================================
# Step 2: 安装 Longhorn
# ==============================================
# 本地 chart 不存在时，从官方 helm 仓库下载
if [ ! -f "$CHART_FILE" ]; then
    echo ">> 本地 chart 未找到，从官方源下载 Longhorn ${LONGHORN_VERSION} ..."
    curl -fsSL "${CHART_REPO_URL}/longhorn-${LONGHORN_VERSION}.tgz" \
      -o "$CHART_FILE" --connect-timeout 30 --retry 3
fi

echo ">> 安装 Longhorn ${LONGHORN_VERSION} ..."
helm upgrade --install longhorn "$CHART_FILE" \
    --namespace "$NAMESPACE" --create-namespace \
    --set defaultSettings.replicaCount=1 \
    --set persistence.defaultStorageClass=false \
    --set csi.kubeletRootDir="${K3S_DATA_DIR}/agent/kubelet" \
    --set service.ui.type=NodePort \
    --set service.ui.nodePort=30777 \
    --wait --timeout 10m

echo "[OK] Longhorn 安装完成"

# 确保 longhorn StorageClass 不抢占默认
echo ">> 确保 longhorn 不是默认 StorageClass ..."
kubectl annotate sc longhorn storageclass.kubernetes.io/is-default-class- --overwrite 2>/dev/null || true
kubectl get sc -o custom-columns=NAME:.metadata.name,DEFAULT:.metadata.annotations.\"storageclass\\.kubernetes\\.io/is-default-class\" 2>/dev/null | grep longhorn || true

# ==============================================
# Step 3: 验证安装结果
# ==============================================
echo ""
echo "================================================"
echo "  验证 Longhorn 组件状态"
echo "================================================"

echo ">> 等待 Longhorn Manager 就绪 ..."
kubectl -n "$NAMESPACE" wait --for=condition=available --timeout=120s deployment/longhorn-manager 2>/dev/null || true

echo ""
echo "  Pods:"
kubectl -n "$NAMESPACE" get pods -o wide 2>/dev/null | head -20 || echo "  （暂无）"
echo ""
echo "  StorageClasses:"
kubectl get sc 2>/dev/null | grep -E "longhorn|NAME" || echo "  （暂无）"

echo ""
echo "================================================"
echo "  Longhorn UI 访问"
echo "================================================"
echo ""

LONGHORN_NODE=$(kubectl -n "$NAMESPACE" get pods -l app=longhorn-ui -o jsonpath='{.items[0].spec.nodeName}' 2>/dev/null)
if [ -n "$LONGHORN_NODE" ]; then
    echo "  方式 1 — NodePort（当前集群任意节点 IP）:"
    echo "    http://<任意节点IP>:30777"
    echo ""
fi
echo "  方式 2 — 端口转发（本地开发机执行）:"
echo "    kubectl -n ${NAMESPACE} port-forward svc/longhorn-frontend 8080:80"
echo "    然后打开 http://localhost:8080"
echo ""
echo "  方式 3 — Ingress（已自动部署）:"
echo "    https://longhorn.czw-sre.internal"
echo ""

echo "================================================"
echo "  存储磁盘配置"
echo "================================================"
echo ""
echo "  Longhorn 默认使用 /var/lib/longhorn/ 作为存储目录。"
echo ""
echo "  >> 如需使用 200G 数据盘，请在各节点上执行:"
echo ""
echo '    # 1. 找到 200G 数据盘设备名'
echo '    lsblk -dno NAME,SIZE | grep "200G"'
echo ""
echo '    # 2. 格式化并挂载（假设设备为 /dev/sdb，按实际设备名调整）'
echo '    sudo mkfs.ext4 /dev/sdb'
echo '    sudo mkdir -p /var/lib/longhorn'
echo '    sudo mount /dev/sdb /var/lib/longhorn'
echo '    echo "/dev/sdb /var/lib/longhorn ext4 defaults 0 0" | sudo tee -a /etc/fstab'
echo ""
echo '    # 3. 重启 longhorn-manager 识别新磁盘'
echo '    kubectl -n longhorn-system delete pods -l app=longhorn-manager'
echo ""
echo "  Longhorn UI → Node → Edit Node → Disks → 确认磁盘已正确识别。"
echo ""

echo "================================================"
echo "  验证命令"
echo "================================================"
echo ""
echo "  kubectl -n ${NAMESPACE} get pods"
echo "  kubectl get sc"
echo "  kubectl -n ${NAMESPACE} get volumes"
echo ""

echo ">> 注意: replicaCount=1（测试配置），数据只有 1 份副本，节点故障会丢失数据。"
echo ">> 生产环境请设为 2 或 3，并确保多节点有存储盘。"

# ==============================================
# Step 4: 部署 Ingress
# ==============================================
echo ""
echo "================================================"
echo "  部署 Longhorn UI Ingress"
echo "================================================"
INGRESS_FILE="$(dirname "$0")/ingress.yaml"
if [ -f "$INGRESS_FILE" ]; then
    kubectl apply -f "$INGRESS_FILE" 2>/dev/null || true
    echo "  Ingress: https://longhorn.czw-sre.internal"
else
    echo "  [WARN] $INGRESS_FILE 不存在，跳过 Ingress 部署"
fi
