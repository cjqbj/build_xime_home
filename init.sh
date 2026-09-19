#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

disable_codespaces_hook() {
    local hook_path="${1:-}"
    [[ -n "$hook_path" ]] || return 0

    local backup="${hook_path}.codespaces-disabled"
    if [[ -f "$hook_path" ]] && grep -Eqi 'codespaces|fork_repo|GITHUB_REPOSITORY' "$hook_path" 2>/dev/null; then
        if [[ ! -e "$backup" ]]; then
            echo "检测到 Codespaces hook，临时禁用: $hook_path"
            mv "$hook_path" "$backup"
        fi
    fi
}

restore_codespaces_hook() {
    local hook_path="${1:-}"
    [[ -n "$hook_path" ]] || return 0

    local backup="${hook_path}.codespaces-disabled"
    if [[ -f "$backup" ]] && [[ ! -f "$hook_path" ]]; then
        echo "恢复 Codespaces hook: $hook_path"
        mv "$backup" "$hook_path"
        chmod +x "$hook_path" 2>/dev/null || true
    fi
}

# Codespaces 会在 .git/hooks/post-commit 中注入一个 fork 仓库钩子；
# 这个钩子会和 git lfs install --local 发生冲突，导致一键初始化失败。
# 先禁用它，完成初始化后再恢复，避免干扰 Codespaces 原有行为。
disable_codespaces_hook "$ROOT_DIR/.git/hooks/post-commit"
#trap 'restore_codespaces_hook "$ROOT_DIR/.git/hooks/post-commit"' EXIT

if command -v git >/dev/null 2>&1 && git lfs version >/dev/null 2>&1; then
    echo "初始化 Git LFS hook（忽略 Codespaces 冲突）..."
    git lfs install --local || true
fi

# 对这个 bootstrap 仓库，不需要执行普通 git pull；
# 远端分支可能和本地存在轻微分叉，直接 pull 会因为“需要指定合并策略”而失败。
# 改为显式 fetch + reset --hard + clean，此时本地细微修改会被忽略，按远端 main 精确同步。
if git -C "$ROOT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "同步仓库到 origin/main（忽略本地细微修改）..."
    git -C "$ROOT_DIR" fetch --all --tags --prune || true
    git -C "$ROOT_DIR" remote set-url origin https://github.com/775cpu/build_xime_home.git 2>/dev/null || true
    git -C "$ROOT_DIR" checkout -B main origin/main 2>/dev/null || git -C "$ROOT_DIR" checkout main 2>/dev/null || true
    git -C "$ROOT_DIR" reset --hard origin/main 2>/dev/null || git -C "$ROOT_DIR" reset --hard HEAD 2>/dev/null || true
    git -C "$ROOT_DIR" clean -fdx 2>/dev/null || true
    git -C "$ROOT_DIR" lfs pull 2>/dev/null || true
fi

git clone https://github.com/wxsb-web/multi_mqtt

# 这是真正需要拉取/构建的项目代码，不要在上层仓库里反复执行全量 git pull。
./git.py clone --depth=1 https://github.com/775cpu/Xime_rpc

cd Xime_rpc
#git submodule update --init --recursive
echo 第一次执行耗时约8分钟，后续执行耗时约几秒钟
./build.sh "$@"

