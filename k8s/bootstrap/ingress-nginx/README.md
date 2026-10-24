# ingress-nginx — Ingress Controller

集群 HTTP/HTTPS 入口，DaemonSet + LoadBalancer 模式（NodePort 30080/30443 备用，任意节点可直连）。

## 安装

```bash
bash k8s/bootstrap/install.sh ingress-nginx
```

依赖 MetalLB。若 MetalLB IP 池尚未配置，脚本会自动 apply `../metallb/pool.yaml`。

## 验证

```bash
kubectl -n ingress-nginx get pods
kubectl -n ingress-nginx get svc ingress-nginx-controller    # 获取 EXTERNAL-IP

# 测试
kubectl apply -f test-echo.yaml
curl -H "Host: echo.czw-sre.internal" http://<EXTERNAL-IP>
kubectl delete -f test-echo.yaml
```

## 使用

- DNS：将 `*.czw-sre.internal` 指向 EXTERNAL-IP
- TLS：配合 cert-manager（见 `../cert-manager/README.md`）
- 日志：已启用增强格式（`values.yaml`），适配日志采集

> Ingress 配了 `tls` 字段时 HTTP 默认 301 重定向到 HTTPS；需要 HTTP+HTTPS 并存时加 annotation `nginx.ingress.kubernetes.io/ssl-redirect: "false"`。

## 清理

```bash
helm uninstall ingress-nginx -n ingress-nginx
kubectl delete namespace ingress-nginx
```
