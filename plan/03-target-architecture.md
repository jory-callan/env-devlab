# 03 — 目标架构与仓库布局建议

> 初步草案，允许后续修订。文中"建议""倾向于"均非最终决议。

## 1. 分层模型

核心思路：**按"谁消费、谁改、变更节奏"分层，而不是按"用了什么工具"分层。**

```
┌─────────────────────────────────────────────────────────────┐
│ L0  底座层（每台机器一次，与集群无关）                        │
│     install-k3s.sh + ansible/                               │
│     系统优化 · 内核模块 · k3s · config.yaml · registries.yaml │
│     ★ 等价于云上的 Terraform                                  │
├─────────────────────────────────────────────────────────────┤
│ L1  引导层（每集群一次）                                     │
│     bootstrap/cilium   ← CNI，ArgoCD 启动前必须有网络          │
│     bootstrap/argocd   ← 装完即交出控制权                     │
├─────────────────────────────────────────────────────────────┤
│ L2  声明层（持续调谐）                                       │
│     gitops/platform/       metallb ingress-nginx cert-manager │
│                            longhorn nfs-storageclass         │
│     gitops/observability/  victoria-metrics-k8s-stack         │
│     gitops/apps/           业务应用                            │
│     gitops/root/           App-of-Apps + ApplicationSet       │
├─────────────────────────────────────────────────────────────┤
│ L3  主机层（与 k8s 无关，独立演进）                           │
│     stacks/  mysql redis nginx monitor ... （Docker Compose）│
└─────────────────────────────────────────────────────────────┘
```

### 为什么 CNI 必须在 L1 而不能进 L2

**引导循环**：ArgoCD 本身是 Pod，需要集群已有可用 Pod 网络才能启动。
若 Cilium 由 ArgoCD 部署 → 无 CNI → ArgoCD 起不来 → 永不就绪。

k3s 当前配置已含 `flannel-backend: "none"`，即"k3s 起来但节点 NotReady，直到 Cilium 装上"，
这正是正确的引导设计，**建议保持**。

### 关于 "L0 等价于 Terraform"

无云环境下，`install-k3s.sh` 承担的正是 Terraform 的角色（准备机器与集群）。
国外 bare-metal/on-prem 团队大量采用 Ansible + shell 替代 Terraform，属常见形态。
未来引入云时，`terraform/` 可作为独立仓库预留，当前空置即可。

## 2. GitOps 工具选型建议

| 维度 | ArgoCD | Flux |
|---|---|---|
| 交互界面 | 完整 Web UI（diff / health / history） | 仅 CLI（Web UI 为独立项目） |
| 生态 | ApplicationSet / Notifications / Projects 齐全 | CNCF 毕业，更贴近 k8s 原生 |
| 概念复杂度 | 较多（App / Project / AppSet / RepoSecret） | 较少（Source / Kustomization / HelmRelease） |
| 审计呈现 | UI 可直接演示"当前 vs 期望"差异 | 需额外工具 |

**建议选 ArgoCD**，主要理由是审计视角：ArgoCD 的 UI 能直接展示状态差异与变更历史，
在与审计方对话时是可演示的证据。Flux 更适合"只想要声明式、不想要控制器复杂度"的场景。

> 该结论的前提是"单人或小团队"。若团队更熟悉 Flux 且不想维护 UI 相关的额外概念，
> Flux 是合理替代——**工具选型不是原则问题**。

## 3. 仓库布局建议

### 3.1 仓库拆分：建议只拆一条线

判据是**消费者不同**：

| 内容 | 消费者 | 读取方式 | 建议归属 |
|---|---|---|---|
| `install-k3s.sh`、`ansible/`、`stacks/`、`bootstrap/cilium`、`bootstrap/argocd` | **人** | 人工阅读并执行 | 留在 `env-devlab` |
| Application CR、Helm values、Kustomize overlays | **ArgoCD（机器）** | 机器拉取并渲染 | 建议独立仓库 `env-gitops` |

理由：ArgoCD 不需要读安装脚本，人也不需要读 Application CR。

**但 GitOps 仓库内部建议不再拆**，用目录 + AppProject 做逻辑隔离：

| 隔离手段 | 强度 | 说明 |
|---|---|---|
| AppProject `sourceRepos` | 强 | 按**仓库路径**限定可读范围 → 官方设计意图就是"单仓多目录" |
| AppProject `destinations` | 强 | 限定可部署的 namespace / cluster |
| AppProject `clusterResourceWhitelist` | 强 | 限制可创建的集群级资源 |
| CODEOWNERS | 中 | PR 审批归属 |
| 独立仓库 | — | 仅在多团队/合规物理隔离时才需要 |

多仓的代价（跨仓 PR、版本同步、仓库数量膨胀）对小团队常常大于收益。

### 3.2 建议目录结构

```
gitops/
├── root/
│   ├── appset-platform.yaml     # ApplicationSet：平台组件 × 环境矩阵
│   ├── appset-observability.yaml
│   ├── appset-apps.yaml
│   ├── clusters.yaml            # 环境清单（cluster 列表 + 环境参数）
│   └── root-app.yaml            # App-of-Apps 入口
├── platform/
│   ├── metallb/
│   │   ├── base/kustomization.yaml
│   │   └── overlays/{dev,test,prod}/kustomization.yaml
│   ├── ingress-nginx/
│   ├── cert-manager/
│   ├── longhorn/
│   └── nfs-storageclass/
├── observability/
│   └── victoria-metrics-k8s-stack/
│       ├── base/
│       └── overlays/{dev,test,prod}/
└── apps/
    └── <app-name>/
        ├── base/
        └── overlays/{dev,test,prod}/
```

### 3.3 路径设计建议（为将来拆仓库预留）

建议**未来独立仓库以 `platform/` `observability/` `apps/` 为顶层**，不要保留 `gitops/` 前缀。
这样从子目录迁到独立仓库时，ArgoCD Application 里的 `path:` 字段**无需修改**。

（若最终决定不拆仓库，这条建议同样无害，只是无用。）

### 3.4 AppProject 划分建议

| Project | sourceRepos | destinations | 用途 |
|---|---|---|---|
| `platform` | `platform/*` | metallb-system, ingress-nginx, cert-manager, longhorn-system, nfs-storageclass | 平台组件 |
| `observability` | `observability/*` | monitoring | 可观测性 |
| `apps` | `apps/*` | 业务 namespace | 业务应用 |

## 4. sync wave 编排建议

| wave | 组件 | 依赖理由 |
|---|---|---|
| -3 | metallb | 提供 LoadBalancer IP，是 ingress 对外暴露的前提 |
| -2 | ingress-nginx | 依赖 metallb 分配到 IP |
| -1 | cert-manager | 应用签发证书前须就绪 |
| 0 | longhorn / nfs-storageclass | 存储供给；不阻塞上面三者 |
| 1 | observability | 采集与存储 |
| 2 | apps | 依赖入口、证书、存储 |

wave 数值仅是**起点建议**，实际顺序应由组件间的真实依赖确定。
可通过 ArgoCD 的 `healthy` 状态与 sync 失败反馈迭代调整。

## 5. 可观测性的两种形态（并存而非二选一）

| 形态 | 位置 | 内容 | 定位 |
|---|---|---|---|
| 主机侧 | `stacks/monitor`（Compose） | VictoriaLogs + Fluent Bit + Grafana + VictoriaMetrics | 裸机/本地中间件的日志与指标底座 |
| 集群侧 | `k8s/monitoring/victoria-metrics-k8s-stack` | VMAgent/VMSingle/VLSingle/VLAgent/VMAlert/AlertManager/Grafana | k8s 集群内可观测性 |

二者**目标形态不同**（Compose vs k8s），建议各自独立演进，不互相搬迁。
若未来希望集群内数据汇聚到主机侧 Grafana，属于可选的集成点，不建议作为默认路径。

至于集群侧的可观测性**是否进入 GitOps**，见 [05-open-questions.md](05-open-questions.md) Q-3。

## 6. 已知需要处理的冲突点

- **metrics-server 双份**：k3s 内置 + victoria-metrics-k8s-stack。建议明确 disable 内置的
  （或反过来只留一个），避免指标源分裂。当前 `fix-k3s-metrics.sh` 是在绕过而非解决。
- **`imagePullPolicy: Always`**：在预缓存镜像仓库下会导致每次启动回源拉取而失败。
  迁移到 GitOps 时应显式设置为 `IfNotPresent`。
- **接管已有资源**：现有组件由 `helm install` 安装，缺少 ArgoCD 管理的元数据，
  同步时可能被判为"多余资源"而在开启 prune 后被删除重建。处理方式见 Phase 3。
