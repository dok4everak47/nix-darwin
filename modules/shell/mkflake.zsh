# ── mkflake：从 /etc/nix-darwin/templates 快速生成项目骨架 ─────────────────
#   纯 zsh 实现的交互式选择菜单（方向键/jk 移动、enter 确认、q 取消），
#   右侧实时预览模板的 flake.nix。不依赖 fzf / dialog / gum 等外部工具。
#
#   mkflake                    交互选择模板，再问目标目录
#   mkflake go                 跳过菜单，直接用 go 模板在当前目录生成
#   mkflake python myapp       新建 myapp/ 并用 python 模板
#   mkflake -l                 纯文本列出模板


# 通用开发 CLI 工具候选（所有模板共用）
typeset -ga _mkf_common=(ripgrep fd jq bat eza zoxide fzf git lazygit tree htop bottom just httpie glow delta sd procs yq tokei hyperfine mcfly xh neovim nixd git-cliff nil)

# 全量包名缓存：与 search.nixos.org 同源，取自 nixpkgs <channel> 的 legacyPackages 顶层属性名
# 默认架构跟随本机（uname → nix 平台）；python3Packages 大包集走独立覆盖文件，按需加载
typeset -g _mkf_channel="26.05"
typeset -g _mkf_arch="$(uname -m | sed -E 's/^arm64$/aarch64/')-$(uname -s | tr 'A-Z' 'a-z')"
_mkf_cache_core() { print -r -- "${XDG_CACHE_HOME:-$HOME/.cache}/mkflake/pkgs-${_mkf_channel}-${_mkf_arch}.txt"; }
_mkf_cache_py()   { print -r -- "${XDG_CACHE_HOME:-$HOME/.cache}/mkflake/py-${_mkf_channel}-${_mkf_arch}.txt"; }
# 包描述缓存：取自 search.nixos.org 后端（真实 meta.description），按 channel 存 TSV
_mkf_cache_desc() { local ch="${1:-$_mkf_channel}"; print -r -- "${XDG_CACHE_HOME:-$HOME/.cache}/mkflake/desc-${ch}.txt"; }
# 描述查找记忆（每次进入 TUI 时清空，避免跨 channel 串味）
typeset -gA _mkf_dl
# 按属性名查描述；先精确查 full，再查去 python 前缀的裸名；命中打印并返回 0
_mkf_desc_lookup() {
  local key="$1" mk cache dsc
  [[ -n "$key" ]] || return 1
  mk="${_mkf_channel}|${key}"
  if (( ${+_mkf_dl[$mk]} )); then
    dsc="${_mkf_dl[$mk]}"
    [[ -n "$dsc" ]] && { print -r -- "$dsc"; return 0; }
    return 1
  fi
  cache="$(_mkf_cache_desc)"
  [[ -r "$cache" ]] || return 1
  dsc=$(awk -F'\t' -v k="$key" '$1==k{print $2; exit}' "$cache" 2>/dev/null)
  _mkf_dl[$mk]="$dsc"
  [[ -n "$dsc" ]] && { print -r -- "$dsc"; return 0; }
  return 1
}
# 搜索时合并 core + python 覆盖（若存在），去重后限 800 条
_mkf_grep_pkgs() {
  { grep -iF -- "$1" "$(_mkf_cache_core)" 2>/dev/null
    grep -iF -- "$1" "$(_mkf_cache_py)"   2>/dev/null; } | sort -u | head -n 800
}

# 工具用途对照（bare 包名 → 中文用途，用于右侧预览；缺失时回退为 “nixpkgs 包：<名>”）
typeset -gA _mkf_desc=(
  ripgrep   '代码/文件内容搜索（grep 的 Rust 替代）'
  fd        '文件/目录查找（find 的现代化替代）'
  jq        'JSON 处理与查询命令行工具'
  bat       '带语法高亮与 git 集成的 cat 替代'
  eza       '现代 ls 替代，支持图标/树形'
  zoxide    '智能 cd，按频率跳转目录'
  fzf       '模糊查找器（交互过滤）'
  git       '分布式版本控制'
  lazygit   '终端图形化 Git 客户端'
  tree      '目录树形结构展示'
  htop      '交互式进程/资源监控'
  bottom    '跨平台系统监控（btm）'
  just      '命令 runner，类似 Make 但更简单'
  httpie    '人性化 HTTP 客户端'
  glow      '终端 Markdown 阅读器'
  delta     '语法高亮的 git diff 查看器'
  sd        '直观的 sed 替代（查找替换）'
  procs     '现代 ps 替代，树形展示进程'
  yq        'YAML/XML/JSON 命令行处理'
  tokei     '代码统计与语言分析'
  hyperfine '命令行基准测试/性能对比'
  mcfly     '智能 shell 历史搜索'
  xh        'HTTP 客户端（类 curl，JSON 友好）'
  neovim    '现代化 Vim 编辑器'
  nixd      'Nix 语言服务（LSP）'
  git-cliff '基于 git 历史生成 changelog'
  nil       'Nix 语言 IDE 后端（nil LSP）'
)

# 顶层菜单：1 创建模板 / 2 新增删除工具包；结果写入全局 $_mkf_menu
_mkflake_menu() {
  emulate -L zsh
  setopt typesetsilent
  local -a opts=("1  创建新项目（从模板初始化）" "2  新增/删除工具包（仅改当前 flake.nix）")
  local -i n=2 cur=1
  local key seq out row
  local esc=$'\e'
  typeset -g _mkf_menu=1
  typeset -g _mkf_reset=$'\e[0m\e[?25h'
  print -n $'\e[?25l\e[2J\e[H'
  trap 'print -n -- $_mkf_reset; return 130' INT TERM
  while true; do
    L=$(( ${LINES:-24} - 1 )); C=${COLUMNS:-80}
    (( L < 10 )) && L=10
    (( C < 60 )) && C=60
    out=""
    printf -v out '%s\e[H\e[1;36m mkflake · 选择要做什么\e[0m\e[K' "$out"
    printf -v out '%s\e[2;1H\e[K' "$out"
    row=3
    local i
    for ((i = 1; i <= n; i++)); do
      if (( i == cur )); then
        printf -v out '%s\e[%d;1H\e[7m %s \e[0m\e[K' "$out" $row "${opts[i]}"
      else
        printf -v out '%s\e[%d;1H %s\e[K' "$out" $row "${opts[i]}"
      fi
      (( row++ ))
    done
    while (( row <= L - 1 )); do
      printf -v out '%s\e[%d;1H\e[K' "$out" $row
      (( row++ ))
    done
    printf -v out '%s\e[%d;1H\e[7m ↑↓/jk 选择 · enter 确认 · q 退出 \e[0m\e[K' "$out" $L
    print -rn -- $'\e[?2026h'"$out"$'\e[?2026l'
    read -k1 -s key
    case "$key" in
      ($'\r'|$'\n') { _mkf_menu=$cur; print -n -- "$_mkf_reset"$'\e[2J\e[H'; return 0; } ;;
      (q|Q) { print -n -- "$_mkf_reset"$'\e[2J\e[H'; return 130; } ;;
      (k)   (( cur > 1 )) && (( cur-- )) ;;
      (j)   (( cur < n )) && (( cur++ )) ;;
      (g)   cur=1 ;;
      (G)   cur=$n ;;
      ($esc)
        read -k2 -s -t 0.05 seq
        case "$seq" in
          ('[A') (( cur > 1 )) && (( cur-- )) ;;
          ('[B') (( cur < n )) && (( cur++ )) ;;
          ('[H'|'[1~') cur=1 ;;
          ('[F'|'[4~') cur=$n ;;
        esac ;;
    esac
  done
}

# 仅修改目标目录已有的 flake.nix：删除现有包 + 新增包，不触碰其它文件

# 仅修改目标目录已有的 flake.nix：删除现有包 + 新增包，不触碰其它文件
# 双面板 UI：面板1=删除现有，面板2=新增；Tab 切换，各自保留勾选，最后一起应用

# 从 nixpkgs <channel> 拉取完整包名清单（与 search.nixos.org 同源），缓存到本地供 mkflake tools / 创建流搜索
# 用法: _mkflake_refresh_pkgs [arch] [channel] [with_py(0/1)]
#   arch=默认本机架构；channel=默认 $_mkf_channel；with_py=1 时额外加载 python3Packages 大包集（独立覆盖文件，可拆分）
_mkflake_refresh_pkgs() {
  local arch="${1:-$_mkf_arch}"
  local channel="${2:-$_mkf_channel}"
  local with_py="${3:-0}"
  local core py tmp tmp2
  core="$(_mkf_cache_core)"; py="$(_mkf_cache_py)"
  tmp="$(mktemp)"; tmp2="$(mktemp)"
  # 并发锁：防止多个 mkflake 同时跑重 nix eval / 拉取，把 CPU 拉满导致机器过热
  local lock="${core:h}/.refresh.lock" lts
  if [[ -d "$lock" ]]; then
    lts=$(date -r "$lock" +%s 2>/dev/null); lts=${lts//[^0-9]/}; [[ -z "$lts" ]] && lts=0
    (( $(date +%s) - lts > 1800 )) && rmdir "$lock" 2>/dev/null
  fi
  if ! mkdir "$lock" 2>/dev/null; then
    print "跳过：已有 mkflake 刷新进程在运行（锁 ${lock}）。"
    rm -f "$tmp" "$tmp2"
    return 1
  fi
  trap 'rmdir "$lock" 2>/dev/null; return 130' INT TERM
  print -n "正在枚举 nixpkgs ${channel} (${arch}) 顶层包名（全量求值，较慢，可安全 Ctrl-C）… "
  if ! timeout 2000 nix --extra-experimental-features 'nix-command flakes' eval --json \
        "github:NixOS/nixpkgs/nixos-${channel}#legacyPackages.${arch}" \
        --apply 'x: builtins.attrNames x' >"$tmp" 2>"$tmp.err"; then
    local rc=$?
    if (( rc == 124 )); then
      print "超时：nix eval 在 2000s 内仍未完成，已自动放弃（此操作本就极慢，可改日再试）。"
    else
      print "失败：nix eval 退出码 $rc。真实报错："
      sed 's/^/    /' "$tmp.err" | head -40
    fi
    rm -f "$tmp" "$tmp2" "$tmp.err"
    rmdir "$lock" 2>/dev/null
    trap - INT TERM
    return 1
  fi
  if [[ ! -s "$tmp" ]]; then
    print "失败：nix eval 未产出数据。报错："
    sed 's/^/    /' "$tmp.err" | head -40
    rm -f "$tmp" "$tmp2" "$tmp.err"
    rmdir "$lock" 2>/dev/null
    trap - INT TERM
    return 1
  fi
  if ! python3 -c 'import sys,json; sys.stdout.write("\n".join(json.load(open(sys.argv[1]))))' "$tmp" >"$tmp2" 2>/dev/null || [[ ! -s "$tmp2" ]]; then
    print "失败：nix 返回的数据无法解析为包名列表（可能被截断）。"
    rm -f "$tmp" "$tmp2" "$tmp.err"
    rmdir "$lock" 2>/dev/null
    trap - INT TERM
    return 1
  fi
  sort -u "$tmp2" >"$tmp"
  mkdir -p "${core:h}"
  mv -f "$tmp" "$core"
  rm -f "$tmp2" "$tmp.err"
  print " 完成（$(wc -l < "$core") 个顶层包名，已缓存到 $core）。"
  if (( with_py )); then
    print -n "  正在追加 python3Packages 大包集（同样很慢）… "
    if ! timeout 2000 nix --extra-experimental-features 'nix-command flakes' eval --json \
        "github:NixOS/nixpkgs/nixos-${channel}#legacyPackages.${arch}.python3Packages" \
        --apply 'x: builtins.attrNames x' >"$tmp" 2>"$tmp.err"; then
      print "  跳过：python3Packages 求值失败（$(sed -n '1p' "$tmp.err")）。"
    elif [[ ! -s "$tmp" ]]; then
      print "  跳过：python3Packages 未产出数据。"
    else
      if python3 -c 'import sys,json; sys.stdout.write("\n".join("python3Packages."+n for n in json.load(open(sys.argv[1]))))' "$tmp" >"$tmp2" 2>/dev/null && [[ -s "$tmp2" ]]; then
        sort -u "$tmp2" >"$tmp"
        mkdir -p "${py:h}"
        mv -f "$tmp" "$py"
        rm -f "$tmp2" "$tmp.err"
        print " 完成（$(wc -l < "$py") 个 python 包名 → $py）。"
      else
        rm -f "$tmp2" "$tmp.err"
        print "  跳过：python3Packages 数据解析失败。"
      fi
    fi
    rm -f "$tmp" "$tmp2" "$tmp.err"
  fi
  rmdir "$lock" 2>/dev/null
  trap - INT TERM
}

# 从 search.nixos.org 后端拉取每个包的真实描述（meta.description），写 desc-<channel>.txt
# 后端凭据在其公开前端 JS 里，动态抓取；python 包名做 python3xx→python3Packages 别名归一
_mkflake_refresh_desc() {
  local channel="${1:-$_mkf_channel}"
  local out; out="$(_mkf_cache_desc "$channel")"
  mkdir -p "${out:h}"
  print -n "正在从 search.nixos.org 拉取 ${channel} 包描述… "
  python3 - "$channel" "$out" "${XDG_CACHE_HOME:-$HOME/.cache}/mkflake" <<'PYEOF'
import sys, json, re, urllib.request, base64, gzip, glob, os
channel, out, cachedir = sys.argv[1], sys.argv[2], sys.argv[3]
def get(url, data=None, headers=None):
    h = {"Accept-Encoding": "identity"}
    if headers: h.update(headers)
    last = None
    for _ in range(4):
        try:
            req = urllib.request.Request(url, data=data, headers=h)
            with urllib.request.urlopen(req, timeout=90) as r:
                b = r.read()
                if r.headers.get("Content-Encoding") == "gzip":
                    b = gzip.decompress(b)
                return b
        except Exception as e:
            last = e
    raise last
base = "https://search.nixos.org"
try:
    html = get(base + "/packages?channel=" + channel).decode("utf-8", "replace")
    mjs = re.search(r'/static/js/index\.[0-9a-f]+\.js', html)
    js = get(base + mjs.group(0)).decode("utf-8", "replace")
    schema = re.search(r'csearchMappingSchemaVersion:parseInt\("(\d+)"\)', js).group(1)
    user = re.search(r'elasticsearchUsername:"([^"]*)"', js).group(1)
    pw = re.search(r'elasticsearchPassword:"([^"]*)"', js).group(1)
except Exception as e:
    print("失败：无法解析后端配置（%s）。" % e); sys.exit(1)
auth = "Basic " + base64.b64encode((user + ":" + pw).encode()).decode()
idx = "latest-%s-nixos-%s" % (schema, channel)
headers = {"Content-Type": "application/json", "Authorization": auth, "Accept-Encoding": "identity"}
# 过滤集合：只保留本地目录里实际存在的包名（core + python 覆盖，任意 arch）
allowed = set()
for pat in ("pkgs-%s-*.txt" % channel, "py-%s-*.txt" % channel):
    for f in glob.glob(os.path.join(cachedir, pat)):
        for line in open(f, errors="replace"):
            s = line.strip()
            if s: allowed.add(s)
rows = {}
def add(k, desc):
    if not k or desc is None: return
    desc = " ".join(str(desc).split())
    if not desc: return
    if allowed and k not in allowed: return
    if k not in rows: rows[k] = desc
def handle(hits):
    for h in hits:
        s = h["_source"]; attr = s.get("package_attr_name"); desc = s.get("package_description")
        add(attr, desc)
        if attr:
            mm = re.match(r'^python3\d+Packages\.(.+)$', attr)
            if mm: add("python3Packages." + mm.group(1), desc)
try:
    after = None
    while True:
        body = {"size": 5000, "query": {"term": {"type": "package"}},
                "sort": [{"_id": "asc"}],
                "_source": ["package_attr_name", "package_description"]}
        if after:
            body["search_after"] = after
        d = json.loads(get(base + "/backend/" + idx + "/_search", data=json.dumps(body).encode(), headers=headers))
        hits = d["hits"]["hits"]
        if not hits:
            break
        handle(hits)
        after = hits[-1]["sort"]
        if len(hits) < 5000:
            break
except Exception as e:
    print("失败：抓取描述出错（%s）。" % e); sys.exit(1)
with open(out, "w") as fh:
    for k in sorted(rows):
        fh.write(k + "\t" + rows[k].replace("\t", " ").replace("\n", " ") + "\n")
print("完成（%d 条描述 → %s）。" % (len(rows), out))
PYEOF
}

_mkflake_edit() {
  local target="${1:-.}"
  target="${target/#\~/$HOME}"
  local f="$target/flake.nix"
  [[ -f "$f" ]] || { print -r -- "错误: $f 不存在（本模式只修改已有 flake.nix）"; return 1 }
  if [[ ! -t 0 || ! -t 1 ]]; then
    print -r -- "错误: mkflake tools 需要交互终端（tty），请在终端里运行。"
    return 1
  fi

  local existing
  existing=$(python3 - "$f" <<'PYEOF'
import sys, re
s = open(sys.argv[1]).read()
m = re.search(r'(packages\s*=\s*(?:with\s+pkgs;\s*)?\[)(.*?)(\])', s, re.S)
print(" ".join(m.group(2).split())) if m else print("")
PYEOF
)
  local -a existing_arr=(${(s: :)existing})
  local -A _exist_set=()
  for _e in "${existing_arr[@]}"; do _exist_set[$_e]=1; done

  local -a cands=("${_mkf_common[@]}")
  _mkflake_pkgs python
  cands+=( "${_mkf_pylibs[@]/#/python3Packages.}" )
  local -a newcands=() x e found
  for x in "${cands[@]}"; do
    found=0
    for e in "${existing_arr[@]}"; do
      [[ "$x" == "$e" ]] && { found=1; break; }
    done
    (( found )) || newcands+=("$x")
  done

  emulate -L zsh
  setopt typesetsilent
  local panel=1
  local -i cur_del=1 top_del=1 cur_add=1 top_add=1
  local query_del="" query_add="" qmode_del="" qmode_add=""
  local -A rm_chosen add_chosen
  typeset -g _mkf_reset=$'\e[0m\e[?25h'
  print -n $'\e[?25l\e[2J\e[H'
  trap 'print -n -- $_mkf_reset; return 130' INT TERM

  local cur=1 top=1 query="" qmode=""
  local -a larr; local -A chosen; local -a vis
  local esc=$'\e' key seq out row name marked cn d desc
  local -i listw=30 rcol rw maxrows n i first last
  while true; do
    if (( panel == 1 )); then
      chosen=(${(kv)rm_chosen}); cur=$cur_del; top=$top_del; larr=("${existing_arr[@]}")
    elif [[ -n "$query" && -r "$(_mkf_cache_core)" ]]; then
      # 新增面板 + 关键词 + 缓存：直接扫全量包名（core + python 覆盖），剔除已存在的包（不载入大数组，避免卡顿）
      chosen=(${(kv)add_chosen}); cur=$cur_add; top=$top_add
      local -a _raw=(${(f)"$(_mkf_grep_pkgs "$query")"})
      larr=()
      for _e in "${_raw[@]}"; do (( ${+_exist_set[$_e]} )) || larr+=("$_e"); done
    else
      chosen=(${(kv)add_chosen}); cur=$cur_add; top=$top_add; larr=("${newcands[@]}")
    fi
    L=$(( ${LINES:-24} - 1 )); C=${COLUMNS:-80}
    (( L < 12 )) && L=12
    (( C < 60 )) && C=60
    (( listw > C - 26 )) && listw=$(( C - 26 ))
    (( listw < 16 )) && listw=16
    maxrows=$(( L - 4 ))
    (( maxrows < 3 )) && maxrows=3

    vis=()
    if (( panel == 2 )) && [[ -n "$query" && -r "$(_mkf_cache_core)" ]]; then
      vis=("${larr[@]}")   # 该路径下 larr 已是过滤后结果，直接采用（含 python3Packages.*，匹配 search.nixos.org）
    else
      for x in "${larr[@]}"; do
        d=${x#python3Packages.}
        if [[ -z "$query" || "${(L)d}" == *"${(L)query}"* ]]; then
          vis+=("$x")
        fi
      done
    fi
    n=${#vis[@]}
    (( n == 0 )) && { cur=1; top=1; } || {
      (( cur < 1 )) && cur=1
      (( cur > n )) && cur=n
      (( top < 1 )) && top=1
      (( top > n - maxrows + 1 )) && top=$(( n - maxrows + 1 ))
      (( top < 1 )) && top=1
      (( cur < top )) && top=cur
      (( cur > top + maxrows - 1 )) && top=$(( cur - maxrows + 1 ))
      (( top < 1 )) && top=1
    }
    rcol=$(( listw + 9 ))
    rw=$(( C - rcol ))
    (( rw < 8 )) && rw=8

    local ptag="删除现有" ptgt="新增"
    (( panel == 2 )) && { ptag="新增" ; ptgt="删除现有"; }
    out=""
    printf -v out '%s\e[H\e[1;36m mkflake · 工具包 [当前面板: %s] · 删 %d / 加 %d\e[0m\e[K' "$out" "$ptag" ${#rm_chosen} ${#add_chosen}
    first=1; last=$n
    (( n > maxrows )) && { first=$top; last=$(( top + maxrows - 1 )); }
    row=2
    for ((i = first; i <= last; i++)); do
      x=${vis[i]}; d=${x#python3Packages.}
      (( ${+chosen[$x]} )) && marked="x" || marked=" "
      if (( i == cur )); then
        printf -v out '%s\e[%d;1H\e[7m %-*s[%s]\e[0m\e[K' "$out" $row $listw "$d" "$marked"
      else
        printf -v out '%s\e[%d;1H %-*s[%s]\e[K' "$out" $row $listw "$d" "$marked"
      fi
      (( row++ ))
    done
    while (( row <= L - 3 )); do
      printf -v out '%s\e[%d;1H\e[K' "$out" $row
      (( row++ ))
    done

    if (( n > 0 )); then
      local _full _rt
      _full=${vis[cur]}
      d=${_full#python3Packages.}
      if _rt=$(_mkf_desc_lookup "$_full") || _rt=$(_mkf_desc_lookup "$d"); then
        desc="$_rt"
      else
        desc="${_mkf_desc[$d]:-nixpkgs 包：$d}"
      fi
    else
      d=""; desc="（无匹配项，按 / 重新过滤）"
    fi
    local -a dlines=(); local cl=""
    for w in ${(s: :)desc}; do
      if (( ${#cl} > 0 && ${#cl} + ${#w} + 1 > rw )); then
        dlines+=("$cl"); cl="$w"
      else
        cl+="${cl:+ }$w"
      fi
    done
    (( ${#cl} > 0 )) && dlines+=("$cl")
    row=2
    for dl in "${dlines[@]}"; do
      (( row > L - 3 )) && break
      printf -v out '%s\e[%d;%dH\e[2m%s\e[0m\e[K' "$out" $row $rcol "$dl"
      (( row++ ))
    done
    while (( row <= L - 3 )); do
      printf -v out '%s\e[%d;%dH\e[K' "$out" $row $rcol
      (( row++ ))
    done

    if [[ -n "$qmode" ]]; then
      printf -v out '%s\e[%d;1H\e[2m 搜索> %s_\e[0m\e[K' "$out" $(( L - 2 )) "$query"
    elif (( panel == 2 )) && [[ -r "$(_mkf_cache_core)" ]]; then
      printf -v out '%s\e[%d;1H\e[2m 搜索: 按 / 从 %s 全量包名过滤 (当前: %s)\e[0m\e[K' "$out" $(( L - 2 )) "$_mkf_channel" "$query"
    elif (( panel == 2 )); then
      printf -v out '%s\e[%d;1H\e[2m 搜索: 按 / 过滤（运行 mkflake --refresh-pkgs 加载 %s 全量包名）\e[0m\e[K' "$out" $(( L - 2 )) "$_mkf_channel" "$query"
    else
      printf -v out '%s\e[%d;1H\e[2m 搜索: 按 / 过滤 (当前: %s)\e[0m\e[K' "$out" $(( L - 2 )) "$query"
    fi
    printf -v out '%s\e[%d;1H\e[2m%s\e[0m' "$out" $(( L - 1 )) "${(l:$C::─:)}"
    printf -v out '%s\e[%d;1H\e[7m Tab 切到[%s] · ↑↓/jk 移动 · 空格 勾选 · / 搜索 · enter 应用 · q 取消 \e[0m\e[K' "$out" $L "$ptgt"
    print -rn -- $'\e[?2026h'"$out"$'\e[?2026l'

    read -k1 -s key
    if [[ -n "$qmode" ]]; then
      case "$key" in
        ($'\r'|$'\n'|$'\e') qmode="" ;;
        ($'\177'|$'\b') query="${query%?}" ;;
        (*) [[ "$key" == [[:print:]] ]] && query+="$key" ;;
      esac
      cur=1; top=1
      if (( panel == 1 )); then cur_del=$cur; top_del=$top; rm_chosen=(${(kv)chosen})
      else cur_add=$cur; top_add=$top; add_chosen=(${(kv)chosen}); fi
      continue
    fi
    case "$key" in
      ($'\t')
        if (( panel == 1 )); then cur_del=$cur; top_del=$top; rm_chosen=(${(kv)chosen})
        else cur_add=$cur; top_add=$top; add_chosen=(${(kv)chosen}); fi
        if (( panel == 1 )); then panel=2; else panel=1; fi
        query=""; qmode=""
        continue ;;
      ($'\r'|$'\n')
        if (( panel == 1 )); then cur_del=$cur; top_del=$top; rm_chosen=(${(kv)chosen})
        else cur_add=$cur; top_add=$top; add_chosen=(${(kv)chosen}); fi
        break ;;
      (q|Q) { print -n -- "$_mkf_reset"$'\e[2J\e[H'; return 130; } ;;
      ($'/') qmode=1; query="" ;;
      ($' ')
        if (( n )); then
          cn=${vis[cur]}
          if (( ${+chosen[$cn]} )); then unset "chosen[$cn]"; else chosen[$cn]=1; fi
        fi ;;
      (k)   (( cur > 1 )) && (( cur-- )) ;;
      (j)   (( cur < n )) && (( cur++ )) ;;
      (g)   cur=1 ;;
      (G)   cur=$n ;;
      ($esc)
        read -k2 -s -t 0.05 seq
        case "$seq" in
          ('[A') (( cur > 1 )) && (( cur-- )) ;;
          ('[B') (( cur < n )) && (( cur++ )) ;;
          ('[H'|'[1~') cur=1 ;;
          ('[F'|'[4~') cur=$n ;;
        esac ;;
    esac
    if (( panel == 1 )); then
      cur_del=$cur; top_del=$top; rm_chosen=(${(kv)chosen})
    else
      cur_add=$cur; top_add=$top; add_chosen=(${(kv)chosen})
    fi
  done
  print -n -- "$_mkf_reset"$'\e[2J\e[H'

  local -a final=()
  for x in "${existing_arr[@]}"; do
    found=0
    for e in "${(k)rm_chosen}"; do [[ "$x" == "$e" ]] && { found=1; break; }; done
    (( found )) || final+=("$x")
  done
  for x in "${(k)add_chosen}"; do
    found=0
    for e in "${final[@]}"; do [[ "$x" == "$e" ]] && { found=1; break; }; done
    (( found )) || final+=("$x")
  done

  local result
  result=$(python3 - "$f" "${final[@]}" <<'PYEOF'
import sys, re, shutil
p = sys.argv[1]
tools = sys.argv[2:]
s = open(p).read()
m = re.search(r'(packages\s*=\s*(?:with\s+pkgs;\s*)?\[)(.*?)(\])', s, re.S)
if not m:
    sys.stderr.write("WARN: 未找到 packages 列表，未修改\n")
    sys.exit(0)
joined = " ".join(tools)
repl = m.group(1) + joined + m.group(3)
s = s[:m.start()] + repl + s[m.end():]
shutil.copy2(p, p + ".bak")
open(p, "w").write(s)
print(" ".join(tools))
PYEOF
)
  print -r -- "已更新 $f"
  print -r -- "packages = with pkgs; [$result];"
}

mkflake() {
  local tdir="/etc/nix-darwin/templates"
  local -a adds=()
  local template="" target=""
  local do_refresh=0 do_desc=0 with_py=0

  if (( $# == 0 )); then
    if [[ -t 0 && -t 1 ]]; then
      _mkflake_menu || return 130
      if (( _mkf_menu == 2 )); then
        _mkflake_edit "."; return $?
      fi
    else
      print -r -- "用法: mkflake [模板] [目录] | mkflake tools [目录] | mkflake -h"
      return 0
    fi
  else
    if [[ "$1" == tools ]]; then
      shift; _mkflake_edit "${1:-.}"; return $?
    fi
  fi

  while (( $# )); do
    case "$1" in
      -l|--list) command ls -1 "$tdir"; return 0 ;;
      -h|--help)
        print -r -- "用法:"
        print -r -- "  mkflake                进入菜单（创建模板 / 增删工具包）"
        print -r -- "  mkflake [模板] [目录]  从模板创建项目 [--add 工具...]"
        print -r -- "  mkflake tools [目录]   仅修改当前目录 flake.nix 的 packages（增删工具包）"
        print -r -- "  mkflake --refresh-pkgs [--channel CH] [--arch ARCH] [--with-python]"
        print -r -- "    从 nixpkgs CH(默认${_mkf_channel}) 拉取全量包名缓存（arch 默认跟随本机 ${_mkf_arch}，--with-python 追加 python3Packages 大包集）"
        print -r -- "  mkflake --refresh-desc [--channel CH]   从 search.nixos.org 拉取真实包描述缓存"
        print -r -- "  （--with-desc 可与 --refresh-pkgs 组合，一次把包名+描述都刷好）"
        print -r -- "  模板: $(command ls -1 "$tdir" | tr '\n' ' ')"
        print -r -- "  注: Python 库写作 python3Packages.flask（交互模式自动加前缀）"
        return 0 ;;
      --add) shift
        while (( $# )) && [[ "$1" != -* ]]; do adds+=("$1"); shift; done ;;
      --refresh-pkgs) do_refresh=1; shift ;;
      --refresh-desc) do_desc=1; shift ;;
      --with-desc) do_desc=1; shift ;;
      --with-python) with_py=1; shift ;;
      --channel) [[ -n "$2" ]] && { _mkf_channel="$2"; shift; }; shift ;;
      --arch)    [[ -n "$2" ]] && { _mkf_arch="$2"; shift; }; shift ;;
      -*) print -r -- "未知选项: $1"; return 1 ;;
      *) if [[ -z "$template" ]]; then template="$1"
         elif [[ -z "$target" ]]; then target="$1"
         else print -r -- "多余参数: $1"; return 1; fi
         shift ;;
    esac
  done

  # --refresh-pkgs / --refresh-desc 延迟执行（可与 --channel/--arch/--with-python 任意顺序组合）
  if (( do_refresh || do_desc )); then
    (( do_refresh )) && { _mkflake_refresh_pkgs "" "" "$with_py" || return $?; }
    (( do_desc ))    && { _mkflake_refresh_desc "" || return $?; }
    return 0
  fi

  if [[ -z "$template" ]]; then
    if [[ -t 0 && -t 1 ]]; then
      _mkflake_select "$tdir" || { print -r -- "已取消"; return 130 }
      template=$_mkflake_choice
    else
      print -r -- "可用模板:"
      command ls -1 "$tdir" | command sed 's/^/  - /'
      printf '输入模板名 [rust]: '
      read -r template
      template="${template:-rust}"
    fi
  fi

  if [[ ! -d "$tdir/$template" ]]; then
    print -r -- "错误: 模板 \"$template\" 不存在。可用: $(command ls -1 "$tdir" | tr '\n' ' ')"
    return 1
  fi

  if [[ -z "$target" ]]; then
    printf '目标目录 [.]: '
    read -r target
    target="${target:-.}"
  fi
  target="${target/#\~/$HOME}"

  if [[ "$target" != "." && ! -d "$target" ]]; then
    command mkdir -p "$target" || return 1
  fi
  if [[ -e "$target/flake.nix" ]]; then
    print -r -- "错误: $target 下已有 flake.nix，未覆盖。"
    return 1
  fi

  command cp -R "$tdir/$template/." "$target/" || return 1
  print -r -- "已基于 [$template] 初始化: $target"

  local -a cands
  cands=( "${_mkf_common[@]}" )
  if [[ "$template" == python ]]; then
    _mkflake_pkgs python
    cands+=( "${_mkf_pylibs[@]/#/python3Packages.}" )
  fi

  if (( ${#adds} )); then
    if [[ "$template" == python ]]; then
      local -a adds_inj=()
      local a
      for a in "${adds[@]}"; do
        case "$a" in
          (*.*) adds_inj+=("$a") ;;
          (*)   adds_inj+=("python3Packages.$a") ;;
        esac
      done
      _mkflake_inject "$target/flake.nix" "${adds_inj[@]}"
    else
      _mkflake_inject "$target/flake.nix" "${adds[@]}"
    fi
  elif [[ -t 0 && -t 1 ]]; then
    _mkflake_pick "选择要加入 devShell 的工具（/ 搜索 · 空格勾选）" "${cands[@]}" || return 130
    (( ${#_mkf_tools} )) && _mkflake_inject "$target/flake.nix" "${_mkf_tools[@]}"
  fi

  print -r -- "下一步: cd $target && direnv allow && nix develop"
}

# 把工具追加进 flake.nix 的 packages 列表（单行写回，保持原括号配对）
_mkflake_inject() {
  local f=$1; shift
  (( $# )) || return 0
  local result rc
  result=$(python3 - "$f" "$@" <<'PYEOF'
import sys, re, shutil
p = sys.argv[1]
tools = sys.argv[2:]
s = open(p).read()
m = re.search(r'(packages\s*=\s*(?:with\s+pkgs;\s*)?\[)(.*?)(\])', s, re.S)
if not m:
    sys.stderr.write("WARN: 未找到 packages 列表，跳过工具注入\n")
    sys.exit(0)
existing = m.group(2).split()
for t in tools:
    t = t.strip().strip('"').strip("'")
    if t and t not in existing:
        existing.append(t)
if not existing:
    sys.exit(0)
joined = " ".join(existing)
repl = m.group(1) + joined + m.group(3)
s = s[:m.start()] + repl + s[m.end():]
shutil.copy2(p, p + ".bak")
open(p, "w").write(s)
print(" ".join(existing))
PYEOF
)
  rc=$?
  if (( rc == 0 )); then
    print -r -- "已注入工具: $result"
  fi
  return $rc
}

# 从 nixos-26.05 的 nixpkgs 拉取 Python 模块包名（search.nixos.org 索引的同一份数据）
# 结果（裸名）写入全局 $_mkf_pylibs；带 1 天本地缓存，失败时回退到常见库清单
_mkflake_pkgs() {
  typeset -g _mkf_pylibs=()
  local cache="${XDG_CACHE_HOME:-$HOME/.cache}/mkflake/python-modules-${_mkf_channel}.txt"
  if [[ -f "$cache" ]]; then
    local mts now
    now=$(date +%s); mts=$(date -r "$cache" +%s 2>/dev/null); mts=${mts//[^0-9]/}; [[ -z "$mts" ]] && mts=0
    if (( now - mts < 86400 )); then
      _mkf_pylibs=(${(f)"$(cat "$cache")"})
      return 0
    fi
  fi
  local page=1 got=0 names="" chunk url
  local -a hdrs=( -H "Accept: application/vnd.github+json" )
  [[ -n "$GITHUB_TOKEN" ]] && hdrs+=( -H "Authorization: Bearer $GITHUB_TOKEN" )
  while (( page <= 40 )); do
    url="https://api.github.com/repos/NixOS/nixpkgs/contents/pkgs/development/python-modules?ref=nixos-${_mkf_channel}&per_page=1000&page=$page"
    # 命中 GitHub 限流(匿名 60 次/小时)或出错时，curl -f 失败/接口返回 message，下面会提前 break
    chunk=$(command curl -fsSL --connect-timeout 15 --max-time 60 "${hdrs[@]}" "$url" 2>/dev/null | python3 -c 'import sys,json
raw=sys.stdin.read()
try:
    d=json.loads(raw)
except Exception:
    sys.exit(0)
if isinstance(d,dict):
    msg=d.get("message","")
    if msg:
        sys.stderr.write("GH_API: "+msg[:120]+"\n")
        sys.exit(0)
print("\n".join(x["name"] for x in d if isinstance(x,dict) and "name" in x))')
    got=${#${(f)chunk}}
    [[ -n "$chunk" ]] && names+="$chunk"$'\n'
    (( got < 1000 )) && break
    (( page++ ))
  done
  if [[ -n "$names" ]]; then
    _mkf_pylibs=(${(f)names})
    command mkdir -p "${cache:h}" 2>/dev/null
    print -r -- "$names" > "$cache" 2>/dev/null
  else
    _mkf_pylibs=(requests flask django numpy scipy pandas matplotlib pytest black ruff mypy poetry pip-tools virtualenv httpx fastapi uvicorn gunicorn ipython pylint isort)
    print -r -- "（网络不可用，使用内置常见 Python 库清单）"
  fi
}

# 工具多选界面（双栏：左列表 / 右用途），支持搜索过滤(/)、滚动、空格勾选
# $1 = 标题；剩余参数 = 候选注入名数组；结果写入全局 $_mkf_tools
_mkflake_pick() {
  emulate -L zsh
  setopt typesetsilent
  local title="$1"; shift
  local -a all=("$@")
  (( ${#all} )) || { typeset -g _mkf_tools=(); return 0 }
  local -A chosen
  local -i n=${#all} cur=1 top=1 listw=30
  local key seq out row name marked cn qmode="" query="" x d desc
  local esc=$'\e'
  typeset -g _mkf_tools=()
  typeset -g _mkf_reset=$'\e[0m\e[?25h'
  print -n $'\e[?25l\e[2J\e[H'
  trap 'print -n -- $_mkf_reset; return 130' INT TERM

  local -a vis
  while true; do
    L=$(( ${LINES:-24} - 1 )); C=${COLUMNS:-80}
    (( L < 12 )) && L=12
    (( C < 60 )) && C=60
    (( listw > C - 26 )) && listw=$(( C - 26 ))
    (( listw < 16 )) && listw=16
    local -i maxrows=$(( L - 4 ))
    (( maxrows < 3 )) && maxrows=3

    vis=()
    if [[ -n "$query" && -r "$(_mkf_cache_core)" ]]; then
      # 有关键词且有缓存：扫全量包名（core + python 覆盖），再合并精选候选
      local -a _raw=(${(f)"$(_mkf_grep_pkgs "$query")"})
      local -A _seen=()
      for x in "${_raw[@]}"; do
        [[ -z "$x" ]] && continue
        (( ${+_seen[$x]} )) && continue
        _seen[$x]=1; vis+=("$x")
      done
      for x in "${all[@]}"; do
        [[ -z "$x" ]] && continue
        d=${x#python3Packages.}
        if [[ -z "${_seen[$x]}" && "${(L)d}" == *"${(L)query}"* ]]; then
          _seen[$x]=1; vis+=("$x")
        fi
      done
    else
      for x in "${all[@]}"; do
        d=${x#python3Packages.}
        if [[ -z "$query" || "${(L)d}" == *"${(L)query}"* ]]; then
          vis+=("$x")
        fi
      done
    fi
    n=${#vis[@]}
    (( n == 0 )) && { cur=1; top=1; } || {
      (( cur < 1 )) && cur=1
      (( cur > n )) && cur=n
      (( top < 1 )) && top=1
      (( top > n - maxrows + 1 )) && top=$(( n - maxrows + 1 ))
      (( top < 1 )) && top=1
      (( cur < top )) && top=cur
      (( cur > top + maxrows - 1 )) && top=$(( cur - maxrows + 1 ))
      (( top < 1 )) && top=1
    }

    local -i rcol=$(( listw + 9 ))
    local -i rw=$(( C - rcol ))
    (( rw < 8 )) && rw=8

    out=""
    printf -v out '%s\e[H\e[1;36m %s · 已选 %d\e[0m\e[K' "$out" "$title" ${#chosen}
    local -i first=1 last=$n
    (( n > maxrows )) && { first=$top; last=$(( top + maxrows - 1 )); }
    row=2
    local i
    for ((i = first; i <= last; i++)); do
      x=${vis[i]}; d=${x#python3Packages.}
      (( ${+chosen[$x]} )) && marked="x" || marked=" "
      if (( i == cur )); then
        printf -v out '%s\e[%d;1H\e[7m %-*s[%s]\e[0m\e[K' "$out" $row $listw "$d" "$marked"
      else
        printf -v out '%s\e[%d;1H %-*s[%s]\e[K' "$out" $row $listw "$d" "$marked"
      fi
      (( row++ ))
    done
    while (( row <= L - 3 )); do
      printf -v out '%s\e[%d;1H\e[K' "$out" $row; (( row++ ))
    done

    # 右栏：当前项的用途说明（优先 search.nixos.org 真实描述，按词换行）
    local _full _rt
    _full=${vis[cur]}
    d=${_full#python3Packages.}
    if [[ -n "$_full" ]] && { _rt=$(_mkf_desc_lookup "$_full") || _rt=$(_mkf_desc_lookup "$d"); }; then
      desc="$_rt"
    else
      desc="${_mkf_desc[$d]:-nixpkgs 包：$d}"
    fi
    local -a dlines=(); local cl=""
    local w
    for w in ${(s: :)desc}; do
      if (( ${#cl} > 0 && ${#cl} + ${#w} + 1 > rw )); then
        dlines+=("$cl"); cl="$w"
      else
        cl+="${cl:+ }$w"
      fi
    done
    (( ${#cl} > 0 )) && dlines+=("$cl")
    row=2
    local dl
    for dl in "${dlines[@]}"; do
      (( row > L - 3 )) && break
      printf -v out '%s\e[%d;%dH\e[2m%s\e[0m\e[K' "$out" $row $rcol "$dl"
      (( row++ ))
    done
    while (( row <= L - 3 )); do
      printf -v out '%s\e[%d;%dH\e[K' "$out" $row $rcol; (( row++ ))
    done

    if [[ -n "$qmode" ]]; then
      printf -v out '%s\e[%d;1H\e[2m 搜索> %s_\e[0m\e[K' "$out" $(( L - 2 )) "$query"
    elif [[ -r "$(_mkf_cache_core)" ]]; then
      printf -v out '%s\e[%d;1H\e[2m 搜索: 按 / 从 %s 全量包名过滤 (当前: %s)\e[0m\e[K' "$out" $(( L - 2 )) "$_mkf_channel" "$query"
    else
      printf -v out '%s\e[%d;1H\e[2m 搜索: 按 / 过滤（运行 mkflake --refresh-pkgs 加载 %s 全量包名）\e[0m\e[K' "$out" $(( L - 2 )) "$_mkf_channel" "$query"
    fi
    printf -v out '%s\e[%d;1H\e[2m%s\e[0m' "$out" $(( L - 1 )) "${(l:$C::─:)}"
    printf -v out '%s\e[%d;1H\e[7m ←→ 看说明 · ↑↓/jk 移动 · 空格 勾选 · / 搜索 · enter 确认 · q 跳过 \e[0m\e[K' "$out" $L
    print -rn -- $'\e[?2026h'"$out"$'\e[?2026l'

    read -k1 -s key
    if [[ -n "$qmode" ]]; then
      case "$key" in
        ($'\r'|$'\n'|$'\e') qmode="" ;;
        ($'\177'|$'\b') query="${query%?}" ;;
        (*) [[ "$key" == [[:print:]] ]] && query+="$key" ;;
      esac
      cur=1; top=1
      continue
    fi
    case "$key" in
      ($'\r'|$'\n') break ;;
      (q|Q) chosen=(); break ;;
      ($'/') qmode=1 ;;
      ($' ')
        if (( n )); then
          cn=${vis[cur]}
          if (( ${+chosen[$cn]} )); then unset "chosen[$cn]"; else chosen[$cn]=1; fi
        fi ;;
      (k)   (( cur > 1 )) && (( cur-- )) ;;
      (j)   (( cur < n )) && (( cur++ )) ;;
      (g)   cur=1 ;;
      (G)   cur=$n ;;
      ($esc)
        read -k2 -s -t 0.05 seq
        case "$seq" in
          ('[A') (( cur > 1 )) && (( cur-- )) ;;
          ('[B') (( cur < n )) && (( cur++ )) ;;
          ('[H'|'[1~') cur=1 ;;
          ('[F'|'[4~') cur=$n ;;
        esac ;;
    esac
  done

  print -n -- "$_mkf_reset"$'\e[2J\e[H'
  _mkf_tools=(${(k)chosen})
  return 0
}

# 纯 zsh TUI 选择器：结果写入全局 $_mkflake_choice

_mkflake_select() {
  emulate -L zsh
  setopt typesetsilent
  local tdir=$1
  local -a items preview
  items=(${(f)"$(command ls -1 "$tdir" 2>/dev/null)"})
  (( ${#items} )) || return 1

  local -i n=${#items} sel=1 off=0 hscroll=0
  local -i L C listw maxrows i row
  local key seq pv pfile out name
  local esc=$'\e'
  local -i pad

  typeset -g _mkf_reset=$'\e[0m\e[?25h'
  print -n $'\e[?25l\e[2J\e[H'
  trap 'print -n -- $_mkf_reset; return 130' INT TERM

  while true; do
    L=$(( ${LINES:-24} - 1 )); C=${COLUMNS:-80}
    (( L < 10 )) && L=10
    (( C < 60 )) && C=60
    
    listw=22
    local -i codew=$(( C - listw - 3 ))
    maxrows=$(( L - 3 ))

    pfile="$tdir/${items[sel]}/flake.nix"
    if [[ -r "$pfile" ]]; then
      preview=("${(@f)"$(<"$pfile")"}")
    else
      preview=("(该模板没有 flake.nix)")
    fi

    (( sel - off > maxrows )) && off=$(( sel - maxrows ))
    (( sel - off < 1 )) && off=$(( sel - 1 ))

    out=""
    printf -v out '%s\e[H\e[1;36m mkflake · 选择 Flake 模板\e[0m\e[K' "$out"
    local h_info=""
    (( hscroll > 0 )) && h_info=" [→ +$hscroll]"
    printf -v out '%s\e[1;%dH\e[2m%d 个模板%s\e[0m\e[K' "$out" $(( C > 32 ? C - 24 : 1 )) "${#items}" "$h_info"

    i=$(( off + 1 ))
    row=2
    pad=$(( listw - 2 ))
    while (( i <= n && row <= maxrows + 1 )); do
      name=${items[i]}
      if (( i == sel )); then
        printf -v out '%s\e[%d;1H\e[7m %-*s\e[0m\e[K' "$out" $row $pad "$name"
      else
        printf -v out '%s\e[%d;1H\e[2m %-*s\e[0m\e[K' "$out" $row $pad "$name"
      fi
      
      if (( row - 1 <= ${#preview} )); then
        pv=${preview[row-1]}
        if (( ${#pv} > hscroll )); then
          pv="${pv[hscroll + 1, hscroll + codew]}"
        else
          pv=""
        fi
        printf -v out '%s\e[%d;%dH%s\e[K' "$out" $row $(( listw + 1 )) "$pv"
      else
        printf -v out '%s\e[%d;%dH\e[K' "$out" $row $(( listw + 1 ))
      fi
      (( i++, row++ ))
    done
    while (( row <= maxrows + 1 )); do
      printf -v out '%s\e[%d;1H\e[K' "$out" $row
      (( row++ ))
    done

    printf -v out '%s\e[%d;1H\e[2m%s\e[0m' "$out" $(( L - 1 )) "${(l:$C::─:)}"
    printf -v out '%s\e[%d;1H\e[7m ↑↓/jk 切换 · ←→/hl 左右滚动 · enter 确认 · q 取消 \e[0m\e[K' "$out" $L
    print -rn -- $'\e[?2026h'"$out"$'\e[?2026l'

    read -k1 -s key
    case "$key" in
      ($'\r'|$'\n') break ;;
      (q|Q) print -n -- "$_mkf_reset"$'\e[2J\e[H'; return 130 ;;
      (k) (( sel > 1 )) && (( sel-- )); hscroll=0 ;;
      (j) (( sel < n )) && (( sel++ )); hscroll=0 ;;
      (h) (( hscroll > 0 )) && (( hscroll -= 4 )); (( hscroll < 0 )) && hscroll=0 ;;
      (l) (( hscroll += 4 )) ;;
      (g) sel=1; hscroll=0 ;;
      (G) sel=n; hscroll=0 ;;
      ($esc)
        read -k2 -s -t 0.05 seq
        case "$seq" in
          ('[A') (( sel > 1 )) && (( sel-- )); hscroll=0 ;;
          ('[B') (( sel < n )) && (( sel++ )); hscroll=0 ;;
          ('[C') (( hscroll += 4 )) ;;
          ('[D') (( hscroll > 0 )) && (( hscroll -= 4 )); (( hscroll < 0 )) && hscroll=0 ;;
          ('[H'|'[1~') sel=1; hscroll=0 ;;
          ('[F'|'[4~') sel=n; hscroll=0 ;;
        esac ;;
    esac
  done

  print -n -- "$_mkf_reset"$'\e[2J\e[H'
  _mkflake_choice="${items[sel]}"
  return 0
}

_mkflake() {
  local -a tmpls
  tmpls=(${(f)"$(command ls -1 /etc/nix-darwin/templates 2>/dev/null)"})
  (( CURRENT == 2 )) && _describe -t templates 'template' tmpls
  (( CURRENT == 3 )) && _files -/
}
(( $+functions[compdef] )) && compdef _mkflake mkflake
