# kube-prometheus-stack

Prometheus Operator 生态栈：Prometheus（指标采集）+ Loki（日志聚合）+ Promtail（日志采集）+ Grafana（展示）。

## 架构

| 组件 | 来源 | 存储 | 说明 |
|------|------|------|------|
| kube-prometheus-stack | GitHub Release (69.7.4) | PVC (nfs-client, 10Gi) | Prometheus Operator + Prometheus + Grafana + AlertManager + CRDs |
| Loki | Nexus (6.32.0) | S3 (MinIO `loki` bucket) | SingleBinary 模式，日志聚合（[cache 已降配](#loki-资源配置)） |
| Promtail | Nexus (6.16.6) | — | DaemonSet，采集所有节点日志 |

## 访问入口

| 服务 | 地址 | 凭证 |
|------|------|------|
| Grafana | https://grafana.czw-sre.internal | admin / admin |
| Prometheus | https://prometheus.czw-sre.internal | 无认证（内网域名） |
| Loki API | https://loki.czw-sre.internal | 无认证 |
| Loki WebUI | https://loki.czw-sre.internal/ui/ | 实验性 UI（LogQL 查询） |

## 部署

```bash
bash install.sh
```

## 卸载

```bash
bash uninstall.sh
```

## Loki 资源配置

`values-loki.yaml` 中覆盖了 chart 默认的 memcached cache 内存，适配实验室环境：

| Cache | Chart 默认 | 当前值 | K8s request |
|-------|-----------|--------|-------------|
| chunks-cache | 8192Mi | **512Mi** | 614Mi |
| results-cache | 1024Mi | **256Mi** | 307Mi |

若需调大，修改 `values-loki.yaml` 中 `chunksCache.allocatedMemory` / `resultsCache.allocatedMemory`，然后 `helm upgrade`。

## 数据源

Grafana 已预置 Loki 数据源（`loki-gateway:80`），Prometheus 数据源由 kube-prometheus-stack 自动配置。

## ServiceMonitor / PodMonitor 兼容

Prometheus 已配置 `selector.matchLabels: {}`（全量自发现）和 `namespaceSelector: {}`（跨命名空间）。任何命名空间下的 ServiceMonitor 和 PodMonitor 无需打额外标签即可被自动发现。

## AlertManager

- 默认路由发送到飞书 webhook（keyword: `alert`）
- Watchdog 告警路由到 null 接收器（不发送）
- 重复间隔：4h

## 注意事项

- k3s 内置 etcd 的 metrics 端口 (2381) 绑定 localhost，集群内无法采集，已禁用 kubeEtcd
- k3s 无独立 kubeControllerManager/kubeScheduler 端点，已禁用
- Helm release 名称：`prometheus`
