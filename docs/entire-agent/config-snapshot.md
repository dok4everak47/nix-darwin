# 配置与花销快照（2026-10-30）

从 Entire 网页逐项抄下来的值，用来跟截图对照。**这是快照，不是配置源** —— 真正的配置在 Entire 账号里（仓库里的这份文件只是记录）。

- 账号：`dok4ever`，CLI handle `dok4everak47`（login server `sg.auth.entire.io`）
- 项目：`dok4everak47`（Personal，GitHub 镜像项目）
- Agent：预设 `Code review`，Entire 托管维护，ID `01M65B1A3NGM4V8K7RVB1EKVGA`

截图见 [README.md](README.md)（`code-review-trigger.png` / `billing-credit.png`）。

## Agent 配置

| 项 | 值 |
| - | - |
| Harness | `Codex` |
| Model | `GPT-6.1 Sol` |
| Reasoning effort | `High` |
| Time limit | `20 min` |
| When to run | `On every push` |
| Which changes | `Ready for review` |
| Repositories | `dok4everak47/nix-darwin`（仅此一个） |
| Active | 开 |
| 创建 | `dok4ever`，2026-10-30 |

预设 Agent 的模型和 instructions 由 Entire 维护（页面标注 `Entire maintains this agent's model and instructions`），上游可能随时调整。

## 账号花销状态

| 项 | 值 |
| - | - |
| Credit balance | `$99.87` USD |
| 试用额度消耗 | `$0.13 of $100 used` |
| 过期 | `expires Jan 28, 2027`（发放后 90 天，不结转） |
| Payment method | `No card on file` |
| 本月已花 | `$0.12`（其中 `dok4everak47/nix-darwin` $0.09，已删的测试项目 $0.03） |

## 官方限制（docs.entire.com/billing）

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

**没有任何按次/按日/按月的花销上限设置。** 官方另外说明两点：

- 余额到 $0 后该计费账号下所有 Agent 停跑，`new runs do not start`。
- 用量入账有几分钟延迟，进行中的模型调用会跑完，所以可能小幅超过 $0，超出部分记在月度用量账单或下一次充值里。

## 实测单价

| 场景 | 花费 |
| - | - |
| 1 行 README 的玩具 diff | $0.03 |
| 8 行 nix 配置 diff（commit `79af047`） | $0.09 |

计价本身是 GPT-6.1 Sol：$2/M 输入、$10/M 输出。按这个量级，$99.87 大约还能跑 300+ 次小改规模的 review。

## 相关记录

- Trail #1 `Review 79af047`：判定 `Pass`、无 findings，一次真实 review 的样本；为了造 diff 用的两个脚手架分支（`review-base` / `review-79af047`）已删除，所以该 Trail 的 diff 已不可见，但运行记录仍在 Agent 的 Runs 里（`Y91ENC8D`）。
- 本机 CLI：`entire` 0.12.2，声明在 `modules/system/homebrew.nix`（cask `entire`，tap `entireio/tap`）。
