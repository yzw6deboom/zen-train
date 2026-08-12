# 问题跟踪：GitHub Issues

本项目的缺陷、优化、新功能、需求规格和开发任务统一存放在 GitHub Issues：

`yzw6deboom/zen-train`

在仓库目录中使用 `gh` CLI 操作，仓库地址从 Git Remote 自动识别。

## 约定

- 新发现的问题或新功能先创建 Issue，再开始正式开发。
- Issue 应说明背景、目标、范围、验收条件和已知限制。
- 开发提交和 PR 应引用对应 Issue。
- 需求发生变化时，先更新 Issue，避免只在代码或聊天中保留决定。
- 外部 PR 不作为需求入口；PR 只承载已有 Issue 的代码实现和审查。

## 常用操作

- 创建：`gh issue create`
- 查看：`gh issue view <编号> --comments`
- 列出：`gh issue list`
- 评论：`gh issue comment <编号>`
- 添加标签：`gh issue edit <编号> --add-label "<标签>"`
- 移除标签：`gh issue edit <编号> --remove-label "<标签>"`
- 关闭：`gh issue close <编号> --comment "<结论>"`

当 skill 要求“发布到 issue tracker”时，创建 GitHub Issue。

当 skill 要求“读取相关 ticket”时，读取对应 Issue 的正文、标签和评论。

## 大型任务

`wayfinder` 使用一个总 Issue 作为路线图，并使用子 Issue 表示调查或实现任务：

- 总 Issue 使用 `wayfinder:map` 标签。
- 子任务使用 `wayfinder:research`、`wayfinder:prototype`、`wayfinder:grilling` 或 `wayfinder:task`。
- 优先使用 GitHub 原生子 Issue 和依赖关系。
- 如果仓库不支持原生关系，则在正文中记录 `Part of #编号` 和 `Blocked by: #编号`。
- 只有阻塞 Issue 全部关闭后，子任务才视为可开始。
