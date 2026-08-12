# 跨端契约

此目录是未来 Agent 候选命令的跨端数据边界，iOS 和后端都必须遵守这里定义的结构。

阶段 A 只建立 `schemas/` 和 `examples/` 目录。创建计划 DTO、JSON Schema 和示例 Payload 属于阶段 E；它们应在 Domain 与 Application Command 的结构实现并稳定后再写入，避免契约过早固化。
