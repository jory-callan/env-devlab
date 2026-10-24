#!/bin/bash
set -euo pipefail

# 修复 k3s 内置 metrics-server Service selector 与 Pod labels 不匹配的问题
# Service 原始 selector 是 app.kubernetes.io/instance 和 app.kubernetes.io/name
# 但 Pod 只有 k8s-app 这个 label，导致 endpoints 为空

kubectl patch svc metrics-server -n kube-system --type='json' \
  -p='[{"op": "replace", "path": "/spec/selector", "value": {"k8s-app": "metrics-server"}}]'

echo "[OK] metrics-server Service selector 已修复"
sleep 3
kubectl top node && echo "[OK] metrics API 正常" || echo "[WARN] 稍等几秒再试 kubectl top node"




speed-check-mode tcp:80,ping

server 101.6.6.6:5353
server 202.38.93.153:5353
server 202.141.162.123:5353
server 202.141.178.13:5353
server 2001:da8::666
server 208.67.222.222:5353 -group fq_dns -exclude-default-group
server 208.67.220.220:5353 -group fq_dns -exclude-default-group

server-tcp 1.0.0.1 -group fq_dns -exclude-default-group
server-tcp 8.8.4.4 -group fq_dns -exclude-default-group
server-tcp 149.112.112.112 -group fq_dns -exclude-default-group
server-tcp 2606:4700:4700::1001 -group fq_dns -exclude-default-group

server-tls 115.159.131.230 -host-name dns.rubyfish.cn
server-tls dns.rubyfish.cn
server-tls 1.1.1.1 -host-name 1dot1dot1dot1.cloudflare-dns.com -group fq_dns -exclude-default-group
server-tls 2606:4700:4700::1111 -host-name 1dot1dot1dot1.cloudflare-dns.com -group fq_dns -exclude-default-group
server-tls 1dot1dot1dot1.cloudflare-dns.com -group fq_dns -exclude-default-group
server-tls 8.8.8.8 -host-name dns.google -group fq_dns -exclude-default-group
server-tls dns.google -group fq_dns -exclude-default-group

server-https https://202.38.93.153/resolve -host-name neatdns.ustclug.org -http-host neatdns.ustclug.org
server-https https://202.141.178.13/resolve -host-name neatdns.ustclug.org -http-host neatdns.ustclug.org
server-https https://[2001:da8:d800:931::153]/resolve -host-name neatdns.ustclug.org -http-host neatdns.ustclug.org
server-https https://neatdns.ustclug.org/resolve
server-https https://rubyfish.cn/dns-query
server-https https://i.233py.com/dns-query
server-https https://9.9.9.9/dns-query -group fq_dns -exclude-default-group
server-https https://dns9.quad9.net/dns-query -group fq_dns -exclude-default-group
server-https https://146.112.41.2/dns-query -host-name doh.opendns.com -http-host doh.opendns.com -group fq_dns -exclude-default-group
server-https https://doh.opendns.com/dns-query -group fq_dns -exclude-default-group