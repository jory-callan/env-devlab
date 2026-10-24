# cert-manager — TLS 证书自动签发

管理证书全生命周期，到期前 30 天自动续期。

内置 CA 方案见 `cluster-issuer.yaml`：`selfsigned-ca` → 根证书 → `internal-ca`（ClusterIssuer），用于签发 `*.czw-sre.internal` 内网域名证书。

## 安装

```bash
bash k8s/bootstrap/install.sh cert-manager
```

## 配置签发器

```bash
kubectl apply -f cluster-issuer.yaml
```

## 验证

```bash
kubectl -n cert-manager get pods
kubectl get clusterissuer        # selfsigned-ca / internal-ca 均应 READY=True
```

## 在 Ingress 中使用

```yaml
metadata:
  annotations:
    cert-manager.io/cluster-issuer: "internal-ca"
spec:
  tls:
    - hosts: [ "my-app.czw-sre.internal" ]
      secretName: my-app-tls          # cert-manager 自动创建并续期
```

## 清理

```bash
helm uninstall cert-manager -n cert-manager
kubectl delete namespace cert-manager
kubectl get crd | grep cert-manager | awk '{print $1}' | xargs kubectl delete crd
```
