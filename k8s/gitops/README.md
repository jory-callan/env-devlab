# GitOps 声明层 — 三层架构

本目录是 **ArgoCD 消费**的声明层。引导层（`../bootstrap/`）装完 ArgoCD 后，
集群内所有组件都由这里持续调谐。

## 分层模型

```
L2 声明层（本目录，ArgoCD 持续调谐）
├── root/          App-of-Apps 根入口 + 三层 AppProject
├── infra-core/    集群核心：MetalLB / ingress-nginx / cert-manager / 存储
├── platform/      平台层：VictoriaMetrics k8s stack（可观测性）
└── apps/          业务应用层
```

对应的引导层（`../bootstrap/`）只做两件事，**因为存在引导循环**：

| 组件 | 为什么在引导层 | 后续归属 |
|------|----------------|----------|
| Cilium | ArgoCD 自身是 Pod，没有 CNI 起不来 | 可迁移至 infra-core（待 ArgoCD 自身稳定后） |
| ArgoCD | 它是 GitOps 引擎本身，不能自己管理自己 | 保持脚本安装 |

## 目录结构

```
gitops/
├── root/
│   ├── root-app.yaml              App-of-Apps 入口（占位符由 install.sh 渲染）
│   └── children/
│       ├── appprojects.yaml       三层 AppProject（权限隔离）
│       └── apps/*.yaml            各组件的 Application 定义
├── infra-core/
│   └── <component>/
│       ├── chart/                 上游 chart（vendored，含 values-override.yaml）
│       └── manifests/             额外 CR（IPAddressPool / ClusterIssuer 等）
├── platform/
│   └── victoria-metrics-k8s-stack/
│       ├── chart/
│       └── manifests/
├── apps/
│   └── hello-world/               业务应用示例
└── render-repo.sh                 统一改写仓库地址
```

## 为什么 chart 要 vendored 进仓库

集群侧访问上游 helm 仓库不稳定（实测 `charts.jetstack.io` / `github.com` 时通时断），
而 ArgoCD 渲染 chart 需要能访问 chart 源。因此把上游 chart 固化进 Git：

- ArgoCD 渲染时**不访问任何外部仓库**，只读 Git 里的 chart 目录
- chart 版本随 Git 提交固定，可审计、可回滚
- 兜底下载仍在 chart 的上游官方地址（见各组件 README）

## 同步波次（sync wave）

| wave | 组件 | 依赖理由 |
|------|------|----------|
| -3 | metallb | 提供 LoadBalancer IP，是 ingress 对外暴露的前提 |
| -2 | ingress-nginx | 依赖 metallb 分配到 IP |
| -1 | cert-manager | 应用签发证书前须就绪 |
| 0 | nfs-storageclass / longhorn | 存储供给，不阻塞上面三者 |
| 1 | victoria-metrics | 平台层，依赖 nfs-client 存储类 |
| 2 | hello-world | 业务应用，依赖入口与证书 |

## 权限模型

三个 AppProject 隔离，详见 [root/children/appprojects.yaml](root/children/appprojects.yaml)：

| Project | 目标 namespace | clusterResource 白名单 |
|---------|----------------|------------------------|
| infra-core | metallb-system / ingress-nginx / cert-manager / nfs-storageclass / longhorn-system | 全部 |
| platform | monitoring | 仅 monitoring.coreos.com / operator.victoriametrics.com / CRD |
| apps | apps | **空** —— 业务应用不得创建集群级资源 |

## 使用

```bash
# 引导层安装（装 Cilium + ArgoCD，并下发 root app）
bash k8s/bootstrap/install.sh

# 查看收敛进度
kubectl -n argocd get applications -w

# UI
kubectl -n argocd port-forward svc/argocd-server 8080:80
```

## 变更仓库地址

`children/` 下的 Application 定义由 ArgoCD **从 Git 读取**，ArgoCD 不支持对普通 YAML
做变量替换，因此仓库地址必须是字面量。变更时统一改写：

```bash
bash k8s/gitops/render-repo.sh <repo-url> [revision]
git diff -- k8s/gitops/ && git commit -am "chore: update gitops repo url"
```

## 注意事项

1. **接管已有资源**：本目录假设集群是全新的。若集群已有 `helm install` 的同名组件，
   ArgoCD 首次同步会因缺少 tracking annotation 判为"孤儿资源"，开启 prune 后会被删除重建。
   → 全新安装时不存在此问题；存量迁移请先 `helm uninstall`。
2. **CRD 顺序**：metallb / cert-manager / longhorn 的 CRD 由 chart 提供，
   ArgoCD 会在同一 Application 内按 CRD 优先排序。
3. **单节点**：所有组件副本数显式设为 1，避免反亲和导致 Pending（cilium operator 已踩过此坑）。
4. **NFS 固定 ClusterIP**：`nfs-storageclass` 的 Service 使用固定 `clusterIP: 10.43.200.10`，
   因为 provisioner chart 需要写死 `nfs.server`。改这个 IP 需同步改
   `infra-core/nfs-storageclass/chart/values-override.yaml`。
