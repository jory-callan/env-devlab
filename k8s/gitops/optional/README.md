# 可选组件（不随 root App-of-Apps 自动同步）

放在这里的 Application **不会被 root app 自动创建/同步**。需要时手工 apply：

```bash
kubectl apply -f k8s/gitops/optional/<file>.yaml
```

## longhorn

| 项 | 说明 |
|----|------|
| Application | `infra-core-longhorn.yaml` |
| 命名空间 | `longhorn-system` |
| 不自动同步的原因 | ① 节点仅 1 核 / 5.7Gi，Longhorn（manager + engine + instance-manager + UI）资源占用重；② chart 内置 3 个 Helm hook Job（`pre-upgrade` / `post-upgrade` / `pre-delete`），ArgoCD 的 hook 语义与 Helm 不同，`pre-upgrade` 会永远 Running 并卡住同步，`pre-delete` 的 uninstall Job 甚至会真的删除 Longhorn CR |

### 启用步骤

```bash
# 1. 确认前置条件
#    - open-iscsi 已安装、iscsi_tcp 模块已加载
#    - /var/lib/longhorn 有可用存储目录
ssh root@192.168.5.143 'isciadm -V; lsmod | grep iscsi_tcp; df -h /var/lib/longhorn'

# 2. 应用 Application（ArgoCD 会自动 sync）
kubectl apply -f k8s/gitops/optional/infra-core-longhorn.yaml

# 3. 观察
kubectl -n argocd get app longhorn -w
```

### 已被 values 覆盖处理的部分

`k8s/gitops/infra-core/longhorn/chart/values-override.yaml` 已设置：

- `preUpgradeChecker.jobEnabled: false` —— 禁用 pre-upgrade 检查 Job
- `defaultSettings.replicaCount: 1` —— 单节点 1 副本
- `persistence.defaultStorageClass: false` —— 不抢默认 StorageClass（默认是 nfs-client）
- `csi.kubeletRootDir: /var/lib/rancher/k3s/agent/kubelet` —— 与 k3s data-dir 对齐
- `service.ui.type: NodePort` + `nodePort: 30777`

`post-upgrade` / `pre-delete` 两个 Job 在 chart 中**无 values 开关**，故不放进自动同步。
