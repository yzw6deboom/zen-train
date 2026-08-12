# ZenTrain

ZenTrain 是一款离线优先的 iOS 训练记录应用。这个 Monorepo 将 iOS 客户端、薄后端和未来的跨端契约放在同一个代码库中统一管理版本。

## 阶段 A 状态

- `ios/`：iOS 17 SwiftUI 应用，包含 App Target、单元测试 Target、UI 测试 Target 和组合根（Composition Root）。
- `backend/`：TypeScript + Fastify 薄后端，当前提供经过测试的 `GET /health` 健康检查接口。
- `contracts/`：为后续 Agent 接入预留 JSON Schema 和跨端示例的存放位置。
- `docs/`：保存与代码实现直接相关的架构说明和架构决策记录（ADR）。

阶段 A 只建立可继续开发的工程骨架。领域业务、SwiftData 持久化和手动训练界面分别留到阶段 B、C、D 实现。

## 模块说明

| 模块 | 用途 |
|---|---|
| `ios/TrainingApp/App` | 应用启动入口和依赖装配。具体技术实现只能从这里注入业务功能。 |
| `ios/TrainingApp/Features` | 按用户能力组织 SwiftUI 页面和 Feature Model。 |
| `ios/TrainingApp/Application` | 对界面和未来 Agent 暴露业务命令、查询接口和快照。 |
| `ios/TrainingApp/Domain` | 保存不依赖 UI、数据库或网络的纯 Swift 业务模型与规则。 |
| `ios/TrainingApp/Infrastructure` | 实现 SwiftData、系统能力、网络和 HealthKit 等外部技术适配器。 |
| `ios/TrainingApp/DesignSystem` | 保存页面复用的组件、样式令牌和预览数据。 |
| `ios/TrainingAppTests` | Domain、Application 和持久化测试。 |
| `ios/TrainingAppUITests` | 从用户视角验证关键操作链路的 UI 冒烟测试。 |
| `backend` | 保护 AI 密钥并承载未来 Agent 编排；不能成为手动训练闭环的运行前提。 |
| `contracts` | 保存 iOS 与后端共同遵守的 JSON Schema 和示例数据。 |

更详细的依赖规则见 [`CONTEXT.md`](./CONTEXT.md)。

## 运行 iOS 应用

1. 安装支持 iOS 17 或更高版本的完整 Xcode。
2. 打开 `ios/TrainingApp.xcodeproj`。
3. 选择 `TrainingApp` Scheme 和一个 iPhone 模拟器。
4. 执行 Build；需要验证时执行 Test。

## 运行后端

需要 Node.js 20 或更高版本。

```sh
cd backend
npm ci
npm test
npm run dev
```

启动成功后，可以通过 `http://localhost:3000/health` 访问健康检查接口。
