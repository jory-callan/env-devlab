# Bootstrap — 引导层（一次性执行）

本目录只负责**把集群从零带到"ArgoCD 已就绪"**这一步。装完之后，
集群内所有组件由 [../gitops/](../gitops/) 持续调谐。

## 引导层组件

| 组件 | 目录 | 为什么在引导层 | 后续归属 |
|------|------|----------------|----------|
| Cilium | [cilium/](cilium/) | ArgoCD 自身是 Pod，没有 CNI 起不来（引导循环） | 可迁至 infra-core |
| ArgoCD | [argocd/](argocd/) | GitOps 引擎本身，不能自己管理自己 | 保持脚本安装 |

依赖顺序：**Cilium → ArgoCD**

## 使用

```bash
# 安装引导层全部组件
bash k8s/bootstrap/install.sh

# 只装 Cilium
bash k8s/bootstrap/install.sh cilium

# 装 ArgoCD 并指定 Git 凭据
bash k8s/bootstrap/install.sh argocd \
  --repo ssh://git@github.com/jory-callan/env-devlab.git \
  --ssh-key ~/.ssh/argocd_gitops
```

安装完成后：

```bash
kubectl -n argocd get applications -w   # 观察三层收敛
kubectl -n argocd port-forward svc/argocd-server 8080:80
```

## 已迁移至 GitOps 的组件（脚本仅作回退保留）

以下组件的**声明式定义**已迁至 [../gitops/infra-core/](../gitops/infra-core/)，
由 ArgoCD 管理。本目录中的 `install.sh` **不再被 `install.sh` 主流程调用**，
仅在需要"绕过 ArgoCD 手工安装/排障"时使用。

| 组件 | GitOps 定义 | 原脚本 |
|------|-------------|--------|
| MetalLB | `../gitops/infra-core/metallb/` | [metallb/](metallb/) |
| ingress-nginx | `../gitops/infra-core/ingress-nginx/` | [ingress-nginx/](ingress-nginx/) |
| cert-manager | `../gitops/infra-core/cert-manager/` | [cert-manager/](cert-manager/) |
| NFS StorageClass | `../gitops/infra-core/nfs-storageclass/` | [nfs-storageclass/](nfs-storageclass/) |
| Longhorn | `../gitops/infra-core/longhorn/` | [longhorn/](longhorn/) |
| VictoriaMetrics stack | `../gitops/platform/victoria-metrics-k8s-stack/` | —（原 `k8s/monitoring/`） |

> ⚠️ **不要同时用脚本和 ArgoCD 管理同一组件** —— 会产生所有权冲突与资源漂移。
> 二选一。

## 官方源对照

所有 chart 源均为上游官方维护地址，不使用任何第三方加速镜像站：

| 组件 | 官方源 |
|------|--------|
| Cilium | `https://helm.cilium.io` |
| ArgoCD | `https://argoproj.github.io/argo-helm` |
| MetalLB | `https://github.com/metallb/metallb/releases` |
| ingress-nginx | `https://github.com/kubernetes/ingress-nginx/releases` |
| cert-manager | `https://charts.jetstack.io` |
| NFS Provisioner | `https://github.com/kubernetes-sigs/nfs-subdir-external-provisioner/releases` |
| Longhorn | `https://charts.longhorn.io` |
| VictoriaMetrics | `https://github.com/VictoriaMetrics/helm-charts/releases` |

chart 均已 vendored 在各自目录，仅在本地缺失时才从官方源下载。

## 镜像预热

zot (`192.168.5.103:20000`) 是**预缓存式**仓库，不是 pull-through 代理。
官方 `registry.k8s.io` 会 307 重定向到 GCS，从本网络超时；containerd 的 mirror
**不做回退** → zot 未命中即拉取失败。

```bash
bash k8s/bootstrap/preload-images.sh --check   # 检查缺失
bash k8s/bootstrap/preload-images.sh            # 拉取并推送
```

## 其他脚本

| 脚本 | 作用 |
|------|------|
| [preload-images.sh](preload-images.sh) | 镜像预热/检查清单 |
| [taint-control-plane.sh](taint-control-plane.sh) | 给控制平面节点打 NoSchedule 污点 |
| [fix-k3s-metrics.sh](fix-k3s-metrics.sh) | 修复 k3s 内置 metrics-server 的 selector 不匹配问题 |

## 约定

- 脚本需要 `helm` + `kubectl` 可用（在控制节点执行）
- DNS 约定：`*.czw-sre.internal` 指向 ingress-nginx 的 LoadBalancer IP
- 各组件详细说明见各自目录下的 README.md
