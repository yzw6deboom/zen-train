import assert from "node:assert/strict";
import test from "node:test";

import { buildApp } from "../src/app.js";

test("GET /health 返回后端就绪状态", async () => {
  const app = buildApp();

  try {
    // `inject` 在进程内模拟 HTTP 请求，因此测试不需要监听真实网络端口。
    const response = await app.inject({
      method: "GET",
      url: "/health",
    });

    assert.equal(response.statusCode, 200);
    assert.deepEqual(response.json(), { status: "ok" });
  } finally {
    // 无论断言成功还是失败都关闭应用，避免测试遗留资源。
    await app.close();
  }
});
