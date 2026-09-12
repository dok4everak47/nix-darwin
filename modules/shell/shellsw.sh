# shellsw — 登录 shell 调度器 + 切换 CLI(一个文件,按 $0 的名字分角色)
#
#   swsh   系统登录 shell。dscl UserShell 指向 /run/current-system/sw/bin/swsh,
#          它读状态文件 → export SHELL → exec 选中的 shell(参数原样透传,
#          所以 `-l` / `-c cmd` / ssh 单命令都由真正的 shell 处理)。
#   sw     用户命令。`sw` 看当前设置,`sw <name>` 写状态文件即切换;
#          在交互终端里顺手 exec 进新 shell,不用重开窗口。
#
# 为什么用调度器而不是运行时 chsh:
#   登录 shell 由 nix-darwin 声明(users.users.<u>.shell),每次 rebuild 都会用
#   dscl 把 UserShell 强制同步回配置值 → 运行时 chsh 的结果会被下一次 rebuild
#   覆盖掉,而且 chsh 要输密码。调度器路径 /run/current-system/sw/bin/swsh 恒定
#   不变,切换只改用户可写的状态文件,所以既"立即生效"又"rebuild 不还原",
#   全程不需要 sudo / 密码。
#
# 上面的 SW_DEFAULT / SW_ORDER / SW_SHELLS 由 modules/shell/login-shell.nix 从
# nix 配置生成(nix 仍是单一事实来源)。本文件不硬编码任何 shell 路径。

set -euo pipefail

# ── 状态文件位置 ─────────────────────────────────────────────────────
sw_state_file() {
  printf '%s\n' "${XDG_STATE_HOME:-$HOME/.local/state}/shellsw/current"
}

# ── 当前选择:状态文件为空/损坏/不支持 → 回退 nix 默认值 ─────────────
sw_current() {
  local name
  name=$(head -n1 "$(sw_state_file)" 2>/dev/null | tr -d '[:space:]' || true)
  # 注意:bash 关联数组不接受空 key(空 key 会报 bad array subscript),先判空。
  if [ -z "$name" ] || [ -z "${SW_SHELLS[$name]:-}" ]; then
    name=$SW_DEFAULT
  fi
  printf '%s\n' "$name"
}

# ── 解析成可执行文件,逐级兜底:选中 → 默认 → /bin/zsh ───────────────
# 登录 shell 不能把用户挡在门外:任何异常都必须退到一个能用的 shell。
sw_resolve() {
  local target
  target=""
  if [ -n "${1-}" ]; then
    target=${SW_SHELLS[$1]:-}
  fi
  if [ -n "$target" ] && [ -x "$target" ]; then
    printf '%s\n' "$target"
    return 0
  fi
  target=${SW_SHELLS[$SW_DEFAULT]:-}
  if [ -n "$target" ] && [ -x "$target" ]; then
    printf '%s\n' "$target"
    return 0
  fi
  printf '/bin/zsh\n'
}

# ── 角色 1:登录 shell 调度器(绝不打印状态,绝不能失败)──────────────
sw_dispatch() {
  local target
  target=$(sw_resolve "$(sw_current)")
  # 把 $SHELL 指回真正的 shell:会话里的 nvim / agent / tmux / IDE 靠 $SHELL
  # 探测 shell 类型,不能让它看到调度器。
  export SHELL=$target
  exec "$target" "$@"
}

# ── 角色 2:CLI ───────────────────────────────────────────────────────
sw_usage() {
  printf 'sw — 切换登录 shell(立即生效,rebuild 不还原)\n'
  printf '用法:\n'
  printf '  sw                  查看当前设置\n'
  printf '  sw <%s>      切换(交互终端里立即进入新 shell)\n' "${SW_ORDER// /|}"
  printf '可用: %s    (nix 默认: %s)\n' "$SW_ORDER" "$SW_DEFAULT"
}

sw_status() {
  local state first current target
  state=$(sw_state_file)
  first=$(head -n1 "$state" 2>/dev/null | tr -d '[:space:]' || true)
  current=$(sw_current)
  target=$(sw_resolve "$current")
  printf '登录 shell: %s → %s\n' "$current" "$target"
  if [ -n "$first" ] && [ -n "${SW_SHELLS[$first]:-}" ]; then
    printf '状态文件:   %s\n' "$state"
  else
    printf '状态文件:   无/无效,回退 nix 默认(%s)\n' "$SW_DEFAULT"
  fi
  printf '可用:       %s    (nix 默认: %s)\n' "$SW_ORDER" "$SW_DEFAULT"
}

sw_switch() {
  local name=$1 state dir
  if [ -z "${SW_SHELLS[$name]:-}" ]; then
    printf 'sw: 不支持的 shell: %s(可用: %s)\n' "$name" "$SW_ORDER" >&2
    return 2
  fi
  state=$(sw_state_file)
  dir=$(dirname "$state")
  mkdir -p "$dir"
  printf '%s\n' "$name" > "$state"
  printf '✓ 登录 shell → %s (%s)\n' "$name" "${SW_SHELLS[$name]}"
  if [ -t 0 ] && [ -t 1 ] && [ -z "${SW_NO_EXEC:-}" ]; then
    printf '→ 当前终端立即进入 %s(-l,等同新窗口的登录 shell)\n' "$name"
    export SHELL=${SW_SHELLS[$name]}
    exec "${SW_SHELLS[$name]}" -l
  fi
  printf '  本次会话未切换(非交互环境);新开终端 / 重新登录后生效\n'
}

sw_main() {
  local role
  role=${0##*/}

  # 被系统当登录 shell 调用时(swsh)只做调度:任何输出都会玷污交互会话。
  if [ "$role" = "swsh" ]; then
    sw_dispatch "$@"
  fi

  case "${1-}" in
    "") sw_status ;;
    -h | --help) sw_usage ;;
    -*) printf 'sw: 未知选项: %s\n' "$1" >&2; sw_usage >&2; return 2 ;;
    *) sw_switch "$1" ;;
  esac
}

sw_main "$@"
