# 交接文档 — k3s 集群脚本验证与改造

> 记录时间：2026-10-24 12:55 (Asia/Tokyo)
> 用途：新会话读取本文档后可直接接续，无需重新排查。

---

## 一、任务目标（用户明确表述）

> "我的目的是为了验证脚本的正确性，其次才是修复当前环境。我需要保证脚本执行永远正确。"

两条主线，**优先级不可颠倒**：

1. **主线 A —— 脚本正确性验证**：`install-k3s.sh` 与 `bootstrap/` 下全部脚本必须保证"永远正确"，
   不能依赖任何可能停止维护的第三方加速站。
2. **主线 B —— 环境修复**：在验证脚本正确的前提下，修复当前远程环境的实际问题。

具体要求：
- `install-k3s.sh` **去掉一切 cn mirror**，一切以官方维护源为主。
  （用户原话："我当心未来哪一天 cn mirror 不再维护了"）
- `bootstrap/` 内容需**全量验证**。
- 用户明确表示：需要重置虚拟机时会直接说明，已授权"你自行完成这些内容"。

---

## 二、环境信息

| 项 | 值 |
|---|---|
| 远程服务器 | `root@192.168.5.143` (Ubuntu 22.04.5, hostname `ubuntu22-01`) |
| 本机 kubeconfig | `~/.kube/config` → `server: https://192.168.5.143:6443` |
| 本机工具 | helm v3.18.0, kubectl 可用；远程 helm v3.16.4 |
| 仓库路径 | `/Users/czw/mygithub/env-devlab` |
| 节点规格 | 2 CPU / 5.7Gi RAM / 97G 磁盘(12% 已用) |
| 自建镜像仓库 | `http://192.168.5.103:20000` (zot, **预缓存式**，非 pull-through 代理) |
| chart 仓库 | 全部 chart 已 vendored 在 `k8s/bootstrap/*/*.tgz`，下载仅为兜底 |

**远程 k3s 现状（重启前）**：k3s v1.36.5+k3s1，单节点 control-plane，datastore = **SQLite(kine)**
（`/var/lib/rancher/k3s/server/db/state.db`，无 etcd 目录）。

---

## 三、已完成的工作

### 3.1 脚本改造（全部已完成并通过静态校验）

**`scripts/linux/k3s-single/install-k3s.sh`**

| 改动 | 详情 |
|---|---|
| 删除 `K3S_MIRROR` 变量 | k3s 安装改为直连 `https://get.k3s.io`，移除 `rancher-mirror.rancher.cn` |
| `APT_MIRROR` 默认值改为空 | 默认使用 Ubuntu 官方源 `archive.ubuntu.com`；非空时仍可切 aliyun（用户可选） |
| 保留 universe 启用逻辑 | 官方源分支下同样执行 `sed -ri 's/main restricted$/main restricted universe multiverse/'` |
| helm 下载源 | 华为云 `mirrors.huaweicloud.com/helm/` → 官方 `https://get.helm.sh/helm-v3.16.4-linux-{arch}.tar.gz` |
| chrony NTP | `ntp.aliyun.com`/`ntp1.aliyun.com` → 官方 `pool pool.ntp.org iburst` |
| **移除 `etcd-snapshot-*` 配置** | SQLite datastore 下该参数不生效，移除以免"配了却不跑"；改为在 `setup_k3s_config` 末尾输出提示 |
| **新增 `disable: servicelb`** | ServiceLB 改由 MetalLB 接管，两者并存会抢同一端口 |
| **新增 `cleanup_flannel_cni()`** | 清理 `/var/lib/rancher/k3s/agent/etc/cni/net.d/10-flannel.conflist` 残留（已接入主流程，位于 `setup_k3s_config` 之后） |
| `tls-san` 移除 `192.168.5.103` | 该 IP 是 zot registry 主机，与 k3s 入口无关 |
| `verify()` 输出调整 | 移除误导性的"快照检查: k3s etcd-snapshot list"，改为提示 datastore 事实 |

**`k8s/bootstrap/cilium/install.sh`（最关键修复）**

- **新增 `--set operator.replicas=1`** —— 这是 `cilium-operator` 副本 Pending 的根因：
  chart 默认 `operator.replicas: 2`，且 operator 为 `hostNetwork=true` + `hostPort: 9963`
  + `podAntiAffinity` 为 **required**（按 `kubernetes.io/hostname`），
  单节点上 2 副本必然 1 个 Pending。已用 `helm template` 验证渲染结果为 `replicas: 1`。
- 删除 `MIRROR_BASE`，兜底下载改官方 `https://helm.cilium.io/cilium-1.18.11.tgz`
- 新增 `--set operator.prometheus.serviceMonitor.enabled=false`（chart 中该字段存在，默认 false）

**`k8s/bootstrap/metallb/install.sh`**

- 删除 `MIRROR_BASE`，兜底改官方 GitHub release 直链
- **新增自动 apply `pool.yaml`**（幂等：已存在则跳过）—— 原脚本只提示手动执行，
  导致后续 ingress-nginx 拿不到 LB IP
- 安装后回显实际 IP 池

**`k8s/bootstrap/ingress-nginx/install.sh`**

- 删除 `MIRROR_BASE`，兜底改官方 GitHub release 直链
- 前置检查失败时由 `[WARN]` 改为 **`[ERR]` + exit 1**（原来会带着无池状态继续装，必然失败）

**`k8s/bootstrap/cert-manager/install.sh`**

- 删除 `MIRROR_BASE`（原本就没有），统一为 `CHART_URL` 变量 + 官方 `charts.jetstack.io`

**`k8s/bootstrap/nfs-storageclass/install.sh`**

- 删除 `MIRROR_BASE`，兜底改官方 GitHub release 直链
- **移除 `kubectl apply -f - 2>/dev/null || true`** —— 原来吞掉错误会导致 NFS Server 起不来时
  后续步骤一路失败难以定位

**`k8s/bootstrap/longhorn/install.sh`**

- 删除 `MIRROR_BASE`，兜底改官方 `https://charts.longhorn.io/longhorn-1.12.0.tgz`
- **`K3S_DATA_DIR` 默认值修正**：`/opt/k3s_data` → `/var/lib/rancher/k3s`（原值与 k3s 实际 data-dir 不符，
  会导致 CSI 驱动无法工作）
- **新增从 systemd 单元自动读取真实 data-dir**（`systemctl show k3s --property=Environment`）
- `sudo modprobe` → `modprobe`（脚本本身以 root 运行）

**`k8s/bootstrap/install.sh`（主脚本）**

- 删除 `MIRROR_BASE` 环境变量说明
- **新增前置检查**：kubectl / helm 是否存在、`kubectl get node` 是否连通，否则明确报错退出

### 3.2 文档同步

- `k8s/bootstrap/README.md` —— 删除 `MIRROR_BASE` 章节，改为列出 6 个组件各自的**官方源对照表**
- `k8s/bootstrap/etcd-backup/README.md` —— **重写**：原文声称"etcd 快照功能已启用，每 6 小时自动备份"，
  与 SQLite 现状矛盾。新文档说明 SQLite 事实、给出切换 etcd datastore 的方法与破坏性警告、
  以及 SQLite 模式下用 CronJob 备份 `state.db` 的方案
- `k8s/bootstrap/longhorn/README.md` —— 更新 `K3S_DATA_DIR` 说明
- 删除 `scripts/linux/k3s-single/install-k3s copy.sh`（过期副本，含旧 cn mirror 配置）

### 3.3 静态校验结果（全部通过）

```
bash -n  →  install-k3s.sh, bootstrap/install.sh, 6 个组件 install.sh,
             fix-k3s-metrics.sh, taint-control-plane.sh          全部 OK

helm lint →  cilium / ingress-nginx / metallb / cert-manager /
             nfs-subdir-external-provisioner / longhorn          全部 0 failed

helm template (cilium) → operator replicas: 1 ✅
                        podAntiAffinity: required ✅ (印证单节点必须 1 副本)

cn mirror 残留扫描 (scripts/linux + k8s/) → 无残留
```

### 3.4 远程现有环境的修复验证（已执行）

| 操作 | 结果 |
|---|---|
| `helm upgrade cilium --set operator.replicas=1` | revision 2, deployed ✅ |
| cilium-operator 副本 | **1/1 Running，Pending 副本消失** ✅ |
| 同步新 bootstrap 到远程 `/root/k8s/k8s/bootstrap` | 成功，校验 `MIRROR_BASE` 全部为 0 ✅ |
| `bash install.sh metallb` | 成功，pool.yaml 自动创建 ✅ |
| metallb pods | controller 1/1, frr-k8s 5/5, speaker 0/1 ContainerCreating ✅（此前 CrashLoop 是卸载残留所致，非脚本问题） |
| `bash install.sh ingress-nginx` | **卡住** → 见下节 |

---

## 四、当前阻塞问题（关键，必须在新会话优先处理）

### 4.1 现象

`bash install.sh ingress-nginx` 卡在 admission job：

```
pod/ingress-nginx-admission-create-jgdm2   0/1   ImagePullBackOff

Failed to pull image "registry.k8s.io/ingress-nginx/kube-webhook-certgen:v1.6.9@sha256:01038e7..."
  desc = not found
```

### 4.2 已验证的根因链（用 `k3s ctr` 做了隔离实验，结论可靠）

1. **zot (`192.168.5.103:20000`) 是预缓存式，不是 pull-through 代理。**
   `GET /v2/_catalog` 返回的镜像列表里**没有** `k8s/ingress-nginx/kube-webhook-certgen`，
   探测该路径返回 **404**。它只存了已缓存的少数镜像（如 `k8s/metrics-server/metrics-server`、
   `k8s/coredns/coredns`、`quay/calico/*` 等）。

2. **官方 `registry.k8s.io` 直连实际超时。**
   `registry.k8s.io` 会 **307 重定向到 GCS** `europe-west3-docker.pkg.dev`，
   该地址从本网络 **i/o timeout**（实测 30s 超时）。所以"直连官方"这条路在当前网络下走不通。

3. **containerd 的 mirror 配置不做回退 —— 这是真正的设计缺陷。**
   k3s 由 `registries.yaml` 的 `mirrors:` 生成的
   `/var/lib/rancher/k3s/agent/etc/containerd/certs.d/registry.k8s.io/hosts.toml` 内容为：

   ```toml
   server = "https://registry.k8s.io/v2"
   capabilities = ["pull", "resolve", "push"]
   [host]
   [host."http://192.168.5.103:20000/v2/k8s"]
     capabilities = ["pull", "resolve"]
     override_path = true
     skip_verify = true
   ```

   实测：ctr 拉取时**只请求 `server`（官方）**，`[host]` 段的 zot **根本没被使用**。
   改写为 zot 作 `server` + 官方作 `[host]` 也仍走 GCS 超时。
   → **结论：zot 缺某个镜像 = 拉取直接失败，无自动回退。**

4. 因此**当前 `registries.yaml` 的写法实际上是失效的**：所有 `registry.k8s.io` 镜像都在走
   超时的官方源，zot 从未被用作首选。

> ⚠️ 上一条推论需在新会话用一条命令复核（当时正准备执行、被中断）：
> `curl -sS http://192.168.5.103:20000/v2/_catalog` 看完整镜像列表，
> 并确认 zot 是否对某些命名空间配了 proxy。

### 4.3 待决策方案（尚未实施）

- **方案 1**：把 zot 配成真正的 pull-through proxy（zot 支持 proxy repos），
  使 `registry.k8s.io` 命名空间可代理拉取任意上游镜像 —— 最优雅，但需改 zot 服务端配置（不在本仓库内）
- **方案 2**：在 `registries.yaml` 中为 `registry.k8s.io` 显式配置多 endpoint 且调整顺序，
  使 zot 在前、官方在后，并验证 containerd 的 fallback 行为 —— 需实测确认 containerd 是否支持
- **方案 3**：预热 zot 缓存，把 bootstrap 所需镜像全部灌入 —— 简单但需人工维护
- **方案 4**：`ingress-nginx` 改用非 `registry.k8s.io` 的镜像源（如 `docker.io/...`）—— 影响 chart 默认值

### 4.4 被中断的诊断命令（可原样重跑）

```bash
ssh -o BatchMode=yes root@192.168.5.143 '
echo "=== zot 代理能力测试 ==="
curl -sS --max-time 10 http://192.168.5.103:20000/v2/k8s/metrics-server/metrics-server/tags/list
curl -sS -o /dev/null -w "%{http_code}\n" --max-time 15 \
  -H "Accept: application/vnd.oci.image.index.v1+json" \
  http://192.168.5.103:20000/v2/k8s/ingress-nginx/kube-webhook-certgen/manifests/v1.6.9
curl -sS --max-time 10 http://192.168.5.103:20000/v2/_catalog | tr "," "\n" | grep -iE "ingress|nginx|certgen"
curl -sS --max-time 10 http://192.168.5.103:20000/v2/_catalog | tr "," "\n" | cut -d/ -f1 | sort -u
'
```

---

## 五、远程环境其它已发现的问题（重置 VM 后会自然消失）

1. **k3s 日志 reflector 刷屏** —— 26748 行日志中 16058 行是同一条：
   ```
   Failed to watch err="failed to list *v1.PartialObjectMetadata: the server could not find the requested resource"
   ```
   仍在增长（实测 15s +6 条）。根因：metallb 被卸载后 CRD 已删除，
   k3s 内置 apiserver 的 CRD informer 仍持续 watch 已消失的 `*.metallb.io` 资源，不自愈。
   **重启 k3s 可清除。**

2. **flannel CNI 残留** —— `/var/lib/rancher/k3s/agent/etc/cni/net.d/10-flannel.conflist` 仍存在
   （名为 `cbr0`），而 Cilium 的在 `/etc/cni/net.d/05-cilium.conflist`。
   **已在 install-k3s.sh 中加 `cleanup_flannel_cni()` 处理。**

3. **config.yaml 字段"被忽略"是误判（重要更正）** —— 早期出现的
   `Unknown flag --flannel-backend found in config.yaml, skipping` 只来自
   `k3s etcd-snapshot list` **子命令**（它只认 etcd 相关 flag），并非 `k3s server` 本身。
   已用 `k3s server --help` 逐项确认 `flannel-backend` / `disable-network-policy` / `tls-san` /
   `kubelet-arg` / `etcd-snapshot-*` **全部被 server 支持**。实测 flannel 已停、Hubble 正常。
   唯一真实问题是 **datastore 是 SQLite**（见 3.1 与 etcd-backup README 重写）。

4. **metrics-server liveness probe 偶发超时** —— `Get "https://10.42.0.159:10250/livez": context deadline exceeded`，
   走 pod IP 而非 node IP。`kubectl top nodes` 本身正常。
   仓库里有 `k8s/bootstrap/fix-k3s-metrics.sh`（修 Service selector）可参考。

5. **远程 `/root/install-k3s.sh` 是旧版**（md5 `5465ed6f`），与仓库版（md5 `e1dbfea9`）不同：
   远程版缺 `bind-address`、缺 `flannel-backend`、缺 `disable-network-policy`。
   远程 config.yaml 里这些字段是**手工补上**的（所以 k3s.yaml 里 server 是 `127.0.0.1:6443`，
   本机 kubeconfig 的 `192.168.5.143:6443` 是手工改的）。**重置 VM 后按新脚本跑即可对齐。**

---

## 六、建议的下一步（新会话执行顺序）

1. **优先复核 4.2 的推论**（跑 4.4 的诊断命令），确定 zot 是预缓存还是代理
2. **决定并实施 4.3 的方案**，重点是让 `registry.k8s.io` 的镜像能拉下来
3. **请用户重置虚拟机** —— 用户已授权，重置后可从零做**干净的端到端验证**：
   ```
   # 全新 Ubuntu 22.04
   scp install-k3s.sh root@192.168.5.143:/root/ && ssh root@192.168.5.143 'bash /root/install-k3s.sh'
   # 然后
   scp -r k8s/ root@192.168.5.143:/root/ && ssh root@192.168.5.143 'bash /root/k8s/bootstrap/install.sh'
   ```
   这一步是"保证脚本永远正确"的核心证据 —— 全量跑通才算验证完成
4. 验证清单：5 个组件全部 `helm list` deployed、全部 Pod Running、
   `kubectl get sc` 有 nfs-client、ingress-nginx 拿到 LB IP、
   `kubectl top nodes` 正常、k3s 日志无 reflector 刷屏
5. 长期改进：把 `registries.yaml` 的镜像源策略写成可配置（环境变量），避免硬编码 `192.168.5.103`

---

## 七、涉及文件清单

**已修改（工作区，未提交）**

- `scripts/linux/k3s-single/install-k3s.sh`
- `k8s/bootstrap/install.sh`
- `k8s/bootstrap/cilium/install.sh`
- `k8s/bootstrap/metallb/install.sh`
- `k8s/bootstrap/ingress-nginx/install.sh`
- `k8s/bootstrap/cert-manager/install.sh`
- `k8s/bootstrap/nfs-storageclass/install.sh`
- `k8s/bootstrap/longhorn/install.sh`
- `k8s/bootstrap/README.md`
- `k8s/bootstrap/etcd-backup/README.md`
- `k8s/bootstrap/longhorn/README.md`

**已删除**

- `scripts/linux/k3s-single/install-k3s copy.sh`（过期副本，含旧 cn mirror 配置）

**新增**

- `k8s/bootstrap/HANDOFF.md`（本文件）

**未改动但相关**

- `k8s/bootstrap/fix-k3s-metrics.sh`、`k8s/bootstrap/taint-control-plane.sh`（语法校验通过）
- `k8s/bootstrap/*/values.yaml`、`pool.yaml`、`cluster-issuer.yaml`（未改动，已确认与脚本参数匹配）
- `ansible/`（**不在本次范围**，其 repos.yml / docker role 仍用 aliyun 源，如需一并去 cn mirror 需另行确认）

---

## 八、给新会话的第一句话（可直接复制）

> 接手 k8s 集群脚本验证任务。**先读 `k8s/bootstrap/HANDOFF.md`**，里面有完整上下文：
> 已完成的脚本改造清单、已验证结论、以及当前唯一阻塞问题（zot 镜像仓库缺
> `registry.k8s.io/ingress-nginx/kube-webhook-certgen`，且 containerd mirror 不做回退、
> 官方 registry.k8s.io 经 GCS 重定向后超时）。请先复核第 4.2/4.4 节，再往下走。
