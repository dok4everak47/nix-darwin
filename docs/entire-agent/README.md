# Entire Code review Agent —— 怎么用

`dok4everak47/nix-darwin` 这个仓库上挂了一个 Entire 的预设 Agent（`Code review`）。
本目录记录它的触发规则、完整使用流程和花销情况，方便以后回查「怎么走」「为什么没跑」「什么时候会花钱」。

| 文件 | 作用 |
| - | - |
| `README.md` | 本文件：完整六步流程、两张截图怎么读、不触发时怎么排查 |
| `code-review-trigger.png` | Agent 的 setup 面板截图（模型 / 超时 / 触发条件 / 绑定仓库） |
| `billing-credit.png` | Account → Billing 截图（余额 / 用量拆分 / 有没有绑卡） |
| [config-snapshot.md](config-snapshot.md) | 从页面上逐项抄下来的配置值、官方限制表、实测单价 |

截图时间 **2026-10-30**。数字会变，需要精确值时以整个 Entire 网页为准。

---

## 一、完整流程（六步）

下面这套是 2026-10-30 实跑验证过的路径（`Trail #2`）。核心前提一句话：
**改动必须走分支 + Trail，review 才会跑；直接推 `main` 什么都不会发生。**

### 第 1 步：开分支、改、提交

```bash
cd /etc/nix-darwin
git checkout -b fix-something        # 不要直接在 main 上改，main 上没有 Trail 也就不会审
# ...改代码...
git commit -am "fix(shell): ..."
```

此时**分支还在本地**，没有推。`trail create` 会替你推，所以不用先 `git push`。

### 第 2 步：建 Trail

```bash
entire trail create --title "fix shell prompt" --type bug
```

`--type` 可选 `bug` / `feature` / `task`，可加 `--body`、`--priority`。
它会做三件事：把当前分支推到 `origin`、建一个新 Trail、把分支挂成该 Trail 的 change。

预期输出（照抄实测）：

```
 * [new branch]      fix-something -> fix-something
Published branch fix-something to origin
Created trail #3 (01M65...); linking branch
Trail #3: fix shell prompt
  URL:     https://entire.com/gh/dok4everak47/-/trails/3
  Changes:
    CHANGE        BRANCH        STATUS  URL
    nix-darwin/3  fix-something  open    .../trails/3/changes/3
```

记下打印出来的 **trail 号**（`#3` 这种）和 URL，后面几步都要用。

> 只在网页上做也可以：Trails → `New trail` → 进 Trail → `⋯` → `Add change` → base `main` / head 你的分支。
> 差别是网页版要求分支**先自己推到 GitHub**，CLI 版会替你推。

### 第 3 步：点 `Ready for review`（唯一必须人工的一步）

打开第 2 步打印的 URL，在 change 面板上点 **`Ready for review`**。

为什么必须点：Agent 的触发条件是 `On every push` **且** `Ready for review`，而这个仓库有 approvals gate，
所以不会「一建 PR 就自动跑」。页面原话：

> In repositories without an approvals gate, every open change counts as ready for review.

也就是说：**光 push 不花钱，点了 ready 才会跑。** 这一步 CLI 没有对应参数
（`entire trail` 全部子命令里都没有 ready/draft 开关），只能点。

### 第 4 步：watch 看结果

```bash
entire trail watch            # 在带该 Trail 的分支上，直接跟事件流
entire trail watch --once     # 只连一次，看到当前状态就退出
```

实测能看到的事件顺序（约 60 秒走完）：

```
gate.updated   up_to_date / findings → passed
gate.updated   checks → pending → failed（见「已知噪音」）
agent.updated  status: queued
agent.updated  status: running
agent.updated  status: succeeded
review.started review_id: ...
```

网页上等价的位置：Trail → change 面板，`Code review` 卡片显示 `Pass` / 分数，
点 `Open Code review` 看 rationale 和 findings 明细。

其他查询命令：

```bash
entire trail show 3                                   # 看某个 Trail 的状态
entire trail finding --repo gh/dok4everak47/nix-darwin  # 列 findings
entire trail list --project gh/dok4everak47           # 列所有 Trail
```

**改了要再审怎么办**：继续在同一个分支上 commit + push，会**自动再跑一次**，不用重建 Trail、不用再点 ready。

### 第 5 步：合并

```bash
git checkout main
git pull --ff-only
git merge --ff-only fix-something
git push origin main
git push gitea main
```

**不要用 Entire 的 `Merge` 按钮**：这仓库 Gates 要求 1 个人批准、且「不能批准自己的 trail」，
所以单人开发时它永远是 `Merge blocked`。Entire 只是 review 工具，合并仍走 git。
合并后 Entire 会自动把 change 标成 `merged`（2026-10-30 实测）。

### 第 6 步：关 Trail

```bash
# 在带该 Trail 的分支上，可以省略 selector
entire trail update --status closed

# 切回 main 之后必须给 trail 号和 --project，否则会报：
#   branch "main" has no discoverable project trail; pass a project trail ID with --project
entire trail update 3 --project gh/dok4everak47 --status closed
```

也可以网页上点 change 面板的 `Close`。

### 一条命令版（第 1–2 步 + 第 5–6 步）

```bash
cd /etc/nix-darwin
git checkout -b fix-something
# ...改...
git commit -am "fix(shell): ..."
entire trail create --title "fix shell prompt" --type bug     # → 记下 URL 和 trail 号

#  ← 此处去网页点一次 Ready for review（唯一人工步骤）

entire trail watch                                            # 等 verdict
git checkout main && git pull --ff-only && git merge --ff-only fix-something
git push origin main && git push gitea main
entire trail update <trail号> --project gh/dok4everak47 --status closed
```

### 想不推代码空跑一次

给 Trail 挂个已有分支，然后点 Agent 卡片上的 `Run now`。适合先看看当前模型在你代码上的判定质量。

---

## 二、两张截图分别什么时候看

### `code-review-trigger.png` —— 回答「它现在到底在什么条件下会自动跑」

![Code review Agent setup 面板](code-review-trigger.png)

图里这一段 `AGENT SETUP` 就是自动触发的全部定义：

| 字段 | 当前值 | 含义 |
| - | - | - |
| Harness / Model / Reasoning | `Codex` / `GPT-6.1 Sol` / `High` | 跑起来用哪个模型、多贵的档位 |
| Time limit | `20 min` | 单次运行硬超时，等于间接封顶单次花销 |
| When to run | `On every push` | 触发时机 |
| Which changes | `Ready for review` | 只有处于这个状态的变化才算数 |
| Repositories | `dok4everak47/nix-darwin` | 只在这个仓库生效 |
| Active | 开 | 总开关 |

什么时候看它：

- 推了代码却**没看到 review** —— 先对一遍图里的 Repositories 和 Active
- 想确认**改动的模型或超时**有没有被上游调整（这是 preset Agent，模型由 Entire 维护，会变）
- 想确认**只在 nix-darwin 上生效**、没有误挂到别的仓库

### `billing-credit.png` —— 回答「还剩多少、花在哪、会不会自己扣钱」

![Account Billing 余额与用量](billing-credit.png)

三个数字最重要：`Credit balance`（还能花多少）、`expires`（什么时候作废）、`Payment method`（`No card on file` 就意味着不可能自动扣款）。
下面 `Usage` 那张表按 project / repository / agent 拆开，能看出钱是哪个仓库的 review 花的。

什么时候看它：

- 想估「还能跑多少次」——拿余额除以单次花费（小 diff 约 $0.03，8 行配置改约 $0.09，见 [config-snapshot.md](config-snapshot.md)）
- 发现用量涨得不对劲——按 repository 拆行，定位是哪个仓库在跑
- 报销/对账，或想确认没被偷偷绑卡

---

## 三、没跑？按这个顺序排查

1. **仓库的 Trails 开关**：Settings → General → Workflows → `Trails` 必须是开的。关着的话 Agent 根本不会被选中（当初就是先开了它才挂上 Agent 的）。
2. **change 是否真的 Ready for review**：停在 open / draft 状态不触发（第 3 步没做）。
3. **分支还在不在**：把 head 分支删了，change 会变成 `Latest commit is unavailable`，也就不再有可审的内容（2026-10-30 那次 Trail #1 就是这样降级的）。
4. **Agent 是否 Active**：Agents 页面或该 Agent 的 `Code review actions` 菜单里能看/切。
5. **额度是否见底**：余额到 $0，该账号下所有 Agent 停跑（`new runs do not start`）。

### 已知噪音（不影响 review）

- Gates 的 `Checks` 常年 `failed`：它要求「所有 GitHub required checks 通过」，而仓库的 `sync` check 会失败、`Sourcery review` 一直在跑。这只是让 `Merge` 按钮红着，跟 Agent review 无关。
- `Merge blocked` 是常态，见第 5 步。

## 四、花销怎么控

- **没有硬性花销上限**。Entire 不提供「单次/每日/每月限额」这类设置，`Automatic top-up monthly maximum` 写的就是 `None`。实际起作用的约束只有：预付余额、单次 20 分钟超时、允许小幅超出 $0、自动充值默认关。
- **刹车**：把 Agent 的 `Active` 关掉即停花钱，随时能开回来；或者不点 `Ready for review`。
- 不会自动扣钱：当前 `No card on file` + 自动充值关闭，余额花完就是停跑，不会产生账单。
- 一次完整流程（25 行文档 diff）实测 **$0.09**，从点 ready 到出 verdict 约 **60 秒**。

细节数值和官方限制表见 [config-snapshot.md](config-snapshot.md)。

## 五、重新截图

页面改版后旧图会失真。重截步骤：

1. `entire.com/gh/dok4everak47/-/agents/<agent-id>` → 点 `Show Setup` 展开 `AGENT SETUP` → 截这一段，存 `code-review-trigger.png`
2. `entire.com/account/billing` → 截余额 + 用量区，存 `billing-credit.png`
3. 顺手更新 [config-snapshot.md](config-snapshot.md) 里的数值和本文件顶部的截图日期
