#!/bin/bash
# install.sh -- 安装 NFS StorageClass(动态 NFS 卷供给)
# 部署内部 NFS 服务器 + nfs-subdir-external-provisioner
# 前置条件: Cilium 已就绪，kubectl 连接正常
set -euo pipefail

NFS_NAMESPACE="nfs-storageclass"
PROVISIONER_VERSION="4.0.18"
# 官方 release 直链(上游维护); 本地 chart 已 vendored, 仅在缺失时兜底下载
CHART_URL="https://github.com/kubernetes-sigs/nfs-subdir-external-provisioner/releases/download/nfs-subdir-external-provisioner-${PROVISIONER_VERSION}/nfs-subdir-external-provisioner-${PROVISIONER_VERSION}.tgz"
CHART_FILE="$(cd "$(dirname "$0")" && pwd)/nfs-subdir-external-provisioner-${PROVISIONER_VERSION}.tgz"

# 检查是否已安装
if helm list -n "$NFS_NAMESPACE" 2>/dev/null | grep -q nfs-provisioner; then
    echo "[INFO]  NFS StorageClass 已安装，跳过"
    exit 0
fi

# === Step 1: 部署基于内核 nfsd 的 NFS 服务器 ===
# 宿主机必须已加载 nfsd 内核模块, 否则容器会因 "Protocol not supported" 反复退出

echo ">> 部署 NFS 服务器 ..."
# 注意: 不吞掉错误, 否则 NFS Server 起不来时后续步骤会一路失败到难以定位
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: nfs-storageclass
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: nfs-server-data
  namespace: nfs-storageclass
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 50Gi
  storageClassName: local-path
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nfs-server
  namespace: nfs-storageclass
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nfs-server
  template:
    metadata:
      labels:
        app: nfs-server
    spec:
      containers:
        - name: nfs-server
          image: erichough/nfs-server:latest
          imagePullPolicy: Always
          ports:
            - containerPort: 2049
              name: nfs
            - containerPort: 20048
              name: mountd
            - containerPort: 111
              name: rpcbind
          securityContext:
            privileged: true
          volumeMounts:
            - name: nfs-storage
              mountPath: /exports
          env:
            - name: NFS_EXPORT_0
              value: "/exports *(rw,sync,no_subtree_check,insecure,no_root_squash,fsid=0)"
      volumes:
        - name: nfs-storage
          persistentVolumeClaim:
            claimName: nfs-server-data
---
apiVersion: v1
kind: Service
metadata:
  name: nfs-server
  namespace: nfs-storageclass
  labels:
    app: nfs-server
spec:
  type: ClusterIP
  ports:
    - name: nfs
      port: 2049
      protocol: TCP
    - name: mountd
      port: 20048
      protocol: TCP
    - name: rpcbind
      port: 111
      protocol: TCP
  selector:
    app: nfs-server
EOF

echo "[WAIT] 等待 NFS 服务器就绪 ..."
kubectl -n "$NFS_NAMESPACE" wait --for=condition=available --timeout=120s deployment/nfs-server

# 获取 NFS 服务器 ClusterIP
NFS_SERVER_IP=$(kubectl -n "$NFS_NAMESPACE" get svc nfs-server -o jsonpath='{.spec.clusterIP}')
echo "   NFS Server IP: ${NFS_SERVER_IP}"

# === Step 2: 安装 nfs-subdir-external-provisioner ===
# 本地 chart 不存在时，从官方 release 下载
if [ ! -f "$CHART_FILE" ]; then
    echo ">> 本地 chart 未找到，从官方源下载 nfs-subdir-external-provisioner ${PROVISIONER_VERSION} ..."
    curl -fsSL "$CHART_URL" -o "$CHART_FILE" --connect-timeout 30 --retry 3
fi

echo ">> 安装 nfs-subdir-external-provisioner ..."
helm upgrade --install nfs-provisioner "$CHART_FILE" \
    --namespace "$NFS_NAMESPACE" \
    --set nfs.server="${NFS_SERVER_IP}" \
    --set nfs.path=/ \
    --set storageClass.name=nfs-client \
    --set storageClass.defaultClass=true \
    --set storageClass.allowVolumeExpansion=true \
    --set storageClass.reclaimPolicy=Delete \
    --set storageClass.accessModes=ReadWriteMany \
    --set mountOptions="{vers=3,hard,intr,sync,timeo=600,retrans=5}" \
    --set leaderElection.enabled=true \
    --wait --timeout 5m

echo "[OK] NFS StorageClass 安装完成"
echo ""
echo "   StorageClass: nfs-client (ReadWriteMany)"
echo "   内部 NFS Server: ${NFS_SERVER_IP}:2049（内核 nfsd）"
echo ""
echo "   验证:"
echo "     kubectl get sc"
echo "     kubectl -n nfs-storageclass get pods"
echo ""
echo "   测试:"
echo "     kubectl apply -f test-pvc.yaml"
echo "     kubectl get pvc test-nfs-pvc"

# 设置 defalut 
# echo "移除 local-path 的 default 标记"
# kubectl patch storageclass local-path \
#   -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'
# echo "设置 nfs-client 的 default 标记"
# kubectl patch storageclass nfs-client \
#   -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'