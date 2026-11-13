# 2026-11-13 新增 session-log 规则

## 目标

用户要求“这个项目需要写 session-log”。理解为：给仓库定一条规则，让每个改动仓库的 agent session 都留下一份日志，而不是给应用加运行时日志。

## 改动

- 规则：新增 `.agents/skills/session-log/SKILL.md`，说明何时写、写在哪、写什么。
- 日志目录：新增 `.agents/session-log/`，包含 `README.md`（索引）、`TEMPLATE.md`（模板）、一份 1.10.0 之前工作的补记和本日志。
- 入口：`AGENTS.md`（`CLAUDE.md` 是它的软链接）写入规则并在 Skills 表加一行；`code-rules` 的目录说明和提交前检查加上 session-log。

## 分支与 PR

- 分支：`docs/session-log`
- PR：[#56](https://github.com/HeadmasterEggy/MenuRunner/pull/56)，已合并（在 #57 之后合入）

## 决策

- 日志放在 `.agents/session-log/`，和 agent 的 skill 放在一起（按用户要求，最初放在 `docs/session-logs/`）。
- 一个 session 一份文件，文件名 `YYYY-MM-DD-<topic>.md`，和分支描述对应；同一个分支后续继续做时更新原文件，不新建。
- 日志用中文写，代码标识符、路径、命令保持原样。
- 日志和改动在同一个 PR 里提交，这样合并后改动和原因在一起。
- 规则做成 `.agents/skills/` 下的 skill，与 `code-rules` 一致，`.claude/skills` 软链接会自动加载。

## 验证

- 只改了 Markdown，不涉及 Swift，无需编译。
- 行数检查和注释检查通过。

## 后续

- 无
