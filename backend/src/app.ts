import Fastify, { type FastifyServerOptions } from "fastify";

import { healthRoutes } from "./routes/health.js";

export function buildApp(options: FastifyServerOptions = {}) {
  const app = Fastify(options);

  app.register(healthRoutes);

  return app;
}
