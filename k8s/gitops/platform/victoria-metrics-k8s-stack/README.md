# victoria-metrics-k8s-stack

一体化 VictoriaMetrics 监控栈：指标采集 + 日志采集 + 展示 + 告警。

## 组件

| 组件 | 类型 | 说明 |
|------|------|------|
| VMAgent | 指标采集 | 自动发现 ServiceMonitor/PodMonitor，20s 间隔 |
| VMSingle | 指标存储 + 查询 | Prometheus 兼容 API，7d 保留，NFS PVC 10Gi |
| VLSingle | 日志存储 | VictoriaLogs 单实例，7d 保留，NFS PVC 10Gi |
| VLAgent | 日志采集 | DaemonSet 采集容器日志 → VLSingle |
| VMAlert | 告警规则引擎 | 30s 评估间隔 |
| AlertManager | 告警通知 | 飞书 webhook |
| Grafana | 展示 | 3 个内置数据源，NFS PVC 5Gi |
| Node Exporter | 节点指标 | DaemonSet |
| kube-state-metrics | 集群状态 | Deployment |

## 架构

```
┌─────────────────────────────────────────────────────────────┐
│                        Grafana                               │
│  3 数据源: PromQL + MetricsQL + LogsQL                       │
│  插件: victoriametrics-metrics-datasource + logs-datasource  │
└───┬──────────┬──────────────┬────────────────────────────────┘
    │          │              │
┌───▼────┐ ┌──▼─────┐ ┌──────▼─────────┐
│VMSingle│ │VMAlert │ │  VLSingle       │
│指标存储 │ │告警引擎│ │  日志存储        │
└───┬────┘ └────────┘ └──────┬──────────┘
    │                        │
┌───▼────┐             ┌─────▼──────────┐
│VMAgent │             │  VLAgent       │
│采集器   │             │  DaemonSet     │
└────────┘             │  k8sCollector  │
                       └────────────────┘
```

## 访问入口

| 服务 | 地址 | 凭证 |
|------|------|------|
| Grafana | https://vm-grafana.czw-sre.internal | admin / admin123 |
| Metrics API | https://vm-metrics.czw-sre.internal | 无认证 |
| Logs API | https://vm-logs.czw-sre.internal | 无认证 |

## Grafana 数据源（自动配置）

| 数据源 | 类型 | 说明 |
|--------|------|------|
| VictoriaMetrics | `prometheus` | 标准 PromQL 查询，无需插件 |
| VictoriaMetrics (Native) | `victoriametrics-metrics-datasource` | MetricsQL 原生查询，需插件 |
| VictoriaLogs | `victoriametrics-logs-datasource` | LogsQL 日志查询，需插件 |

插件通过 initContainer 自动从 gh-proxy.com 下载。

## 部署

```bash
cd k8s/monitoring/victoria-metrics-k8s-stack
bash install.sh
```

## 卸载

```bash
bash uninstall.sh
```

## Service 命名规则

通过 `fullnameOverride: "monitoring"` 统一命名，所有组件 Service 名为 `<component>-monitoring`：

| 组件 | Service 名 | 端口 |
|------|-----------|------|
| VMSingle | vmsingle-monitoring | 8428 |
| VLSingle | vlsingle-monitoring | 9428 |
| VMAgent | vmagent-monitoring | 8429 |
| VLAgent | vlagent-monitoring | 9429 |
| VMAlert | vmalert-monitoring | 8080 |
| VMAlertmanager | vmalertmanager-monitoring | 9093 |

集群内其他服务连接 VM 组件时使用 `<service>.monitoring:<port>` 格式。

## 注意事项

- k3s 无独立 kube-controller-manager/kube-scheduler endpoints，相关面板无数据
- VLAgent 自动采集所有命名空间容器日志
- 告警通过 AlertManager -> 飞书通知
- Chart 自动加载 kube-prometheus 系列 Dashboard（含 VM/Node/Pod/Cluster 等）

## 原始资源

- Chart: `https://github.com/VictoriaMetrics/helm-charts/tree/master/charts/victoria-metrics-k8s-stack`
- Version: 0.85.9 (app v1.146.0)
- 文档: https://docs.victoriametrics.com/helm/victoriametrics-k8s-stack/
