#!/usr/bin/env bash
# =============================================================================
# install-k3s.sh - Ubuntu 22.04 一键系统初始化 + 安装 k3s (单机 server)
#
# 步骤: 自检 -> apt 源 -> 基础软件 -> swap -> 防火墙 -> 时间同步 -> 内核优化
#       -> helm -> k3s config.yaml -> k3s registries.yaml -> 安装 k3s -> kubeconfig -> 验证
#
# k3s 参数全部写入 config.yaml (k3s 启动时自动读取), 镜像源写入 registries.yaml,
# 安装命令本身保持极简。幂等: 重复执行安全, 配置无变化不重启。
#
# 仅保留 4 个变量, 其余内容需要调整时直接编辑脚本:
#   K3S_VERSION=v1.30.4+k3s1   # 空=最新稳定版 (重点场景用, 覆盖要显式)
#   K3S_MIRROR=cn              # cn=国内安装源, 空=官方源
#   APT_MIRROR=mirrors.aliyun.com  # 空=不动 apt 源
#   TIMEZONE=Asia/Shanghai
# =============================================================================
set -euo pipefail

K3S_VERSION="${K3S_VERSION:-}"
K3S_MIRROR="${K3S_MIRROR:-cn}"
APT_MIRROR="${APT_MIRROR:-mirrors.aliyun.com}"
TIMEZONE="${TIMEZONE:-Asia/Shanghai}"

# ================================= 工具函数 ==================================
log()   { echo -e "\033[0;36m[信息]\033[0m $*"; }
ok()    { echo -e "\033[0;32m[完成]\033[0m $*"; }
skip()  { echo -e "\033[0;33m[跳过]\033[0m $*"; }
die()   { echo -e "\033[0;31m[失败]\033[0m $*" >&2; exit 1; }
hr()    { echo -e "\n\033[0;90m---------- $* ----------\033[0m"; }

# 写文件: stdin 为内容; 与现有文件相同则跳过 (返回 1=无变化), 保证幂等
write_if_changed() {
  local path="$1" tmp
  tmp="$(mktemp)"
  cat > "${tmp}"
  if [[ -f "${path}" ]] && cmp -s "${tmp}" "${path}"; then
    rm -f "${tmp}"
    return 1
  fi
  mkdir -p "$(dirname "${path}")"
  mv "${tmp}" "${path}"
  chmod 644 "${path}"
}

restart_k3s_if_running() {
  if systemctl is-active --quiet k3s 2>/dev/null; then
    systemctl restart k3s
    ok "k3s 已重启 (配置变更生效)"
  else
    log "k3s 未在运行, 配置将在启动时生效"
  fi
}

# ------------------------------ 00 系统自检 ----------------------------------
check_system() {
  hr "00 系统自检"
  [[ ${EUID} -eq 0 ]] || die "需要 root 权限, 请用 sudo 执行"
  # shellcheck disable=SC1091
  source /etc/os-release
  [[ "${ID:-}" == "ubuntu" && "${VERSION_ID:-}" == "22."* ]] \
    || die "仅支持 Ubuntu 22.x, 当前: ${PRETTY_NAME:-unknown}"
  ok "Ubuntu ${VERSION_ID}, 自检通过"
}

# ------------------------------ 01 apt 镜像源 --------------------------------
setup_apt_source() {
  hr "01 配置 apt 镜像源"
  if [[ -z "${APT_MIRROR}" ]]; then
    skip "未设置 APT_MIRROR, 保持现有源"
  elif grep -q "${APT_MIRROR}" /etc/apt/sources.list 2>/dev/null; then
    skip "apt 源已指向 ${APT_MIRROR}"
  else
    [[ -f /etc/apt/sources.list.bak ]] || cp /etc/apt/sources.list{,.bak}
    sed -ri \
      "s#https?://(archive\\.ubuntu\\.com|security\\.ubuntu\\.com)#https://${APT_MIRROR}#g" \
      /etc/apt/sources.list
    # 启用 universe 组件 (etcd-client 等包需要)
    grep -q universe /etc/apt/sources.list || \
      sed -ri 's/main restricted$/main restricted universe multiverse/' /etc/apt/sources.list
    ok "apt 源已切换为 https://${APT_MIRROR} (备份: sources.list.bak)"
  fi
}

# ------------------------------ 02 基础软件包 --------------------------------
setup_packages() {
  hr "02 安装基础软件包"
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  # shellcheck disable=SC2086
  apt-get install -y -qq \
    curl wget vim zip unzip jq tree htop net-tools rsync lsof bash-completion \
    tcpdump chrony conntrack socat ipvsadm ipset etcd-client nfs-common >/dev/null
  ok "基础软件包已就绪 (etcd-client 即 etcdctl, 重复安装为幂等)"
}

# ------------------------------ 03 关闭 swap ---------------------------------
disable_swap() {
  hr "03 关闭 swap"
  if [[ -n "$(swapon --show=NAME --noheadings 2>/dev/null || true)" ]]; then
    [[ -f /etc/fstab.bak ]] || cp /etc/fstab{,.bak}
    sed -ri "s|^([^#].*[[:space:]]swap[[:space:]])|#\1|" /etc/fstab # 注释 swap 行
    swapoff -a
    ok "已关闭 swap 并注释 fstab 相关行 (备份: /etc/fstab.bak)"
  else
    skip "swap 已是关闭状态"
  fi
}

# ------------------------------ 04 关闭防火墙 --------------------------------
disable_firewall() {
  hr "04 关闭防火墙"
  if ! command -v ufw >/dev/null 2>&1; then
    skip "未安装 ufw"
  elif ! ufw status 2>/dev/null | grep -q "Status: active"; then
    skip "ufw 已是 inactive"
  else
    ufw --force disable
    ok "ufw 已关闭 (网络策略交由 k3s/flannel 管理)"
  fi
}

# ------------------------------ 05 时区与时间同步 ----------------------------
setup_time() {
  hr "05 配置时间同步 (chrony)"
  local cur_tz
  cur_tz="$(timedatectl show -p Timezone --value 2>/dev/null || true)"
  if [[ "${cur_tz}" == "${TIMEZONE}" ]]; then
    skip "时区已是 ${TIMEZONE}"
  else
    timedatectl set-timezone "${TIMEZONE}"
    ok "时区已设置为 ${TIMEZONE}"
  fi
  systemctl enable --now chrony >/dev/null 2>&1 || true
  if {
    echo "# 由 install-k3s.sh 管理, 手动修改会被覆盖"
    echo "driftfile /var/lib/chrony/chrony.drift"
    echo "makestep 1.0 3"
    echo "rtcsync"
    echo "sourcedir /run/chrony-dhcp"
    for s in ntp.aliyun.com ntp1.aliyun.com; do echo "server ${s} iburst"; done
  } | write_if_changed /etc/chrony/chrony.conf; then
    systemctl restart chrony
    ok "chrony 配置已更新并重启"
  else
    skip "chrony 配置无变化"
  fi
}

# ------------------------------ 06 内核优化 ----------------------------------
setup_kernel() {
  hr "06 内核模块与参数优化"
  # nfs / nfsd / nfs_acl: 集群内自建 NFS 服务器 (nfs-storageclass) 依赖宿主机内核 nfsd,
  # 缺失时容器会以 "protocol not supported" 反复退出
  if printf "overlay\nbr_netfilter\nnf_conntrack\nnfs\nnfsd\nnfs_acl\n" \
    | write_if_changed /etc/modules-load.d/k3s.conf; then
    ok "已写入 /etc/modules-load.d/k3s.conf"
  else
    skip "内核模块配置无变化"
  fi
  for m in overlay br_netfilter nf_conntrack; do modprobe "${m}" 2>/dev/null || true; done
  if cat <<'EOF' | write_if_changed /etc/sysctl.d/99-k3s.conf
# 由 install-k3s.sh 管理, 手动修改会被覆盖
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
net.ipv4.conf.all.forwarding = 1
net.ipv6.conf.all.forwarding = 1
net.netfilter.nf_conntrack_max = 1048576
net.core.somaxconn = 65535

kernel.panic = 10
kernel.panic_on_oops = 1
vm.overcommit_memory = 1
vm.swappiness = 0
fs.inotify.max_user_instances = 8192
fs.inotify.max_user_watches = 1048576

EOF
  then
    ok "已写入 /etc/sysctl.d/99-k3s.conf"
  else
    skip "sysctl 配置无变化"
  fi
  sysctl --system >/dev/null 2>&1
  ok "内核模块与参数已应用"
}

# --------------------- 06b NFS 内核模块 (nfsd) -------------------------------
# 集群内自建 NFS 服务器 (k8s/bootstrap/nfs-storageclass) 使用内核 nfsd,
# 宿主机缺少 nfs / nfsd / nfs_acl 模块时容器会以
# "Protocol not supported" 反复 CrashLoopBackOff。
# Ubuntu 把这些模块放在 linux-modules-extra-<kernel> 里, 最小化安装的镜像默认不带。
setup_nfs_kernel() {
  hr "06b 加载 NFS 内核模块 (nfsd)"
  local kver
  kver="$(uname -r)"
  if ! modinfo nfsd >/dev/null 2>&1; then
    log "nfsd 模块不存在, 安装 linux-modules-extra-${kver}"
    export DEBIAN_FRONTEND=noninteractive
    apt-get install -y -qq "linux-modules-extra-${kver}" >/dev/null \
      || die "安装 linux-modules-extra-${kver} 失败"
  fi
  # sunrpc/lockd 是 nfsd 的依赖, 顺序加载
  for m in sunrpc lockd nfs nfs_acl nfsd; do
    modprobe "${m}" 2>/dev/null || true
  done
  # 注意: 不能用 `lsmod | grep -q`, pipefail 下 grep 提前退出会让 lsmod 收到 SIGPIPE 导致误判
  lsmod | grep '^nfsd ' >/dev/null || die "nfsd 模块加载失败, 宿主机无法运行内核 NFS 服务器"
  grep -qw nfsd /proc/filesystems || die "/proc/filesystems 中无 nfsd, 内核 NFS 服务器不可用"
  ok "nfsd 已就绪 (nfs / nfs_acl / nfsd 模块已加载, /proc/filesystems 包含 nfsd)"
}

# ------------------------------ 07 安装 helm ---------------------------------
install_helm() {
  hr "07 安装 helm"
  local want=v3.16.4 have arch tmp
  have="$(helm version --short 2>/dev/null || true)"
  if [[ "${have}" == "${want}"* ]]; then skip "helm ${have} 已安装"; return; fi
  arch="$(dpkg --print-architecture)"
  tmp="$(mktemp -d)"
  log "helm ${want}"
  curl -fsSL "https://mirrors.huaweicloud.com/helm/${want}/helm-${want}-linux-${arch}.tar.gz" \
    -o "${tmp}/helm.tgz"
  tar -xzf "${tmp}/helm.tgz" -C "${tmp}"
  install -m 0755 "${tmp}/linux-${arch}/helm" /usr/local/bin/helm
  rm -rf "${tmp}"
  ok "$(helm version --short)"
}
# install_helm() {
#   hr "07 安装 helm"
#   local want=v3.16.4 have arch tmp
#   have="$(helm version --short 2>/dev/null || true)"
#   if [[ "${have}" == "${want}"* ]]; then skip "helm ${have} 已安装"; return; fi
#   arch="$(dpkg --print-architecture)"
#   tmp="$(mktemp -d)"
#   log "helm ${want}"
#   # 官方发布地址, 不使用任何第三方镜像站
#   curl -fsSL "https://get.helm.sh/helm-${want}-linux-${arch}.tar.gz" \
#     -o "${tmp}/helm.tgz"
#   tar -xzf "${tmp}/helm.tgz" -C "${tmp}"
#   install -m 0755 "${tmp}/linux-${arch}/helm" /usr/local/bin/helm
#   rm -rf "${tmp}"
#   ok "$(helm version --short)"
# }

# ------------------------------ 08 k3s config.yaml ---------------------------
setup_k3s_config() {
  hr "08 写入 /etc/rancher/k3s/config.yaml"
  local node_ip hostname
  node_ip="$(hostname -I 2>/dev/null | awk '{print $1}' || true)"
  hostname="$(hostname -s)"
  if cat <<EOF | write_if_changed /etc/rancher/k3s/config.yaml
# 由 install-k3s.sh 管理, 重新执行脚本会覆盖; k3s 启动时自动读取
cluster-init: true # 默认单节点只使用 sqlite , 多节点自动转 etcd

# data-dir: "/var/lib/rancher/k3s"
disable:
  - traefik                    # 使用 ingress-nginx
  - servicelb                  # 使用 MetalLB
  - network-policy             # 禁用内置网络策略（Cilium 接管）
flannel-backend: "none" # CNI 由 Cilium 接管, k3s 不再运行 flannel (见 k8s/bootstrap/cilium)
bind-address: "${node_ip}" # k3s 生成 kubeconfig 时 server 用本机 IP 而非 127.0.0.1, 便于 scp 到工作机直接使用
tls-san: # 冗余多个入口, 防止证书校验失败后不能访问
  - "${node_ip}"
  - "${hostname}"
  - "k3s.lan"
  - "k3s.server"
  - "k3s-server"
  - "k3s-server-lb"
  - "k3s-master"
  - "k3s-master-lb"

# ==============================================
# ETCD 配置
# ==============================================
# 自动快照
etcd-snapshot-schedule-cron: "0 */6 * * *"
etcd-snapshot-retention: 30
# etcd-snapshot-dir: "__CHANGEME_DATA_DIR__/snapshots"
# ETCD 性能参数
etcd-arg:
  - "auto-compaction-mode=periodic"
  - "auto-compaction-retention=1h"
  - "quota-backend-bytes=8589934592"
  - "heartbeat-interval=100"
  - "election-timeout=1000"
  - "snapshot-count=100000"

# ==============================================
# Kubelet 配置（日志轮转 / GC / 资源预留）
# ==============================================
kubelet-arg:
  # 容器日志限制（防止日志占满磁盘）
  - "container-log-max-size=50Mi"
  - "container-log-max-files=3"
  # 镜像垃圾回收
  - "image-gc-high-threshold=75"
  - "image-gc-low-threshold=65"
  # 镜像拉取
  - "serialize-image-pulls=false"
  # 资源预留（2C8G 环境，根据实际资源调整）
  - "system-reserved=cpu=500m,memory=1Gi,ephemeral-storage=5Gi"
  - "kube-reserved=cpu=500m,memory=1Gi,ephemeral-storage=5Gi"
  # 驱逐策略
  - "eviction-hard=nodefs.available<15%,imagefs.available<15%"
  # Pod 限制
  - "max-pods=110"

# ==============================================
# API Server 配置
# ==============================================
kube-apiserver-arg:
  - "max-requests-inflight=3000"
  - "max-mutating-requests-inflight=1000"
  - "event-ttl=24h"
  - "enable-admission-plugins=NodeRestriction"
  - "service-node-port-range=30000-32767"
  - "request-timeout=1m"

# ==============================================
# Controller Manager 配置
# ==============================================
kube-controller-manager-arg:
  - "node-monitor-period=5s"
  - "node-monitor-grace-period=40s"
  - "terminated-pod-gc-threshold=1000"

# ==============================================
# 安全配置
# ==============================================
# Secrets 加密
secrets-encryption: true
# 保护内核默认值
protect-kernel-defaults: true
# kubeconfig 权限
write-kubeconfig-mode: "600"
# mirror
# system-default-registry: "registry.cn-hangzhou.aliyuncs.com"

EOF
  then
    ok "config.yaml 已写入 (node: ${node_ip:-?}, ${hostname})"
    restart_k3s_if_running
  else
    skip "config.yaml 无变化"
  fi
}

# ------------------------------ 09 k3s registries.yaml -----------------------
setup_k3s_registry() {
  hr "09 写入 /etc/rancher/k3s/registries.yaml"
  if cat <<'EOF' | write_if_changed /etc/rancher/k3s/registries.yaml
# 由 install-k3s.sh 管理, 重新执行脚本会覆盖
# zot 的上游命名空间是 /v2/<{docker,ghcr,gcr,k8s}>/<repo>
mirrors:
  "docker.io":
    endpoint:
      - "http://192.168.5.103:20000/v2/docker"
  "gcr.io":
    endpoint:
      - "http://192.168.5.103:20000/v2/gcr"
  "ghcr.io":
    endpoint:
      - "http://192.168.5.103:20000/v2/ghcr"
  "registry.k8s.io":
    endpoint:
      - "http://192.168.5.103:20000/v2/k8s"
configs:
  "192.168.5.103:20000":
    tls:
      insecure_skip_verify: true
EOF
  then
    ok "registries.yaml 已写入 (endpoint 含 /v2/<ns>, 匹配 zot 命名空间)"
    restart_k3s_if_running
  else
    skip "registries.yaml 无变化"
  fi
}

# ------------------------------ 10 安装/升级 k3s -----------------------------
install_k3s() {
  hr "10 安装 k3s (目标版本: ${K3S_VERSION:-最新稳定版})"
  local cur url="https://get.k3s.io" envs=()
  cur="$(k3s --version 2>/dev/null | awk 'NR==1{print $3}' || true)"
  if [[ -n "${cur}" && ( -z "${K3S_VERSION}" || "${cur}" == "${K3S_VERSION}" ) ]]; then
    skip "k3s ${cur} 已安装 (升级请显式指定 K3S_VERSION)"
    return
  fi
  [[ -n "${K3S_MIRROR}" ]] && {
    url="https://rancher-mirror.rancher.cn/k3s/k3s-install.sh"
    envs+=("INSTALL_K3S_MIRROR=cn")
  }
  [[ -n "${K3S_VERSION}" ]] && envs+=("INSTALL_K3S_VERSION=${K3S_VERSION}")
  log "安装脚本: ${url} (参数全部来自 /etc/rancher/k3s/config.yaml)"
  curl -fsSL "${url}" | env "${envs[@]}" sh -
  export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
  ok "k3s $(k3s --version | awk 'NR==1{print $3}') 安装完成"
}

# ------------------------------ 11 kubeconfig 链接 ---------------------------
setup_kubeconfig() {
  hr "11 链接 ~/.kube/config"
  local kube_dir="${HOME}/.kube"
  # config.yaml 已设 write-kubeconfig-mode 0644, k3s.yaml 全员可读;
  # server 地址已通过 bind-address 写成本机 IP, 该链接 scp 到工作机可直接使用
  if [[ "$(readlink "${kube_dir}/config" 2>/dev/null || true)" == "/etc/rancher/k3s/k3s.yaml" ]]; then
    skip "~/.kube/config 已指向 /etc/rancher/k3s/k3s.yaml"
  else
    mkdir -p "${kube_dir}"
    rm -f "${kube_dir}/config"
    ln -s /etc/rancher/k3s/k3s.yaml "${kube_dir}/config"
    ok "~/.kube/config -> /etc/rancher/k3s/k3s.yaml"
  fi
  echo "  远程使用: scp <user>@\$(hostname -I | awk '{print \$1}'):/etc/rancher/k3s/k3s.yaml ~/.kube/config"
  echo "  注意: kubeconfig 证书会随 k3s 重启自动续期, 复制到外部的副本过期后需重新 scp"
}

# ------------------------------ 12 验证 --------------------------------------
verify() {
  hr "12 验证"
  # shellcheck disable=SC1091
  source /etc/profile.d/k3s.sh 2>/dev/null || export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
  local _
  for _ in {1..20}; do
    kubectl get node -o name >/dev/null 2>&1 && break
    sleep 3
  done
  kubectl get node -o wide || die "节点未就绪, 请执行: journalctl -u k3s -f 排查"
  ok "全部步骤完成 ✔"
  echo "  快照检查: k3s etcd-snapshot list"
  echo "  卸载: /usr/local/bin/k3s-uninstall.sh"
}

# ================================== 主流程 ===================================
check_system
setup_apt_source
setup_packages
disable_swap
disable_firewall
setup_time
setup_kernel
setup_nfs_kernel
install_helm
setup_k3s_config
setup_k3s_registry
install_k3s
setup_kubeconfig
verify
