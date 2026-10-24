# etcd 快照 — 远程备份到 MinIO

## 现状

**单节点 k3s 默认使用 SQLite(kine) datastore，不是 etcd**，因此 `--etcd-snapshot-*` 系列参数不生效，
`k3s etcd-snapshot list` 会直接报 `etcd datastore disabled`。

当前 datastore 实况：

```bash
# 数据文件在 state.db (SQLite)
ls -la /var/lib/rancher/k3s/server/db/
# state.db  state.db-shm  state.db-wal
```

SQLite 模式下 k3s 不提供自动快照调度，需要自己定时备份 `state.db`。

> 若要让 etcd 快照生效，必须把 k3s 切换到 etcd datastore（`datastore-endpoint` + `cluster-init`），
> 这是一次性迁移操作，详见下方"启用 etcd datastore"。

## 方案

### 方式一：切换到 etcd datastore（推荐，官方原生方案）

在 k3s config.yaml 中启用内置 etcd，然后 k3s 的快照能力才可用。

```
# /etc/rancher/k3s/config.yaml
datastore-endpoint: "etcd"
cluster-init: true
etcd-snapshot-schedule-cron: "0 */6 * * *"   # 每 6 小时
etcd-snapshot-retention: 30
```

> ⚠️ 该配置只能在全新集群初始化时生效。已有 SQLite 集群不能直接切换，
> 需要 `--cluster-init` 重建或迁移数据，属于破坏性操作。

配置后配合 S3 参数可把快照直接写入对象存储：

```
--etcd-s3
--etcd-s3-bucket k3s-etcd
--etcd-s3-endpoint minio.minio.svc.cluster.local:80
--etcd-s3-access-key svc-poweruser
--etcd-s3-secret-key <secret>
--etcd-s3-insecure true
--etcd-s3-region us-east-1
```

**优点：** K3s 原生支持，无需额外组件，快照直接写入 MinIO，且带自动调度。
**缺点：** 需要切换 datastore（重建集群），且要重启 k3s 服务。

### 方式二：CronJob 同步 SQLite 文件（适用于当前 SQLite 模式）

用 Kubernetes CronJob 定时备份 `/var/lib/rancher/k3s/server/db/state.db` 到 MinIO。

**优点：** 不需要重建集群，不影响现有运行。
**缺点：** 备份 SQLite 文件需要停写或使用 `.backup` API，有短暂不一致窗口。

## 推荐

- **测试环境（当前状态）**：用方式二，直接备份 SQLite 文件。
- **生产环境**：用方式一，切到 etcd datastore，拿到官方原生的快照调度 + S3 直写。

## 恢复

从 MinIO 恢复快照（etcd datastore 模式）：

```bash
k3s server \
  --cluster-init \
  --etcd-s3 \
  --etcd-s3-bucket k3s-etcd \
  --etcd-s3-endpoint minio.minio.svc.cluster.local:80 \
  --etcd-s3-access-key svc-poweruser \
  --etcd-s3-secret-key <secret> \
  --etcd-s3-insecure true \
  --etcd-s3-region us-east-1 \
  --etcd-snapshot-name <snapshot-name>
```

## 参考

- [K3s etcd 备份文档](https://docs.k3s.io/backup-restore#etcd-snapshot)
- [K3s datastore 文档](https://docs.k3s.io/datastore)
