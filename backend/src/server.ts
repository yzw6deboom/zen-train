import { buildApp } from "./app.js";

// 正式服务器启用 Fastify 日志，便于观察启动信息、请求和错误。
const app = buildApp({ logger: true });
// 部署环境可以通过 PORT 指定端口；本地开发默认使用 3000。
const port = Number.parseInt(process.env.PORT ?? "3000", 10);

try {
  // 监听 0.0.0.0 后，本机和容器外部都可以访问该服务。
  await app.listen({ host: "0.0.0.0", port });
} catch (error) {
  app.log.error(error);
  // 设置退出码而不是直接抛弃日志，让 Node.js 以失败状态结束进程。
  process.exitCode = 1;
}
