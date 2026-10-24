#!/bin/bash
# taint-control-plane.sh -- 给控制平面节点打上 NoSchedule 污点
# 阻止普通 Pod 调度到控制平面节点，DaemonSet 不受影响
set -euo pipefail

echo ">> 为控制平面节点添加 NoSchedule 污点 ..."
for node in $(kubectl get nodes --selector='node-role.kubernetes.io/control-plane' -o name 2>/dev/null); do
    node_name="${node#node/}"
    kubectl taint nodes "$node_name" node-role.kubernetes.io/control-plane=:NoSchedule --overwrite 2>/dev/null && \
        echo "  [OK] $node_name 已添加 NoSchedule 污点" || \
        echo "  [WARN] $node_name 操作失败"
done

echo ""
echo "当前节点污点状态:"
kubectl get nodes -o custom-columns=NAME:.metadata.name,TAINTS:.spec.taints
echo ""
echo "完成。普通 Pod 不会再调度到控制平面节点上。"
echo "DaemonSet (如 Cilium, MetalLB 等) 不受影响，将继续运行。"
