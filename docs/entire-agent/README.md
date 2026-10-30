# Entire Code review Agent —— 触发规则与花销约束

> 记录时间：2026-10-30 10:55 (UTC+8)
> 账号：`dok4ever` / CLI handle `dok4everak47`（login server `sg.auth.entire.io`）
> 项目：`dok4everak47`（Personal，GitHub 镜像项目）
> Agent：`Code review`（preset，Entire 托管维护，ID `01M65B1A3NGM4V8K7RVB1EKVGA`）

这份文档是为了以后回查：**这个 Agent 什么时候会自动跑、跑一次花多少、有没有硬性花销上限。
截图 + 下面的文字是从 Entire 网页上逐项抄下来的，两者应当一致；若上游改版，以截图为准。

## 1. 自动触发规则

![Code review Agent 的 setup 面板：模型、推理强度、超时、触发条件、绑定仓库](code-review-trigger.png)

| 项 | 值 |
| - | - |
| Harness | `Codex` |
| Model | `GPT-6.1 Sol` |
| Reasoning effort | `High` |
| Time limit | `20 min`（单次运行硬超时，等于间接封顶单次 token 量） |
| When to run | `On every push` |
| Which changes | `Ready for review` |
| Repositories | `dok4everak47/nix-darwin`（仅此一个） |
| Active | 开 |

触发语义（照抄页面说明）：

> Runs on every push once a change is ready for review, and when it's marked ready.
> In repositories without an approvals gate, every open change counts as ready for review.

也就是说，光 push 不花钱；必须是挂在 **Trail** 上、且该 change 处于 **Ready for review** 状态的那次 push 才会触发。
`nix-darwin` 有 approvals gate，所以只有显式点过 Ready for review 之后才会跑。

前置条件：仓库的 **Settings → General → Workflows → Trails** 必须是开的，否则 Agent 不会被选中执行。
`nix-darwin` 的 Trails 于 2026-10-30 打开。

## 2. 花销：没有任何硬性上限

![Account → Billing：试用额度余额与按仓库的用量拆分](billing-credit.png)

**Entire 目前不提供「单次/每日/每月花销上限」这类设置。** 官方 Billing 文档的 Defaults and Limits 里只有这些：

| Setting | Value |
| - | - |
| Free trial | $100 credit, once per billing account |
| Trial credit expiration | 90 days after issuance |
| Minimum credit purchase | $10 |
| Default credit purchase | $25 |
| Purchased credit expiration | 365 days after purchase |
| Automatic top-up | Off by default |
| Default top-up threshold | $10 |
| Default top-up target | $50 |
| Automatic top-up monthly maximum | **None** |

所以实际起作用的约束只有四条：

1. **预付余额本身**就是天花板：`Credit balance` 归零后该计费账号下所有 Agent 停止，`new runs do not start`。
2. **允许小幅超出**：官方说明「usage takes a few minutes to record, and model calls in progress are allowed to finish. A small amount of usage can therefore run past $0」。
3. **单次运行 20 分钟超时**：这个 Agent 唯一的单次成本刹车。
4. **关掉自动充值 + 无卡**：`Automatic top-up` 默认关闭，当前 `No card on file`，所以不存在自动扣款。真要到 0，Agent 直接停，不会产生账单。

### 本账号当前状态（2026-10-30）

| 项 | 值 |
| - | - |
| Credit balance | `$99.87` USD |
| 试用额度消耗 | `$0.13 of $100 used` |
| 过期 | `expires Jan 28, 2027`（发放后 90 天，不结转） |
| Payment method | `No card on file` |

### 实测单价（用来估算还能跑多少次）

| 场景 | 花费 |
| - | - |
| 1 行 README 的玩具 diff | $0.03 |
| 8 行 nix 配置 diff（真实的 `79af047`） | $0.09 |

模型计价是 GPT-6.1 Sol：$2/M 输入、$10/M 输出（见 `docs.entire.com/billing`）。
按这个量级，$99.87 大约还能跑 300+ 次「小改」规模的 review。

## 3. 怎么临时刹车

- 关 Agent：`dok4everak47` → Agents → Code review → 右上 `Code review actions`，或该页的 `Active` 开关。关掉后不触发、不产生费用，可随时开回。
- 不想跑就别点 change 的 `Ready for review`：没到那个状态不会触发。
- 查账：Account → Billing → Usage，按 project / repository / agent 拆分。

## 4. 维护提示

- 这是 preset Agent，模型和 instructions 由 Entire 维护（页面上写着 `Entire maintains this agent's model and instructions`），上游可能随时调模型或改行为。
- 本机如果想用 CLI 侧能力（推整个 Entire 原生仓库、采集本地 session），需要 `entire` CLI，已在 `modules/system/homebrew.nix` 里声明（cask `entire`，tap `entireio/tap`）。
- 重新截图的步骤：打开 Agent 页面 → `Show Setup` 展开 → 截上表那段；Billing 页面另截一张。截图生成于 2026-10-30。
