# Longhorn — 分布式块存储（可选）

高可用块存储：多副本、快照、备份。资源占用较重（约 0.5 core + 1.5~2GB 内存），**未加入一键安装**，仅在需要时手动安装；小集群优先用 NFS（见 `../nfs-storageclass/`）。

## 安装

```bash
bash install.sh          # 在本目录执行
```

前置：节点已安装 open-iscsi 并加载 `iscsi_tcp` 模块（ansible linux-init 已包含）。

`K3S_DATA_DIR` 需与 k3s 实际 data-dir 一致，否则 CSI 驱动无法工作。脚本默认从
k3s systemd 单元自动读取真实 data-dir（通常为 `/var/lib/rancher/k3s`），
仅在 k3s 用了自定义 data-dir 且自动读取失败时才需手动指定：

```bash
K3S_DATA_DIR=/custom/k3s_data bash install.sh
```

安装完成后自动部署 Ingress（`longhorn.czw-sre.internal`），UI 也可通过 NodePort 30777 访问。

## 验证

```bash
kubectl -n longhorn-system get pods
kubectl get sc                                     # longhorn（非默认）

kubectl apply -f test-pvc.yaml
kubectl get pvc test-longhorn-pvc                  # STATUS=Bound
```

> 当前 `replicaCount=1` 仅适合测试，节点故障会丢数据；生产请设 2-3 副本。

## 清理

```bash
helm uninstall longhorn -n longhorn-system
kubectl delete namespace longhorn-system
kubectl get crd | grep longhorn | awk '{print $1}' | xargs kubectl delete crd
```

节点上残留存储目录手动清理：`rm -rf /var/lib/longhorn/`
