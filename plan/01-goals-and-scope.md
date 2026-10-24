# 01 — 总体目标与范围

> 初步草案，允许后续修订。

## 1. 背景

当前仓库 `env-devlab` 的形态：

| 目录 | 内容 | 消费者 | 交付方式 |
|---|---|---|---|
| `scripts/linux/k3s-single/` | 系统优化 + k3s 安装 | 人 | 手工执行 |
| `ansible/` | OS 层配置 | 人 | 手工执行 |
| `k8s/bootstrap/` | cilium / metallb / ingress-nginx / cert-manager / nfs-storageclass / longhorn | 人 | `helm install` 脚本 |
| `k8s/monitoring/` | kube-prometheus-stack / victoria-metrics-k8s-stack | 人 | `helm install` 脚本 |
| `stacks/` | mysql / redis / nginx / monitor 等 Docker Compose 中间件 | 人 | `docker compose` |

即：**全仓库都是命令式（imperative）交付**——变更 = 改脚本 → 手工执行 → 期望环境被改对。
这种方式能工作，但存在几个结构性问题：

- **无法自愈**：有人手工 `kubectl edit` 改了组件，脚本与集群状态发生漂移，无人察觉
- **无法审计**：不清楚"生产环境当前到底是什么配置"，变更历史散落在 commit 与个人操作中
- **多环境成本线性上升**：每加一个环境，所有组件都要重跑一遍脚本

## 2. 总体目标

把交付方式从**命令式**逐步迁移为**声明式**，具体拆成三个可独立推进的目标：

### 目标 A —— 交付方式升级（主线）

平台组件与业务应用的变更，改由 Git 仓库中的声明描述，由 GitOps 引擎持续调谐。
人在 Git 上提交变更并经过 review，控制器负责让集群收敛到期望状态。

- 建议工具：**ArgoCD**（理由见 [03-target-architecture.md](03-target-architecture.md)）
- 建议保留**引导层**：CNI 与 ArgoCD 自身仍需脚本安装（见"引导循环"约束）

### 目标 B —— 技术栈对标

希望整体形态与国外主流实践一致，便于后续阅读他人仓库、承接他人方案、满足合规审计习惯。

- 建议对标：Weaveworks 三仓模型、ArgoCD App-of-Apps、Terraform/Ansible + GitOps 分层
- 说明：**没有云环境时，Terraform 的位置由 `install-k3s.sh` + `ansible/` 等价承担**，这不是妥协，
  而是"裸机/无云"场景下的常见形态

### 目标 C —— 环境准备

最终需要支撑 **test / dev / prod 三套环境**。

- 建议：**单仓库 + Kustomize overlays 表达环境差异**，而非每环境一个仓库
- 环境数量从 1 增到 3 时，改动应主要落在 overlays 与 ApplicationSet 的 cluster 列表，
  而非复制粘贴组件清单

## 3. 范围边界

### 本次覆盖

- k3s 集群之上的**集群内工作负载**的交付方式
- 仓库内三个来源（`k8s/bootstrap/`、`k8s/monitoring/`、未来的业务应用）向声明式的收敛
- 配套的目录结构、权限模型、审计说明

### 本次不覆盖（明确排除）

- **云资源编排**（VPC/子网/IAM/LB 等）。无云环境，且与 GitOps 属于不同层、不同工具。
  后续引入云时，`terraform/` 可作为独立仓库预留（当前可空置）。
- **`stacks/` 下的 Docker Compose 中间件**。它们的部署目标是 Docker 而非 k8s，
  交付模型与 GitOps 不同，**建议保持在当前仓库**。可观测性同理：
  `stacks/monitor`（compose 版）与 `k8s/monitoring/`（k8s 版）是两套不同目标形态的部署，
  不建议合并或互相搬迁。
- **业务代码本身的 CI/CD**。GitOps 解决的是"配置与部署声明"，不替代应用构建流水线。
- **多集群联邦**（Cluster API / fleet）。当前是单集群，等真有多集群需求再评估。

## 4. 非目标（明确不做）

- 不追求"一次到位"的完美终态。迁移过程中**命令式与声明式会并存**，
  这是正常的过渡期形态，不是失败。
- 不为了使用某个工具而引入该工具。每个新增组件都应回答：
  "它替代了什么？收益是否大于运维成本？"

## 5. 推翻与重审条件

本方案在下列情况下应当重新评估：

- 镜像链路问题（Phase 0）发现**无法稳定解决**，导致 GitOps 组件拉取不可靠
- 集群规模扩大导致单仓库 Git 操作（clone / diff / history）明显变慢
- 出现真实的**多团队边界**：不同团队需要不同权限、不同发版节奏、合规要求物理隔离
- 用户在实际使用中认为 GitOps 的运维成本高于收益 → **这条优先级最高，应立即回退到命令式**
