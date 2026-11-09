import assert from "node:assert/strict";
import http from "node:http";
import test from "node:test";
import { DeepSeekAdapter } from "../src/adapters.mjs";

test("DeepSeekAdapter assembles streamed content and split tool call arguments", async () => {
  const chunks = [
    `data: ${JSON.stringify({ choices: [{ delta: { content: "正在" } }] })}\n\n`,
    `data: ${JSON.stringify({
      choices: [
        {
          delta: {
            content: "处理",
            tool_calls: [
              {
                index: 0,
                id: "call_1",
                function: { name: "create_reminder", arguments: "{\"title\":\"取" }
              }
            ]
          }
        }
      ]
    })}\n\n`,
    `data: ${JSON.stringify({
      choices: [
        {
          delta: {
            tool_calls: [
              { index: 0, function: { arguments: "快递\",\"timezone\":\"Asia/Shanghai\"}" } }
            ]
          }
        }
      ]
    })}\n\n`,
    "data: [DONE]\n\n"
  ];

  const server = http.createServer((request, response) => {
    response.writeHead(200, { "content-type": "text/event-stream" });
    for (const chunk of chunks) response.write(chunk);
    response.end();
  });

  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  const { port } = server.address();
  const adapter = new DeepSeekAdapter({
    baseUrl: `http://127.0.0.1:${port}`,
    apiKey: "test-key",
    model: "deepseek-chat"
  });

  const deltas = [];
  const result = await adapter.chat({
    messages: [],
    tools: [{ type: "function", function: { name: "create_reminder" } }],
    onDelta: (text) => deltas.push(text)
  });
  server.close();

  assert.equal(result.content, "正在处理");
  assert.deepEqual(deltas, ["正在", "处理"]);
  assert.equal(result.toolCalls.length, 1);
  assert.equal(result.toolCalls[0].id, "call_1");
  assert.equal(result.toolCalls[0].name, "create_reminder");
  assert.deepEqual(JSON.parse(result.toolCalls[0].arguments), {
    title: "取快递",
    timezone: "Asia/Shanghai"
  });
});

test("DeepSeekAdapter accepts a non-streaming JSON response", async () => {
  const server = http.createServer((request, response) => {
    response.writeHead(200, { "content-type": "application/json" });
    response.end(
      JSON.stringify({
        choices: [
          {
            message: {
              content: "好的",
              tool_calls: [
                {
                  id: "call_json",
                  function: { name: "create_reminder", arguments: "{\"title\":\"测试\"}" }
                }
              ]
            }
          }
        ]
      })
    );
  });

  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  const { port } = server.address();
  const adapter = new DeepSeekAdapter({
    baseUrl: `http://127.0.0.1:${port}`,
    apiKey: "test-key",
    model: "deepseek-chat"
  });

  const result = await adapter.chat({ messages: [], tools: [] });
  server.close();

  assert.equal(result.content, "好的");
  assert.equal(result.toolCalls[0].name, "create_reminder");
  assert.deepEqual(JSON.parse(result.toolCalls[0].arguments), { title: "测试" });
});
