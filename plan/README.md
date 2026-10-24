# plan — 目标、需求与实施步骤

> **状态：v1 定型（2026-10-24）**
>
> 本目录记录目标、约束与实施路径。文中结论均附**依据**（实测/官方文档）与**推翻条件**。
> 若与实际环境冲突，**以实际环境为准**，并回头修正本文档。

## 文档索引

| 文件 | 内容 |
|---|---|
| [01-goals-and-scope.md](01-goals-and-scope.md) | 总体目标、范围边界、非目标 |
| [02-requirements.md](02-requirements.md) | 功能/非功能需求与硬约束（**HC 段必读**） |
| [03-target-architecture.md](03-target-architecture.md) | 目标架构与仓库布局 |
| [04-implementation-steps.md](04-implementation-steps.md) | 分阶段实施步骤与验收标准 |
| [05-open-questions.md](05-open-questions.md) | 开放问题、待决策项、风险登记 |

## 一句话现状

`k8s/bootstrap/`（引导层：cilium + argocd）+ `k8s/gitops/`（声明层：infra-core /
platform / apps 三层）**代码已就绪**。当前处于 **Phase 5：VM 重置后端到端验证**前的最后准备阶段。

## 进度看板

| Phase | 内容 | 状态 |
|---|---|---|
| Phase 0 | 镜像链路诊断与修复 | ✅ 完成（实测推翻原假设） |
| Phase 1 | ArgoCD 引导安装 | ✅ 代码就绪，待端到端验证 |
| Phase 2 | `gitops/` 三层骨架 | ✅ 代码就绪，待端到端验证 |
| Phase 3 | 同步波次编排 | ✅ 已内置 |
| Phase 4 | 业务应用接入（示例） | ✅ 已就绪 |
| Phase 5 | **VM 重置端到端验证** | ⬜ **下一步** |
| 后续 | Cilium 纳管 / 多环境矩阵 / metrics-server 双份收敛 / CHANGELOG+ADR | ⬜ 未开始 |
