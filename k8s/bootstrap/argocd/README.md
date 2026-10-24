# ArgoCD 引导安装

ArgoCD 是 GitOps 引擎，放在**引导层**（`../bootstrap/`），原因见
[../gitops/README.md](../gitops/README.md#为什么-cni-必须在-l1)。

## 组件信息

| 项 | 值 |
|----|-----|
| Chart | `argo-cd` 10.11.1（ArgoCD v3.5.5） |
| 上游源 | `https://argoproj.github.io/argo-helm` / `github.com/argoproj/argo-helm` release |
| 命名空间 | `argocd` |
| 访问方式 | NodePort `30800`（HTTP）/ `30443`（HTTPS） |

chart 已 vendored 在本目录，仅在缺失时从官方 release 兜底下载。

## 前置条件

- Cilium 已就绪（Pod 网络可用）
- `kubectl` / `helm` 可用且能连上集群
- Git 仓库可读（SSH deploy key 或其它凭据）

## 使用

```bash
# 默认仓库 + 自动生成 deploy key 提示
bash install.sh

# 指定 Git 仓库与 deploy key 私钥
bash install.sh --repo ssh://git@github.com/jory-callan/env-devlab.git \
                --ssh-key ~/.ssh/argocd_gitops
```

`--ssh-key` 指向 **私钥**。对应的公钥需在 GitHub 仓库设置中登记为
**read-only Deploy key**。

## 安装内容

1. Helm 安装 ArgoCD（NodePort 暴露，单节点副本数全部为 1）
2. 创建仓库凭据 Secret `argocd-repo-secret`（含 `sshPrivateKey` + `known_hosts`）
3. 渲染并下发 root App-of-Apps（`../../gitops/root/root-app.yaml`）

## 访问

```bash
# 端口转发（推荐）
kubectl -n argocd port-forward svc/argocd-server 8080:80
# 打开 http://localhost:8080

# 或直接访问 NodePort
# http://<节点IP>:30800

# 初始密码
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo
```

## 验证

```bash
kubectl -n argocd get pods            # 全部 Running
kubectl -n argocd get applications    # root Healthy，各层逐层 Healthy
kubectl -n argocd get appprojects     # infra-core / platform / apps
```

## 回滚

```bash
helm uninstall argocd -n argocd
kubectl delete ns argocd
```

不影响 k3s 与已有集群组件。
