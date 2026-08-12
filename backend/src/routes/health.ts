import type { FastifyPluginAsync } from "fastify";

/** 注册后端健康检查路由。 */
export const healthRoutes: FastifyPluginAsync = async (app) => {
  app.get(
    "/health",
    {
      // 响应 Schema 同时负责运行时序列化约束，并为未来生成 OpenAPI 提供依据。
      schema: {
        response: {
          200: {
            type: "object",
            additionalProperties: false,
            required: ["status"],
            properties: {
              status: { type: "string", const: "ok" },
            },
          },
        },
      },
    },
    // `as const` 将 status 保留为字面量类型 "ok"，避免被推断成任意字符串。
    async () => ({ status: "ok" as const }),
  );
};
