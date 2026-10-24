# 02 — 需求清单

> 初步草案，允许后续修订。每条需求标注了**类型**与**验证方式**，便于后续逐条核对。

## 1. 功能需求

### FR-1 平台组件声明式交付

集群内的平台组件（cert-manager / metallb / ingress-nginx / longhorn / nfs-storageclass）
应能以 Git 中的声明描述其期望状态，由 GitOps 引擎负责收敛。

- **验证**：在 Git 中修改某个组件的 values，提交后集群在无人工干预下收敛到新状态
- **备注**：当前这些组件以 `helm install` 脚本方式安装，迁移时需处理"接管已有资源"问题
  （见 [04-implementation-steps.md](04-implementation-steps.md) Phase 3）

### FR-2 业务应用声明式交付

业务应用的部署声明进入 Git，由同一套机制管理。

- **验证**：新建一个示例应用，通过修改 Git 中的声明即可完成部署/扩缩容/回滚

### FR-3 多环境支持

同一套组件声明需能表达 test / dev / prod 的差异。

- **建议做法**：Kustomize `base/` + `overlays/{dev,test,prod}`
- **验证**：同一组件在三个环境使用不同配置，diff 只呈现环境差异部分
- **备注**：当前物理环境只有单集群，环境矩阵在初期可通过 ApplicationSet 的 cluster 列表
  预留，不必立即具备三套真实集群

### FR-4 依赖顺序可控

平台组件之间存在依赖（MetalLB → ingress-nginx → cert-manager → 存储 → 应用），
声明式同步需能保证顺序。

- **建议做法**：ArgoCD sync wave 注解
- **验证**：全新集群上一次性同步，组件按预期顺序就绪，无中间态错误

### FR-5 权限与爆炸半径隔离

不同类别的组件应能在权限层面隔离，避免单点失陷导致全集群受影响。

- **建议做法**：ArgoCD AppProject 限定 `sourceRepos` 与 `destinations`
- **验证**：某 Project 无法向未授权 namespace 部署；无法读取未授权路径

### FR-6 引导能力（bootstrap）

集群必须能从"刚装好 k3s、无 CNI"的状态走到"GitOps 接管"。

- **建议做法**：`install-k3s.sh` 只做底座；`bootstrap/cilium` + `bootstrap/argocd` 做引导
- **验证**：在全新虚拟机上按顺序执行，节点从 NotReady → Ready，ArgoCD UI 可访问

### FR-7 可观测性在 k8s 内可用

k8s 集群内应具备指标采集、日志采集、存储、展示、告警的完整链路。

- **现状**：已有 `k8s/monitoring/victoria-metrics-k8s-stack`（脚本方式）
- **备注**：是否迁入 GitOps 见 [05-open-questions.md](05-open-questions.md) Q-3

## 2. 非功能需求

### NFR-1 变更可审计

任何影响集群状态的变更都应能回答：谁改的、为什么改、怎么回滚。

- **建议**：Git 仓库强制 PR + CODEOWNERS + 分支保护；必要处补 CHANGELOG
- **依据**：审计方关注的是"控制目标"（变更可控可审计），而非具体用了哪种工具。
  命令式与声明式都可以满足，前提是证据链完整

### NFR-2 幂等与可重入

任何脚本重复执行应安全；任何声明重复同步应收敛到同一状态。

- **验证**：脚本连跑两次无副作用；同一 commit 反复 sync 结果一致

### NFR-3 不依赖可能停止维护的第三方源

镜像源、chart 源、脚本源优先使用**上游官方维护地址**。

- **背景**：用户明确担心第三方加速站未来停止维护
- **现状**：`install-k3s.sh` 已完成去 cn mirror 改造（部分见 HANDOFF.md）
- **注意**：本次改造中曾因可用性原因引入 `gh-proxy.com`（Grafana 插件下载），
  **建议后续替换为官方渠道**，登记于 [05-open-questions.md](05-open-questions.md) Q-5

### NFR-4 错误显式暴露

失败应明确报错，不应被静默吞掉。

- **约定**：脚本统一 `set -euo pipefail`；禁止用 `|| true` 掩盖关键失败
- **注意**：非关键探测性命令可用 `|| true`，但需注释说明为何可忽略

### NFR-5 可回滚

每个阶段都应有明确的回滚路径，且**不破坏既有可用环境**。

- **验证**：每个 Phase 完成后，确认原路径仍可用

### NFR-6 文档与代码同步

结构调整后，相关 README 与本文档应同步更新，避免"文档描述与实际不符"。

## 3. 硬约束（当前环境事实，绕不过去）

| 编号 | 约束 | 影响 |
|---|---|---|
| HC-1 | **zot 的 mirror 是生效的，但不做回退**（2026-10-24 实测更正）<br>`ctr images pull registry.k8s.io/kube-proxy:v1.35.9`（zot 内有、本地无）**5.8s 成功** → 命中 zot；<br>pull 一个 zot 内没有的 tag → **62s 后失败**（先打 zot miss，再等官方超时） | 结论：zot 命中即可拉取；**zot 未命中 = 必然失败**，因为 `registry.k8s.io` 会 307 重定向到 `europe-west3-docker.pkg.dev`，从本网络 i/o timeout<br>❌ 原表述"mirror 写法在 containerd 中不生效、zot 从未被使用"**已被实测推翻** |
| HC-2 | **zot 是预缓存式，不是 pull-through 代理**（实测确认） | 镜像必须**预先推送**到 zot。清单固化在 `k8s/bootstrap/preload-images.sh` |
| HC-3 | **k3s 使用 SQLite(kine) 而非 etcd** | `k3s etcd-snapshot` 不可用；快照/备份策略需另行设计 |
| HC-4 | **单节点** | 多组件的副本数、反亲和、拓扑约束需按单节点设计（历史上 cilium operator 因默认 2 副本 + podAntiAffinity 而 Pending） |
| HC-5 | **`imagePullPolicy: Always` 与预缓存模式冲突** | 每次重启都回源拉取 → 离线环境必然失败。GitOps 层统一改为 `IfNotPresent` |
| HC-6 | **k3s 内置 metrics-server 与 victoria-metrics-k8s-stack 并存** | 两套指标源冲突。需明确 disable 其中一套（现有 `fix-k3s-metrics.sh` 是在绕过此问题） |
| HC-7 | **k3s 内置 traefik / servicelb 已 disable** | ingress 由 ingress-nginx 承担，LoadBalancer 由 MetalLB 承担。不可误开 |
| HC-8 | **集群侧访问上游仓库不稳定**（实测）<br>`helm.cilium.io` / `charts.longhorn.io` / `argoproj.github.io` 稳定 200；<br>`charts.jetstack.io` **时通时断**（10s 超时）；`github.com` https **时通时断**（但 ssh:22 通）；<br>`quay.io` 可达但慢（211MB 拉取 48s） | → **chart 必须 vendored 进 Git**，ArgoCD 渲染时不访问外部仓库<br>→ 镜像走 zot 预缓存，插件下载走官方 release 直链（已去掉 gh-proxy） |

## 4. 非需求（明确不追求）

- 不追求零人工操作。生产环境的变更窗口与审批流程本身是有价值的控制。
- 不追求一次迁移完所有组件。允许命令式与声明式并存过渡。
- 不追求与某个特定上游项目的目录结构完全一致。结构服务于自己的团队。
- 不追求"GitOps 覆盖率"这类指标数字。
