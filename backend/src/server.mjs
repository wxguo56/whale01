import { createServer } from "node:http";
import { createHash, timingSafeEqual } from "node:crypto";
import { pathToFileURL } from "node:url";
import { AgentError } from "./agent.mjs";
import { ConversationError } from "./conversation.mjs";
import { loadLocalEnv } from "./env.mjs";
import { createRuntime } from "./runtime.mjs";

loadLocalEnv();

const MAX_BODY_BYTES = 1024 * 1024;

export function createHttpServer(runtime) {
  return createServer(async (request, response) => {
    try {
      const url = new URL(request.url ?? "/", "http://localhost");
      response.setHeader("access-control-allow-origin", "*");
      response.setHeader("access-control-allow-headers", "content-type, accept, authorization");
      response.setHeader("access-control-allow-methods", "GET, POST, OPTIONS");

      if (request.method === "OPTIONS") {
        response.writeHead(204).end();
        return;
      }

      if (request.method === "GET" && url.pathname === "/healthz") {
        sendJson(response, 200, {
          status: "ok",
          modelMode: runtime.config.modelMode,
          executionMode: runtime.config.executionMode,
          requiresDeferExecution: runtime.config.executionMode !== "mock",
          adapterConfigured: runtime.config.modelMode === "deepseek" ? Boolean(runtime.config.deepseek.apiKey) : true,
          tools: runtime.registry.names().length,
          contractVersion: runtime.config.contractVersion,
          authRequired: runtime.config.authTokens.length > 0,
          caps: runtime.config.caps
        });
        return;
      }

      const identity = url.pathname.startsWith("/v1/")
        ? resolveIdentity(request, runtime.config.authTokens)
        : null;
      if (url.pathname.startsWith("/v1/") && (!identity || !identity.authorized)) {
        sendJson(response, 401, {
          error: { code: "unauthorized", message: "缺少或无效的访问令牌" }
        });
        return;
      }
      const ownerId = identity?.ownerId ?? "owner_local";

      if (request.method === "GET" && url.pathname === "/v1/capabilities") {
        sendJson(response, 200, {
          executionMode: runtime.config.executionMode,
          capabilities: runtime.agent.capabilities()
        });
        return;
      }

      if (request.method === "POST" && url.pathname === "/v1/turns") {
        const body = await readJson(request);
        const text = body.text;
        const now = body.now ?? new Date().toISOString();
        const timezone = body.timezone ?? "Asia/Shanghai";
        const autoConfirm = body.autoConfirm ?? false;
        const deferExecution = body.deferExecution ?? false;
        const conversationId = body.conversationId;
        const permissions = body.permissions ?? {};

        if (acceptsEventStream(request)) {
          response.writeHead(200, {
            "content-type": "text/event-stream; charset=utf-8",
            "cache-control": "no-cache",
            connection: "keep-alive"
          });
          let closed = false;
          response.on("close", () => {
            closed = true;
          });
          const result = await runtime.agent.start(
            { text, now, timezone, autoConfirm, deferExecution, conversationId, permissions, ownerId },
            {
              onEvent: (event) => {
                if (!closed) response.write(`event: ${event.type}\ndata: ${JSON.stringify(event)}\n\n`);
              }
            }
          );
          if (!closed) {
            response.write(`event: turn.snapshot\ndata: ${JSON.stringify(result)}\n\n`);
            response.end();
          }
          return;
        }

        const result = await runtime.agent.start({
          text,
          now,
          timezone,
          autoConfirm,
          deferExecution,
          conversationId,
          permissions,
          ownerId
        });
        sendJson(response, 200, result);
        return;
      }

      const conversationMatch = /^\/v1\/conversations\/([^/]+)$/.exec(url.pathname);
      if (conversationMatch) {
        const conversationId = decodeURIComponent(conversationMatch[1]);
        if (request.method === "GET") {
          const summary = runtime.conversations?.summary(conversationId, ownerId);
          if (!summary) {
            sendJson(response, 404, { error: { code: "unknown_conversation", message: "未知会话" } });
            return;
          }
          sendJson(response, 200, summary);
          return;
        }
        if (request.method === "DELETE") {
          runtime.conversations?.reset(conversationId, ownerId);
          sendJson(response, 200, { status: "reset", conversationId });
          return;
        }
      }

      const confirmMatch = /^\/v1\/turns\/([^/]+)\/confirm$/.exec(url.pathname);
      if (request.method === "POST" && confirmMatch) {
        const body = await readJson(request);
        const result = await runtime.agent.confirm(
          decodeURIComponent(confirmMatch[1]),
          body.operationId,
          body.confirmed === true,
          ownerId
        );
        sendJson(response, 200, result);
        return;
      }

      const toolResultsMatch = /^\/v1\/turns\/([^/]+)\/tool-results$/.exec(url.pathname);
      if (request.method === "POST" && toolResultsMatch) {
        const body = await readJson(request);
        const result = await runtime.agent.submitToolResults(
          decodeURIComponent(toolResultsMatch[1]),
          body.results ?? [],
          ownerId
        );
        sendJson(response, 200, result);
        return;
      }

      const turnMatch = /^\/v1\/turns\/([^/]+)$/.exec(url.pathname);
      if (request.method === "GET" && turnMatch) {
        sendJson(response, 200, runtime.agent.snapshot(decodeURIComponent(turnMatch[1]), ownerId));
        return;
      }

      sendJson(response, 404, { error: { code: "not_found", message: "未知路径" } });
    } catch (error) {
      if (response.headersSent) {
        if (!response.writableEnded && String(response.getHeader("content-type") ?? "").includes("text/event-stream")) {
          const event = {
            type: "turn.failed",
            payload: { code: error.code ?? "internal_error", message: error.message }
          };
          response.write(`event: turn.failed\ndata: ${JSON.stringify(event)}\n\n`);
        }
        response.end();
        return;
      }
      const status = String(error.code ?? "").startsWith("forbidden")
        ? 403
        : error instanceof AgentError || error instanceof ConversationError
          ? 400
          : 500;
      sendJson(response, status, {
        error: { code: error.code ?? "internal_error", message: error.message }
      });
    }
  });
}

export async function startServer(runtime, { port = runtime.config.port, host = "127.0.0.1" } = {}) {
  const server = createHttpServer(runtime);
  await new Promise((resolve, reject) => {
    server.once("error", reject);
    server.listen(port, host, resolve);
  });
  return server;
}

function acceptsEventStream(request) {
  return (request.headers.accept ?? "").includes("text/event-stream");
}

function resolveIdentity(request, tokens) {
  if (!tokens.length) return { authorized: true, ownerId: "owner_local" };
  const header = request.headers.authorization ?? "";
  const match = /^Bearer\s+(.+)$/i.exec(header);
  if (!match) return { authorized: false, ownerId: null };
  const candidate = match[1].trim();
  for (const token of tokens) {
    if (sameSecret(candidate, token)) {
      return { authorized: true, ownerId: ownerIdFor(token) };
    }
  }
  return { authorized: false, ownerId: null };
}

function sameSecret(candidate, expected) {
  const left = Buffer.from(candidate);
  const right = Buffer.from(expected);
  return left.length === right.length && timingSafeEqual(left, right);
}

function ownerIdFor(token) {
  return `owner_${createHash("sha256").update(token).digest("hex").slice(0, 16)}`;
}

function readJson(request) {
  return new Promise((resolve, reject) => {
    let size = 0;
    const chunks = [];
    request.on("data", (chunk) => {
      size += chunk.length;
      if (size > MAX_BODY_BYTES) {
        reject(new AgentError("请求体过大", "payload_too_large"));
        request.destroy();
        return;
      }
      chunks.push(chunk);
    });
    request.on("end", () => {
      if (!chunks.length) {
        resolve({});
        return;
      }
      try {
        resolve(JSON.parse(Buffer.concat(chunks).toString("utf8")));
      } catch {
        reject(new AgentError("请求体不是合法 JSON", "invalid_json"));
      }
    });
    request.on("error", reject);
  });
}

function sendJson(response, status, body) {
  if (response.headersSent) return;
  const payload = JSON.stringify(body);
  response.writeHead(status, {
    "content-type": "application/json; charset=utf-8",
    "content-length": Buffer.byteLength(payload)
  });
  response.end(payload);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const runtime = await createRuntime();
  const server = await startServer(runtime, { host: runtime.config.host });
  const address = server.address();
  console.log(`whale01 backend listening on http://${address.address}:${address.port}`);
  console.log(`model mode: ${runtime.config.modelMode}, contract: ${runtime.config.contractVersion}`);
}
