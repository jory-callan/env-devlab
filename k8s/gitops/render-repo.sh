#!/bin/bash
# render-repo.sh -- 统一替换 gitops/ 内的 Git 仓库地址
#
# 为什么需要: children/ 下的 Application 定义会被 ArgoCD 从 Git 仓库读取，
# ArgoCD 不支持对普通 YAML 做变量替换，因此仓库地址必须是字面量。
# 当仓库地址变更时，用本脚本统一改写（改完需 git commit，ArgoCD 才会读到）。
#
# 用法:
#   bash render-repo.sh                                  # 切换为默认 GitHub 仓库
#   bash render-repo.sh <repo-url> [revision]
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_URL="${1:-ssh://git@github.com/jory-callan/env-devlab.git}"
REVISION="${2:-main}"

echo ">> 目标仓库: ${REPO_URL} @ ${REVISION}"

# 1) children/ 内的 Application（字面量仓库地址）
find "$DIR/root/children" -name "*.yaml" -type f -exec \
    sed -i '' -E "s#repoURL: ssh://git@[^ ]+#repoURL: ${REPO_URL}#g" {} \;
find "$DIR/root/children" -name "*.yaml" -type f -exec \
    sed -i '' -E "s#targetRevision: [^ ]+#targetRevision: ${REVISION}#g" {} \;

# 2) root-app.yaml 的占位符（由 bootstrap/argocd/install.sh 渲染后 apply）
sed -i '' -E "s#__REPO_URL__#${REPO_URL}#g" "$DIR/root/root-app.yaml"
sed -i '' -E "s#__REPO_REVISION__#${REVISION}#g" "$DIR/root/root-app.yaml"

echo "[OK] 仓库地址已更新"
echo ""
echo "请检查 diff 后提交:"
echo "  git diff -- k8s/gitops/"
