# 05 — 开放问题、待决策项与风险登记

> 初步草案，允许后续修订。
> 本文件的价值在于**把还没想清楚的事显式记下来**，避免它们被默认值悄悄决定。

---

## 一、待决策问题

### Q-1 是否拆分独立 GitOps 仓库？

**当前倾向**：先在 `env-devlab/gitops/` 子目录跑通闭环，验证后再评估搬迁。

**理由**
- 判据是消费者不同（人 vs ArgoCD 机器），这条线成立
- 但"新建仓库"会引入一批不可预判的改动（repo credential、路径前缀剥离、
  GitOps token 权限等）。**先证明模式可行，再付迁移成本**
- 若最终搬迁，建议新仓库以 `platform/` `observability/` `apps/` 为顶层，
  不保留 `gitops/` 前缀，这样 Application 的 `path:` 字段无需改动

**推翻条件**：出现多团队权限隔离 / 合规物理隔离 / 发版节奏明显不同 → 直接拆

**待补充**：拆分后 ArgoCD 的 repo credential 如何管理（建议 `argocd-repo-server` secret
或专用 ServiceAccount + 细粒度 token），此项尚未展开

---

### Q-2 ArgoCD 还是 Flux？

**当前倾向**：ArgoCD。

**理由**
- Web UI 可直接展示"当前状态 vs 期望状态"差异与变更历史，审计视角下是可演示的证据
- ApplicationSet / Projects / Notifications 生态更完整
- 与"多环境矩阵"的需求匹配（ApplicationSet 的 list generator 较成熟）

**推翻条件**：团队更熟悉 Flux、或认为 UI 带来的运维复杂度不值得 → 换 Flux 不影响整体分层设计

**待补充**：ArgoCD 自身的资源规格（单节点 2C/5.7G 下是否需要调低副本数与资源限制）
需在 Phase 1 实测确定

---

### Q-3 集群侧可观测性（`k8s/monitoring/`）是否迁入 GitOps？

**当前倾向**：倾向迁入（它属于平台层组件），但**尚未定论**。

**支持迁入的理由**
- 与其他平台组件保持一致的交付方式，避免"同一层两种机制"
- VictoriaMetrics Operator 的资源（VMAlert/VMAgent 等）本身适合声明式管理
- 告警规则作为 YAML 管理，比脚本内嵌更易 review

**不支持迁入的理由**
- 官方 chart 的 values 结构庞大，翻译为 Kustomize base/overlays 成本高
- 该 stack 依赖 NFS PVC 存储，需要存储类先就绪，增加 wave 编排复杂度
- Grafana 数据源、插件安装等环节在 chart 之外还有额外脚本逻辑

**判据**：如果 Phase 4 完成后迁移成本明显高于收益，保持脚本方式也是合理结论。
**这不是对错问题，是投入产出问题。**

**另一个独立议题**（无论迁不迁都要处理）：**metrics-server 双份冲突**（HC-6）。
建议明确只保留一套。现状 `fix-k3s-metrics.sh` 是绕过而非解决。

---

### Q-4 三环境如何实际落地？

**当前倾向**：单仓库 + Kustomize overlays；环境矩阵由 ApplicationSet 的 cluster 列表驱动。

**待解决**
- 当前只有**一台**物理集群（192.168.5.143）。三环境是否需要三套真实集群？
  若不需要，dev/test/prod 的差异是否只用 namespace 区分？
  *注意*：仅 namespace 区分时，ArgoCD 的 `destinations` 限制与 sync wave 语义会变简单，
  但资源争抢（dev 抢占 prod 资源）会失去隔离
- 若需要多集群，是"同集群多 namespace"还是"多台机器多集群"？
  后者才需要真正的 cluster secret 管理

**倾向**：初期用同一集群 + 不同 namespace + 资源限制区分，等有第二台机器再升级为多集群。
**理由**：符合"先跑通模式，再扩大规模"的原则。

---

### Q-5 Grafana 插件下载渠道

**现状**：`k8s/monitoring/victoria-metrics-k8s-stack/` 中 Grafana 插件通过 **gh-proxy.com** 下载。

**问题**：与 NFR-3（不依赖可能停止维护的第三方源）冲突。

**待评估**：是否可改为
- 官方 grafana.com 插件仓库直连（需验证本网络可达性）
- 插件镜像预构建并推到 zot（最稳，但需自建镜像）
- 或放弃这两个插件，用 VictoriaLogs 的原生 API（LogsQL 有一定兼容度）替代

---

### Q-6 `terraform/` 目录的定位

**当前倾向**：预留空目录或独立仓库，当前不填内容。

**理由**：无云环境，且 Terraform 属于 L0 层（云资源编排），与 GitOps 是不同层不同工具。
未来有云时可直接启用。

**注意**：如果一直不填，空目录反而是噪声。可考虑在真正需要时再建。

---

## 二、风险登记

| 编号 | 风险 | 影响 | 概率 | 应对 |
|---|---|---|---|---|
| R-1 | **镜像链路无法稳定解决** | Phase 1+ 全部阻塞 | 中 | Phase 0 优先做；若确认 containerd 原生配置也无法满足，则考虑放弃 GitOps 路线（回到命令式） |
| R-2 | **接管已有资源时 ArgoCD 误删资源** | 组件中断 | 中 | Phase 3 先不开 prune；metallb 试点失败则改用"先卸载再重建" |
| R-3 | **单节点资源紧张**（2C/5.7G） | ArgoCD + 平台组件 + 监控挤爆内存 | 高 | 逐个 Phase 观察内存；监控 stack 尤其重（VMAgent/VLSingle/VLAgent 都是常驻） |
| R-4 | **单节点 + 反亲和/拓扑约束** | Pod Pending | 高 | 历史上 cilium operator 已踩过（默认 2 副本 + podAntiAffinity）→ 所有组件副本数按单节点显式设 1 |
| R-5 | **双套可观测性并存**（Compose + k8s stack） | 资源翻倍、维护面翻倍 | 高 | 明确两者定位与边界；HC-6 的 metrics-server 冲突必须解决 |
| R-6 | **GitOps 运维成本高于收益** | 项目失去价值 | 中 | 保留命令式路径随时可回退；在 Phase 3/4 后重新评估 |
| R-7 | **ArgoCD 自身故障导致集群失控** | 无法收敛 | 低 | 引入前确认 k3s 侧 Pod 存活策略；保留 `bootstrap/install.sh` 作为灾难恢复路径 |
| R-8 | **迁移过程中新旧机制打架** | 状态漂移 | 中 | 明确"同一组件只有一个 owner"；迁移完成后脚本标记为废弃（不再执行） |

---

## 三、决策记录（ADR 摘要）

正式 ADR 建议在 Phase 7 撰写为独立文件。以下为已达成的口头共识，供后续 reference。

### ADR-001：采用"命令式底座 + 声明式平台层"分层

- **决定**：`install-k3s.sh` 做底座；`bootstrap/` 只保留 CNI 与 ArgoCD；其余进 GitOps
- **理由**：GitOps 的引导循环要求 CNI 先于 ArgoCD；其余组件无此约束
- **状态**：初步，待 Phase 3 验证后确认

### ADR-002：CNI 与 ArgoCD 保留脚本安装

- **决定**：CNI 与 ArgoCD 不进 GitOps
- **理由**：引导循环；且这两者装完基本不再变
- **状态**：初步

### ADR-003：Docker Compose 栈（`stacks/`）保持在当前仓库

- **决定**：`stacks/`（含 `stacks/monitor`）不迁入 GitOps 仓库
- **理由**：部署目标不同（Docker vs k8s）；故障域隔离；集群重建不丢监控数据
- **状态**：初步

### ADR-004：GitOps 仓库内部用目录 + AppProject 隔离，不拆多仓

- **决定**：单仓多目录
- **理由**：AppProject 的 `sourceRepos` 已提供按路径的读写隔离；多仓的跨仓 PR 成本对小团队是净负担
- **推翻条件**：出现真实的多团队边界
- **状态**：初步

---

## 四、给后续接手者（含 AI）的提示

1. **本文档是草案，不是决议。** 任何一条都可能是错的。若实测推翻了某条假设，
   **请直接改这份文档并在 §三 的 ADR 中记录变更**，不要默默按旧文档执行。
2. **动手前先读 [02-requirements.md](02-requirements.md) 的 HC 段。**
   那些是当前环境的硬事实，绕不过去，重复踩坑成本很高。
3. **优先做 Phase 0。** 它独立于所有架构决策，却是所有后续步骤的前提。
4. **每个 Phase 都要有回滚路径。** 在动手前先想清楚"怎么退回去"。
5. **不要一次性大改。** 迁移存量组件时，"接管已有资源"是最容易出问题的地方，
   建议先用最小组件（metallb）验证这条路。
6. **遇到与文档冲突的实际情况，以实际情况为准**，然后回头修正文档。
