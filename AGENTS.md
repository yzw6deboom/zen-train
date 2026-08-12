# ZenTrain Agent 开发指南

## 项目目标

ZenTrain 是一款离线优先的 iOS 训练记录应用。当前优先完成：

```text
进入 App → 手动创建今日计划 → 执行计划 → 完成计划 → 生成今日训练记录
```

手动训练闭环不能依赖后端、网络或 AI 才能运行。

## 开始开发前

1. 阅读根目录 `CONTEXT.md`。
2. 阅读 `docs/architecture/` 中与任务相关的设计。
3. 阅读 `docs/adr/` 中影响当前模块的架构决策。
4. 从 GitHub Issue 获取需求、验收条件和讨论记录。
5. 检查 Git 状态，保留用户已有的未提交修改。

## 模块职责

| 模块 | 职责 |
|---|---|
| `ios/TrainingApp/App` | 应用入口和组合根；集中创建、选择并注入具体依赖。 |
| `ios/TrainingApp/Features` | SwiftUI 页面、Feature Model、页面草稿、导航和用户意图。 |
| `ios/TrainingApp/Application` | 对外提供 Command、查询接口、Snapshot、业务错误和 Repository 端口。 |
| `ios/TrainingApp/Domain` | 纯 Swift 领域模型、状态转换和业务不变量。 |
| `ios/TrainingApp/Infrastructure` | SwiftData、系统时间、ID、网络和 HealthKit 等技术实现。 |
| `ios/TrainingApp/DesignSystem` | 可复用界面组件、样式令牌和预览数据。 |
| `ios/TrainingAppTests` | Domain、Application 和持久化测试。 |
| `ios/TrainingAppUITests` | 从用户视角验证关键训练链路。 |
| `backend/src/routes` | Fastify HTTP 路由和请求/响应 Schema。 |
| `backend/src/modules` | 后端业务模块；未来包含 Agent 计划编排。 |
| `backend/src/infrastructure` | 模型提供商、日志和外部服务适配器。 |
| `contracts/schemas` | iOS 与后端共同遵守的 JSON Schema。 |
| `contracts/examples` | 跨端契约示例和兼容性样本。 |
| `docs/architecture` | 当前架构与业务链路说明。 |
| `docs/adr` | 已确认的架构决策记录。 |

## 依赖规则

- SwiftUI View 不能直接读写 SwiftData。
- View 只渲染 Feature Model，并转发用户意图。
- Feature Model 只调用 Application 接口，不实现核心业务规则。
- Application 依赖 Domain 和 Repository 接口。
- Domain 不依赖 SwiftUI、SwiftData、HealthKit、网络或 Fastify。
- Infrastructure 实现端口，并负责技术模型与 Domain 模型之间的映射。
- `App` 是唯一选择和装配具体 Adapter 的位置。
- 手动操作和未来 Agent 操作必须进入相同 Command。
- Agent 输出只是候选数据；执行前必须经过 Schema 校验、业务校验和用户确认。
- 计划值与实际结果必须分离。
- 重复提交不得产生重复计划、Session 或训练结果。

## 中文文档与教学型注释

- 代码注释、README、CONTEXT、ADR、架构说明和开发指南统一使用中文。
- Swift、TypeScript 标识符和第三方 API 名称继续遵循英文生态惯例。
- 用户正在学习 Swift/iOS 和 TypeScript；新代码需要提供清晰、适量的中文注释。
- 公共类型、跨层接口、关键状态转换、并发逻辑、Schema 和不直观语法必须说明用途。
- 注释优先解释“为什么这样设计”、数据如何流动、语法承担什么角色以及容易踩什么坑。
- 不为显而易见的赋值逐行添加注释，也不能用注释掩盖难懂的代码。
- 采用新语法或缩写时，应在首次出现处说明。
- 测试名称可以遵循语言惯例使用英文标识符，但测试描述、失败信息和辅助说明使用中文。

## 开发与验证

- 功能开发尽量按已确认的公共 seam 进行 TDD。
- Domain 测试验证业务规则和状态转换。
- Application 测试通过真实接口和 In-Memory Repository 验证完整行为。
- Persistence 测试验证 SwiftData 映射、恢复和幂等。
- UI 测试只保留关键用户链路，不重复测试所有 Domain 规则。
- TypeScript 修改后运行测试、类型检查和生产构建。
- iOS 修改后运行相关测试、完整测试和目标平台构建。
- 提交前执行代码审查，并分别检查代码规范和需求符合度。
- 不提前实现当前阶段之外的功能。

## Agent skills

### Issue tracker

缺陷、优化和新功能统一记录在本仓库的 GitHub Issues；外部 PR 不作为需求入口。参见 `docs/agents/issue-tracker.md`。

### Triage labels

使用默认五角色标签：`needs-triage`、`needs-info`、`ready-for-agent`、`ready-for-human`、`wontfix`。参见 `docs/agents/triage-labels.md`。

### Domain docs

当前采用单上下文：根目录 `CONTEXT.md` 描述整个 Monorepo，架构决策位于 `docs/adr/`。参见 `docs/agents/domain.md`。
