# ansible — Node Initialization Quick-Apply

Ansible playbooks for Linux base initialization and Docker installation,
targeting k3s cluster nodes.

## Quick start

```bash
# 1. Fill in your nodes
vi inventories/production/hosts.ini

# 2. Apply (installs collection dependencies automatically)
bash apply.sh linux-init     # base initialization
bash apply.sh docker         # install Docker
bash apply.sh all            # both

# 3. Extra arguments are passed through to ansible-playbook
bash apply.sh all -l node1 --check --diff
```

## Content

| Playbook | Content |
|---|---|
| `linux-init` | Hostname/timezone, domestic mirrors (Rocky 8/9/10 + Ubuntu 20/22/24), base tool packages, kernel modules and sysctl, swap disablement, ulimit, journald/logrotate limits, SELinux/firewall |
| `docker` | Old-version removal, Aliyun Docker CE repository (RedHat/Debian), daemon.json configuration, service startup verification |

## Layout

```
ansible/
├── apply.sh                        # quick-apply entry
├── ansible.cfg                     # defaults (inventory/roles_path/SSH)
├── requirements.yml                # collection dependencies (community.general)
├── inventories/production/
│   ├── hosts.ini                   # node inventory (example)
│   └── group_vars/all.yml          # environment-level variables (role defaults live in defaults/)
├── playbooks/
│   ├── linux-init.yml
│   └── docker.yml
└── roles/
    ├── linux-init/                 # defaults/ meta/ tasks (split by step)/ templates
    └── docker/                     # defaults/ meta/ tasks (install/configure/service)/ templates
```

## Single-step runs

Every step carries tags, so individual steps can be run in isolation:

```bash
bash apply.sh linux-init --tags swap              # swap only
bash apply.sh linux-init --skip-tags security     # skip the security step
bash apply.sh docker --tags configure             # rewrite daemon.json and restart only
```

Available tags: `hostname timezone repos mirror packages kernel sysctl modules
swap limits ulimit logging journald logrotate security selinux firewall`
(linux-init); `docker check install configure service` (docker).

## Notes

- All tasks run with `become: yes` (root by default; adjust `ansible_user`
  in hosts.ini)
- Role defaults live in `roles/<role>/defaults/main.yml`; override per
  environment in `inventories/production/group_vars/all.yml`
- `registry-mirrors` is disabled by default: an unreachable mirror makes
  every pull time out. Uncomment the example in group_vars when you have
  a working mirror
- The compose service stacks live in `stacks/` at the repository root and
  are independent of this directory
