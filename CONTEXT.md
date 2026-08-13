# 项目上下文

## 当前目标

按依赖顺序开发第一条手动训练闭环。阶段 B 已建立纯 Swift Domain、Application Command、查询 Snapshot、内存 Repository，以及从 `TrainingApplication` 公共接口运行的集成测试。

当前阶段 C 已建立 SwiftData Schema V1、Entity/Domain Mapper 与 `SwiftDataTrainingRepository`。正式 App 的组合根装配 SwiftData Adapter；测试继续使用 In-Memory Adapter 或内存 SwiftData Container。Application、Feature 与未来 Agent 使用的公共接口保持不变。

## 架构边界

- SwiftUI View 只能依赖 Feature Model，不能直接读写 SwiftData。
- Feature Model 调用 Application 接口，不持有核心业务规则。
- Application Command 通过 Repository 端口协调纯 Swift Domain 类型。
- SwiftData Entity 及其映射逻辑只能存在于 Infrastructure。
- `App` 目录是组合根，也是唯一可以选择和装配具体 Adapter 的位置。
- 手动操作与未来的 Agent 候选必须进入同一组 Command。
- Agent 候选执行前必须经过 Schema 校验、业务校验和用户确认。
- 完整手动训练闭环必须在后端、网络或 AI 不可用时仍然正常运行。

## 阶段边界

- 阶段 B：Domain、Application 和内存 Repository。
- 阶段 C：SwiftData Schema V1 与持久化 Adapter。
- 阶段 D：用四个 SwiftUI Feature 实现已经冻结的七页面流程。
- 阶段 E：稳定 Agent Command DTO、JSON Schema 和示例数据。

不要为了填满空目录而提前实现后续阶段。

## 开发者约定

- 代码标识符、接口字段和第三方 API 名称遵循 Swift、TypeScript 及相关生态的英文惯例。
- 代码注释、README、架构说明和开发指南等面向人的内容统一使用中文。
- 面向 Swift/iOS 与 TypeScript 新手编写注释，优先解释设计意图、关键语法、数据流、架构边界和容易误用的行为。
- 不为显而易见的赋值或语法逐行添加无价值注释；注释应帮助读者理解“为什么”，而不只是重复“做了什么”。
