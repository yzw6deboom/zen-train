import Fastify, { type FastifyServerOptions } from "fastify";

import { healthRoutes } from "./routes/health.js";

/**
 * 创建并配置 Fastify 应用，但不在这里监听网络端口。
 *
 * 将“构建应用”和“启动服务器”分开后，测试可以通过 `inject` 直接调用路由，
 * 不需要占用真实端口；正式启动入口则可以复用完全相同的应用配置。
 */
export function buildApp(options: FastifyServerOptions = {}) {
  const app = Fastify(options);

  // 路由以插件形式注册，后续模块可以继续使用相同方式接入。
  app.register(healthRoutes);

  return app;
}
