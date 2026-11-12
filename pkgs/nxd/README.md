# nxd — nix-darwin ASCII TUI

`/etc/nix-darwin` 的控制台入口。零外部依赖（只用 std + `stty` + ANSI），
单文件二进制，构建完全离线。

启动时 logo 与菜单同屏：动画只逐字揭示 logo，菜单一开始就在，动画结束后 logo 常驻在菜单上方。

## 键盘

| 场景 | 键 |
|---|---|
| 菜单 | `↑/↓` 或 `j/k` 移动，`Enter` 执行，`q` 退出 |
| 文件列表 | 输入即过滤，`Enter` 用 `$EDITOR` 打开，`Esc` 返回 |
| 文本/日志 | `↑/↓` 滚动，`PgUp/PgDn` 翻页，`q` 返回 |
| 输入框 | `Enter` 确认，`Esc` 取消 |
| 安装屏 | 输入即搜（可含空格），`Tab` 多选，`↓`（到结果末尾）进已选列表，`→`/`←` 切 nix/brew，`Enter` 写入 |
| 已选列表 | `↑/↓` 选择，`Tab`/`Backspace` 移除，`↑`（到顶部）/`Esc` 回结果列表 |

输入框和过滤框支持 UTF-8（中文 commit message 可以直接打）；安装屏里 `Space`
就是普通空格；多选改用 `Tab`，nix/brew 切换用 `Ctrl-B`。

## 参数

- `-q` / `--no-anim`：跳过启动动画（也认 `NXD_NO_ANIM=1`）
- `--dump=<view>`：把一帧渲染到 stdout，用于自检
  （`menu` / `browse` / `files` / `text` / `input` / `confirm` / `log`）
- `--selftest`：跑内置断言（宽度、过滤、插入、帧尺寸）
- `--search=<q>`：命令行跑一次 nix-search 并打印解析结果（调试用）
- `--keys`：按键诊断，逐字节显示你按下的键（排查终端吞键 / 改编码）

## 安装子菜单（不再依赖 fzf / nxd-install）

菜单第 7 项打开内置安装屏：

- **nix**：输入即搜（300ms 防抖 + 后台线程跑 `nix-search --channel=26.05`），
  `Tab` 加入购物车，`Enter` 把所有选中项写进 `modules/system/packages.nix`
  的 systemPackages 列表，然后问你是否立即 rebuild。
- **brew**（`Tab` 切换）：输入名字 → `brew info --cask` 判断 formula/cask →
  `brew install` → 自动追加声明到 `modules/system/homebrew.nix` 对应列表。
- 写入用纯文本行插入，已存在的包会跳过，不会重复声明。

## 设计约束

1. **零依赖**：nix 构建环境访问不到 crates.io，带依赖就要 vendor 几十 MB；
   这里只依赖 `std` + 系统 `stty`，`nix build` 不需要网络。
2. **纯 ASCII 骨架**：边框、标记、动画帧全部是 7-bit 字符；中文文案按 2 列宽
   计算，保证不同终端下对齐。
3. **外部命令必须让出终端**：`sudo darwin-rebuild`、`$EDITOR`、`less` 都先
   `Term::suspend()`（退出备用屏 + 恢复行规程），跑完再 `resume()`。

## 目录

- `src/term.rs`：raw 模式、尺寸、按键解析、整帧绘制
- `src/ui.rs`：纯函数渲染（宽度计算 + 各屏布局）
- `src/app.rs`：状态机 + git / rebuild / rollback / commit 等动作
- `src/install.rs`：nix-search 解析、packages.nix / homebrew.nix 追加
- `src/main.rs`：参数、主循环、`--dump` / `--selftest`
