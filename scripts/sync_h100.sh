#!/usr/bin/env bash

set -euo pipefail

usage() {
    cat <<'EOF'
用法：./scripts/sync_h100.sh [--dry-run] [--help]

从当前分支的上游远端执行 fast-forward 拉取，并同步全部 Git 子模块。
脚本会拒绝覆盖根仓库或子模块中的未提交修改。

选项：
  --dry-run  只检查状态并显示将执行的命令，不修改仓库
  -h, --help 显示帮助
EOF
}

fail() {
    printf '错误：%s\n' "$*" >&2
    exit 1
}

dry_run=0
while (($# > 0)); do
    case "$1" in
        --dry-run)
            dry_run=1
            ;;
        -h|--help)
            usage
            exit 0
        ;;
        *)
            usage >&2
            fail "未知参数：$1"
            ;;
    esac
    shift
done

command -v git >/dev/null 2>&1 || fail '未找到 git。'

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(git -C "$script_dir" rev-parse --show-toplevel) || fail '无法定位 Git 仓库根目录。'
cd "$repo_root"

branch=$(git symbolic-ref --quiet --short HEAD) || fail '根仓库处于 detached HEAD，无法确定待更新分支。'
git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' >/dev/null 2>&1 \
    || fail "当前分支 ${branch} 未配置上游远端。"

if [[ -n $(git status --porcelain --ignore-submodules=all) ]]; then
    git status --short --ignore-submodules=all >&2
    fail '根仓库存在未提交修改，请先在本机按流程提交并推送；不要在 H100 上直接修改源码。'
fi

if ! git submodule foreach --recursive '
    if [ -n "$(git status --porcelain)" ]; then
        printf "子模块 %s 存在未提交修改：\n" "$displaypath" >&2
        git status --short >&2
        exit 1
    fi
'; then
    fail '子模块存在未提交修改，已停止同步。'
fi

run() {
    printf '+ '
    printf '%q ' "$@"
    printf '\n'
    if ((dry_run == 0)); then
        "$@"
    fi
}

printf '仓库：%s\n分支：%s\n' "$repo_root" "$branch"
run git pull --ff-only
run git submodule sync --recursive
run git submodule update --init --recursive

if ((dry_run == 1)); then
    printf '预览完成，未修改仓库。\n'
else
    printf '同步完成。当前状态：\n'
    git status --short --branch
    git submodule status --recursive
fi
