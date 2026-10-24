# MetalLB — 裸机 LoadBalancer

为 LoadBalancer 类型 Service 分配外部 IP（L2/ARP 模式，无需路由器 BGP 支持）。

## 安装

```bash
bash k8s/bootstrap/install.sh metallb
```

## 配置 IP 池

按内网空闲 IP 修改 `pool.yaml`（当前默认 `192.168.5.252-253`）：

```bash
kubectl apply -f pool.yaml
```

> ingress-nginx 安装时会自动检测 IP 池并按需 apply，一般无需手动操作。

## 验证

```bash
kubectl -n metallb-system get pods

# 测试
kubectl create deploy test-lb --image nginx:alpine
kubectl expose deploy test-lb --name test-lb-svc --type LoadBalancer --port 80
kubectl get svc test-lb-svc          # 应分配到池内 IP
kubectl delete deploy test-lb && kubectl delete svc test-lb-svc
```

## 清理

```bash
helm uninstall metallb -n metallb-system
kubectl delete namespace metallb-system
```
