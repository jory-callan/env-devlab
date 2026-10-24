# 04 — 分阶段实施步骤

> **状态：v1 已定型（2026-10-24）**。本文按"三层 GitOps"重写。
>
> **推进原则**
> - 每个 Phase 结束时，**既有可用环境不应被破坏**（回滚路径必须存在）
> - 每个 Phase 结束时应能用一段命令验证结果，而不是靠"看起来正常"
> - Phase 之间允许调整顺序；若发现某 Phase 的前提不成立，先解决前提
> - 每个 Phase 完成后回填「实际结果」并勾选

---

## 架构决策（v1 定稿）

```
L1 引导层  k8s/bootstrap/          命令式脚本，一次性执行
           ├─ cilium               ArgoCD 是 Pod，没 CNI 起不来（引导循环）
           └─ argocd               GitOps 引擎本身，不能自己管自己
                    ↓ 装完交出控制权
L2 声明层  k8s/gitops/             ArgoCD 持续调谐
           ├─ root/                App-of-Apps + 三层 AppProject
           ├─ infra-core/          metallb ingress-nginx cert-manager nfs longhorn
           ├─ platform/            victoria-metrics-k8s-stack（可观测性）
           └─ apps/                业务应用
```

**与旧版 plan 的差异**：旧版 Phase 3/4/5 主张"把平台层与可观测性迁入 ArgoCD"，
已被后续决策推翻 —— 平台层与可观测性**不进** ArgoCD 之外的其它机制，
但**统一进** ArgoCD 声明层（三层都在 ArgoCD 内，只是分层隔离）。
`stacks/`（Docker Compose）始终不进 ArgoCD。

---

## Phase 0 — 镜像链路诊断与修复 ✅ 已完成

**原任务**（诊断 containerd mirror 行为、确定 zot 是代理还是缓存）
**结论**（实测，2026-10-24）：

| 验证 | 结果 |
|---|---|
| `ctr images pull registry.k8s.io/kube-proxy:v1.35.9`（zot 有、本地无） | **成功 5.8s** → 命中 zot |
| pull `...kube-webhook-certgen:v9999-nonexistent`（zot 无） | 失败 **62s**（zot miss → 官方超时） |
| `zot /v2/k8s/ingress-nginx/kube-webhook-certgen/tags/list` | `["v1.6.9"]` → 镜像已补齐 |
| `helm list -A` | ingress-nginx rev2 deployed，cert-manager/metallb/nfs/vm 全部 deployed |

→ **原 HANDOFF §4.2 的"mirror 从未被使用"结论是误判**（当时 zot 里恰无该镜像，
掩盖了真实行为）。真实事实是：mirror 生效，但**不回退**；官方源经 GCS 重定向后超时，
所以 zot 未命中即失败。

**落地**：
- 镜像清单固化 → `k8s/bootstrap/preload-images.sh`（含 `--check` 模式）
- `imagePullPolicy: Always` → `IfNotPresent`
- Grafana 插件下载去掉 `gh-proxy.com` → 官方 release 直链（实测 VM 可达）

**实际结果**：✅ 全部镜像已推送，缺失数 0

---

## Phase 1 — ArgoCD 引导安装 ✅ 代码就绪

**产物**：`k8s/bootstrap/argocd/`（install.sh + values.yaml + README.md + chart）

- chart：`argo-cd` 10.11.1（ArgoCD v3.5.5），vendored 于仓库
- 副本数全部显式为 1（单节点）
- NodePort 暴露（30800/30443）—— 引导阶段不能依赖 ingress-nginx
- SSH deploy key 凭据（只读，最小权限），`known_hosts` 现场采集
- 渲染并下发 root App-of-Apps

**实际结果**：⏳ 待 VM 重置后端到端验证

---

## Phase 2 — `gitops/` 三层骨架 ✅ 代码就绪

**产物**：
- `k8s/gitops/root/root-app.yaml`（App-of-Apps）
- `k8s/gitops/root/children/appprojects.yaml`（infra-core / platform / apps 三个 AppProject）
- `k8s/gitops/root/children/apps/*.yaml`（7 个 Application）
- `k8s/gitops/infra-core/<component>/{chart,manifests}/`
- `k8s/gitops/platform/victoria-metrics-k8s-stack/chart/`
- `k8s/gitops/apps/hello-world/`（业务应用示例）
- `k8s/gitops/render-repo.sh`（统一改写仓库地址）

**关键设计**：**chart vendored 进 Git**。集群侧访问 `charts.jetstack.io` /
`github.com` 时通时断（HC-8），ArgoCD 渲染时不能依赖外部 chart 仓库。

**权限隔离**：

| Project | destinations | clusterResource 白名单 |
|---------|--------------|------------------------|
| infra-core | 5 个组件 ns | 全部 |
| platform | monitoring | 仅 monitoring.coreos.com / operator.victoriametrics.com / CRD |
| apps | apps | **空** —— 业务应用不得创建集群级资源 |

**实际结果**：⏳ 待 VM 重置后端到端验证

---

## Phase 3 — 同步波次编排 ✅ 已内置

| wave | 组件 | 依赖理由 |
|---|---|---|
| -3 | metallb | 提供 LoadBalancer IP |
| -2 | ingress-nginx | 依赖 metallb 分配 IP |
| -1 | cert-manager | 应用签发证书前须就绪 |
| 0 | nfs-storageclass / longhorn | 存储供给 |
| 1 | victoria-metrics | 依赖 nfs-client 存储类 |
| 2 | hello-world | 依赖入口与证书 |

**实际结果**：⏳ 待验证

---

## Phase 4 — 业务应用接入 ✅ 示例已就绪

`k8s/gitops/apps/hello-world/`（Deployment + Service + Ingress + cert-manager 注解）
演示完整链路：改 Git → 提交 → ArgoCD 自动收敛 → self-heal。

**实际结果**：⏳ 待验证

---

## Phase 5 — 端到端重置验证 ⏳ **下一步**

**这是"脚本永远正确"的最终证据**。VM 重置后从零执行：

```bash
# 1) 底座
scp scripts/linux/k3s-single/install-k3s.sh root@192.168.5.143:/root/
scp ~/.ssh/argocd_gitops root@192.168.5.143:/root/
ssh root@192.168.5.143 'bash /root/install-k3s.sh'

# 2) 引导层（Cilium → ArgoCD）
git archive --format=tar.gz -o /tmp/k8s.tar.gz HEAD k8s/
scp /tmp/k8s.tar.gz root@192.168.5.143:/root/
ssh root@192.168.5.143 'tar xzf /root/k8s.tar.gz -C /root/k8s'
ssh root@192.168.5.143 'bash /root/k8s/k8s/bootstrap/install.sh argocd \
    --repo ssh://git@github.com/jory-callan/env-devlab.git \
    --ssh-key /root/argocd_gitops'

# 3) 观察三层收敛
kubectl -n argocd get applications -w
```

**完整验收清单与踩坑记录见 [`k8s/bootstrap/HANDOFF.md`](../k8s/bootstrap/HANDOFF.md)。**

**实际结果**：_（待填）_

---

## 里程碑与依赖关系

```
Phase 0 (镜像链路)      ✅
Phase 1 (ArgoCD 引导)    ✅ 代码就绪
Phase 2 (三层骨架)       ✅ 代码就绪
Phase 3 (波次编排)       ✅ 已内置
Phase 4 (业务应用示例)   ✅ 已就绪
        └─> Phase 5 (VM 重置端到端验证)   ← 当前所在
```

---

## 后续（Phase 5 之后）

1. **Cilium 纳入 infra-core**：待 ArgoCD 自身稳定后，把 Cilium 也改为 GitOps 管理
2. **多环境矩阵**：单集群 + namespace 区分 dev/test/prod，ApplicationSet 驱动
3. **HC-6 metrics-server 双份**：明确只保留一套
4. **CHANGELOG + ADR**：SOC 2 审计证据（不依赖 GitOps，靠 PR review + commit history）
5. **仓库拆分评估**：先在子目录跑通闭环再评估
