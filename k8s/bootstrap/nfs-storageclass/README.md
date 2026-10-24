# NFS StorageClass — 共享存储（ReadWriteMany）

集群内自建 NFS 服务器（内核 nfsd）+ `nfs-subdir-external-provisioner`，提供 `nfs-client` StorageClass（默认 SC），适合共享配置、日志、静态文件。不适合数据库类高并发 IO（那种场景用 Longhorn）。

## 安装

```bash
# === Step 1: 部署基于内核 nfsd 的 NFS 服务器 ===
# 宿主机必须已加载 nfsd 内核模块, 否则容器会因 "Protocol not supported" 反复退出
#
echo ">> 检查 nfsd 内核模块 ..."
if ! lsmod 2>/dev/null | grep '^nfsd ' >/dev/null; then
    echo "[ERROR] 宿主机未加载 nfsd 内核模块, NFS Server 无法启动"
    echo "        请先执行: sudo modprobe nfs && sudo modprobe nfsd"
    echo "        并配置开机自启: echo -e 'nfs\\nnfsd\\n' | sudo tee /etc/modules-load.d/nfs.conf"
    exit 1
fi
echo "[OK]   nfsd 内核模块已加载"

bash k8s/bootstrap/install.sh nfs-storageclass

# 去除 defalut local-path
kubectl patch sc local-path \
  -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'
```

前置：所有节点已加载 `nfs` + `nfsd` 内核模块（`scripts/linux/k3s-single/install-k3s.sh` 的 `setup_nfs_kernel` 负责安装并开机自启；ansible linux-init 亦已包含）。
宿主机缺少 `nfsd` 模块时，NFS Server 容器会以 `Protocol not supported` 反复退出。


## 验证

```bash
kubectl get sc                                  # nfs-client
kubectl -n nfs-storageclass get pods

kubectl apply -f test-pvc.yaml
kubectl get pvc test-nfs-pvc                    # STATUS=Bound
```

## 使用

PVC 中指定 `storageClassName: nfs-client` 即可，完整示例见 `example-app.yaml`。

> `reclaimPolicy: Delete`：PVC 删除后数据目录一并删除，重要数据自行备份。

## 清理

```bash
helm uninstall nfs-provisioner -n nfs-storageclass
kubectl delete namespace nfs-storageclass
```
