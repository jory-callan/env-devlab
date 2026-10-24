# Cilium — eBPF CNI

第一个安装的组件，负责 Pod 网络（替代 flannel），并开启 Hubble 流量可视化。

## 安装

```bash
bash k8s/bootstrap/install.sh cilium
```

前置：k3s 安装时使用 `flannel-backend: none`。安装需 2-5 分钟（eBPF 程序编译下发）。

## 验证

```bash
kubectl get nodes                                          # 节点应 Ready
kubectl -n kube-system get pods -l k8s-app=cilium
kubectl -n kube-system exec -it daemonset/cilium -- cilium status

# Hubble UI（可选）
kubectl port-forward -n kube-system svc/hubble-ui 12000:80
# 浏览器访问 http://localhost:12000
```

## 关键配置

- Pod CIDR：`10.42.0.0/16`（每节点 /24）
- `kubeProxyReplacement=false`：保留 k3s 内置 kube-proxy
- `routingMode=native` + `autoDirectNodeRoutes`：节点间直接路由

## 清理

```bash
helm uninstall cilium -n kube-system
rm -f /var/lib/cni/networks/cilium/* /etc/cni/net.d/*cilium*   # 需在每个节点执行
```

> 卸载后建议重启各节点，彻底清理 CNI 与 iptables 残留。
