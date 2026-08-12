import type { FastifyPluginAsync } from "fastify";

export const healthRoutes: FastifyPluginAsync = async (app) => {
  app.get(
    "/health",
    {
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
    async () => ({ status: "ok" as const }),
  );
};
