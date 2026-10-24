# 交接文档 — 三层 GitOps 架构落地

> 记录时间：2026-10-24 19:40 (Asia/Tokyo)
> 用途：新会话读取本文档后可直接接续，无需重新排查。

---

## 一、任务目标（用户明确表述）

> "我认为应该采用 分层 GitOps 架构 。即初始化允许采用脚本安装，完成后的所有都应该 gitops 管理，
> 例如 infra-core 层主要是 argocd Cilium StorageClass 等。第二个则是平台层，主要是 victoriametrics
> k8s stack 可观测技术栈，第三层才是业务 app 层。"

> "先调整好脚本和目录格式，先写一版本，写好了后，请通知我重置虚拟机，你全量重新跑验证一遍。"

---

## 二、当前状态

### ✅ 已完成并实测验证

| 项 | 状态 |
|---|---|
| 三层 GitOps 目录重构 | ✅ 完成 |
| `bootstrap/argocd/install.sh` | ✅ 真实安装成功，ArgoCD v3.5.5 |
| `gitops/` 三层骨架（3 AppProject + 7 Application + App-of-Apps） | ✅ 全部渲染并应用成功 |
| ArgoCD 从 GitHub 拉取 + 渲染 chart | ✅ 实测通过 |
| 权限隔离 | ✅ 实测生效（apps 层创建 Namespace 被拒） |
| 镜像预热清单 | ✅ 缺失数 0 |
| 代码已推送 GitHub | ✅ main 分支，commit `4a7d30d` |

### ⏳ 待做

**VM 重置后从零全量重跑**（用户已授权，会配合重置）。

---

## 三、目录结构（v1 定稿）

```
k8s/
├── bootstrap/                 L1 引导层（命令式，一次性）
│   ├── install.sh             → cilium → argocd
│   ├── cilium/                CNI（引导循环必需）
│   ├── argocd/                ArgoCD v3.5.5 + deploy key + root app 下发
│   ├── preload-images.sh      zot 镜像预热清单（--check / 推送）
│   ├── metallb/ ingress-nginx/ cert-manager/ nfs-storageclass/ longhorn/
│   │                          原脚本保留作回退，不再被主流程调用
│   └── README.md
└── gitops/                    L2 声明层（ArgoCD 持续调谐）
    ├── root/
    │   ├── root-app.yaml              App-of-Apps（占位符由 install.sh 渲染）
    │   └── children/
    │       ├── appprojects.yaml        三层 AppProject
    │       └── apps/*.yaml            各组件 Application
    ├── infra-core/<component>/
    │   ├── chart/                     上游 chart vendored + values-override.yaml
    │   └── manifests/                 额外 CR
    ├── platform/victoria-metrics-k8s-stack/chart/
    ├── apps/hello-world/              业务应用示例
    ├── optional/                      longhorn（不自动同步，见其 README）
    ├── render-repo.sh                 统一改写仓库地址
    └── README.md
```

---

## 四、实测踩坑记录（全部已修复，勿重复踩坑）

### 4.1 原 HANDOFF §4.2 的"镜像链路"结论是错的 ❌

旧结论："`registries.yaml` 的 mirror 写法在 containerd 中不生效，zot 从未被使用"。

**实测证伪**：
```
k3s ctr images pull registry.k8s.io/kube-proxy:v1.35.9   # zot 内有、本地无
→ Completed pull ... elapsed: 5.8 s      ← 命中 zot（官方源经 GCS 重定向必超时）
k3s ctr images pull registry.k8s.io/...:v9999-nonexistent  # zot 内无
→ failed: not found, 耗时 62 s            ← 先打 zot miss，再等官方超时
```

**真实结论**：mirror **生效**但**不回退**。zot 命中即可拉取；zot 未命中 = 必然失败
（`registry.k8s.io` 307 → `europe-west3-docker.pkg.dev`，本网络 i/o timeout）。

### 4.2 ArgoCD 探针被 Cilium 拦截（NetworkPolicy）

chart 默认生成的 NetworkPolicy 只放行 metrics 端口来自「namespace 内的 Pod」，
而 **kubelet 的探针流量来源是宿主机（host identity）**，不在 `namespaceSelector` 匹配范围内
→ repo-server 的 readiness/liveness 持续超时。

**修复**：`global.networkPolicy.create: false`（单节点开发环境无多租户隔离需求）。

### 4.3 ArgoCD 探针 timeoutSeconds 默认值太小

chart 默认 `repoServer.livenessProbe.timeoutSeconds: 1`，而 `/healthz?full=true` 会做 git 操作，
单节点 1 核下必然超过 1s → 被 liveness 杀掉 → CrashLoopBackOff。

**修复**：`timeoutSeconds: 15` / `failureThreshold: 6` / `initialDelaySeconds: 30`。

### 4.4 节点只有 1 核

`allocatable = 1 CPU / 3.9Gi`。各组件 requests 合计必须 < 1 核，
否则 Pod 永远 Pending（`1 Insufficient cpu`）。已把 argocd / 监控 / ingress-nginx 全部降配。

### 4.5 AppProject CRD 不接受 `metadata.description`

`server-side apply` 直接报 `.metadata.description: field not declared in schema`
→ 三个 AppProject 全部创建失败 → 子 Application 报
`referencing project infra-core which does not exist`。

**修复**：删除 `metadata.description`。

### 4.6 Repo Secret 必须打 label

`kubectl create secret generic argocd-repo-secret --from-file=sshPrivateKey=... --from-literal=type=git --from-literal=url=...`
**必须**再打 `argocd.argoproj.io/secret-type: repository`，否则 ArgoCD 不关联该凭据。

症状：不带 label → `error creating SSH agent: "SSH agent requested but SSH_AUTH_SOCK not-specified"`
（ArgoCD 3.5 的 go-git v5.19 行为：**没有**凭据时才走 ssh-agent 分支）。
带 label + 重启 application-controller → 立即生效。

### 4.7 chart 里的 Helm hook Job 在 ArgoCD 下会卡死

| chart | hook | 症状 |
|---|---|---|
| longhorn | `pre-upgrade` | 永远 Running，卡住整个 Application 同步 |
| longhorn | `pre-delete` (uninstall Job) | **会真的删除 Longhorn CR** |
| vmstack | `sync-job` | 正常（Completed） |

**修复**：longhorn 移出 root 自动同步 → `k8s/gitops/optional/`，需要时手工 apply。
`preUpgradeChecker.jobEnabled: false` 也已设。

### 4.8 cert-manager 与 vmstack 的 CRD 顺序依赖

cert-manager 的 ServiceMonitor 引用 `monitoring.coreos.com/v1`，
该 CRD 由 victoria-metrics-operator 提供，而 platform 层（wave 1）晚于 cert-manager（wave -1）。

**修复**：`prometheus.enabled: false`（chart 默认 servicemonitor 就是 false，
但 `prometheus.enabled: true` 时会渲染 ServiceMonitor）。

### 4.9 cert-manager leader election 在 kube-system

`global.leaderElection.namespace` 默认 `kube-system`，
→ AppProject destinations 必须包含 kube-system。

### 4.10 NFS 的 clusterIP 不可变

provisioner 的 NFS volume 由 **kubelet 在宿主机侧挂载**，只能用 IP，
不能用 Service DNS 名（宿主机解析不了集群内 DNS）。
但 clusterIP 是不可变字段 —— 存量同名 Service 存在时 ArgoCD 改不了。
**全新安装无此问题**；存量环境需先删旧 Service。

### 4.11 apps 层不能创建 Namespace

AppProject `apps` 的 `clusterResourceWhitelist: []` → Namespace 被拒
（`resource :Namespace is not permitted in project apps`）。
→ namespace 由 bootstrap 预建（`bootstrap/argocd/install.sh` 已加）。

### 4.12 其他

- `values.yaml` 里 `server:` 写两次会后者覆盖前者 —— YAML 重复 key 的坑
- `kubectl patch --type=merge` 改 containers 数组会整体覆盖（丢 image）→ 用 `--type=json` 按索引改
- ArgoCD 应用卡在 Failed 状态时，`refresh=hard` 不会重新触发同步 → 需 `kubectl patch application --type=merge -p '{"operation":{"sync":{...}}}'`
- `helm upgrade` 报 "another operation is in progress" → `kubectl -n argocd delete secret -l owner=helm`
- `docker pull registry.k8s.io/xxx` 在 Mac 上会因 GCS 重定向到 europe-west3 而 Bad Gateway；
  同一镜像从 VM 上 pull 有时可达（走 asia-northeast1）—— 重定向落点不稳定

---

## 五、Git 凭据

| 项 | 值 |
|---|---|
| 仓库 | `ssh://git@github.com/jory-callan/env-devlab.git` |
| Deploy key 标题 | `argocd-gitops-deploykey` |
| 私钥（本机） | `~/.ssh/argocd_gitops` |
| 私钥（VM） | `/root/argocd_gitops` |
| 权限 | read-only |

GitHub deploy key 已添加（id 167514609）。

---

## 六、下一步：VM 重置后全量验证

### 6.1 准备（本地执行）

```bash
cd /Users/czw/mygithub/env-devlab

# 1) 镜像预热检查（应输出 缺失镜像数: 0）
bash k8s/bootstrap/preload-images.sh --check

# 2) 打包 k8s/（含 vendored chart）
git archive --format=tar.gz -o /tmp/k8s.tar.gz HEAD k8s/
```

### 6.2 重置 VM

**请用户重置 `192.168.5.143`**（Ubuntu 22.04，2C/5.7G/97G）。

### 6.3 执行（VM 重置后）

```bash
# 1) 底座
scp scripts/linux/k3s-single/install-k3s.sh root@192.168.5.143:/root/
scp ~/.ssh/argocd_gitops root@192.168.5.143:/root/
ssh root@192.168.5.143 'bash /root/install-k3s.sh'

# 2) 引导层（cilium → argocd）
scp /tmp/k8s.tar.gz root@192.168.5.143:/root/
ssh root@192.168.5.143 'tar xzf /root/k8s.tar.gz -C /root/k8s'
ssh root@192.168.5.143 'bash /root/k8s/k8s/bootstrap/install.sh argocd \
    --repo ssh://git@github.com/jory-callan/env-devlab.git \
    --ssh-key /root/argocd_gitops'

# 3) 观察三层收敛
kubectl -n argocd get applications -w
```

### 6.4 验收清单

| # | 项 | 判定 |
|---|---|---|
| 1 | `install-k3s.sh` 退出码 | 0 |
| 2 | `bootstrap/install.sh` 退出码 | 0 |
| 3 | ArgoCD pods 全部 Running | `kubectl -n argocd get pods` |
| 4 | 5 个 AppProject/Application 存在 | `kubectl -n argocd get app,appproject` |
| 5 | root Synced + Healthy | 同上 |
| 6 | metallb / ingress-nginx / cert-manager / nfs-storageclass / victoria-metrics 全 Synced+Healthy | 同上 |
| 7 | hello-world Synced + Healthy | 同上 |
| 8 | MetalLB 有 IPAddressPool | `kubectl -n metallb-system get ipaddresspool` |
| 9 | ingress-nginx 拿到 LB IP | `kubectl -n ingress-nginx get svc` |
| 10 | `nfs-client` StorageClass 存在且是 default | `kubectl get sc` |
| 11 | 全集群 Pod 非 Pending | `kubectl get pods -A` |
| 12 | 无组件抢 default StorageClass | 同 10 |
| 13 | self-heal 生效 | `kubectl -n apps scale deploy hello-world --replicas=1` → ArgoCD 改回 2 |
| 14 | hello-world Ingress 有证书 | `kubectl -n apps get secret hello-world-tls` |
| 15 | Grafana 可访问 | `kubectl -n monitoring port-forward svc/vm-grafana 3000:80` |
| 16 | k3s 日志无 reflector 刷屏 | `journalctl -u k3s --since '10 min ago' \| grep -c reflector` |
| 17 | 重复执行 `bootstrap/install.sh` 幂等 | 无副作用 |

---

## 七、回滚

任一步失败 →

```bash
ssh root@192.168.5.143 'helm uninstall argocd -n argocd; kubectl delete ns argocd'
```

回到纯脚本模式：各组件的 `install.sh` 保留在 `k8s/bootstrap/<component>/`，
可手工执行（`bash k8s/bootstrap/install.sh metallb` 等）。

---

## 八、Git 历史

```
4a7d30d fix(gitops): longhorn 移出 root 自动同步，改为可选组件
031af2f fix(gitops): cert-manager 关闭 Prometheus 监控 + 允许 kube-system 部署
b7cfe04 fix(gitops): 放宽 platform 层 AppProject 权限 + apps 层不声明 Namespace
9640789 fix(gitops): 禁用 longhorn pre-upgrade hook Job，移除 cert-manager 的 ServiceMonitor
ce706db fix(gitops): nfs-server Service 固定 clusterIP 并补充说明
133b711 fix(gitops): 移除 AppProject 的 metadata.description + 关闭 NP + 调大探针超时 + 降配
b667fa9 feat(k8s): 三层 GitOps 架构 —— 引导层收敛为 cilium+argocd，声明层拆为 infra-core/platform/apps
```
