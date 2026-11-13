export async function readTextBounded(response, maxBytes = 2 * 1024 * 1024) {
  const declared = Number(response.headers?.get("content-length"));
  if (declared > maxBytes) throw new Error("Content exceeds download budget");
  if (!response.body?.getReader) throw new Error("Streaming response is required");
  const reader = response.body.getReader();
  const decoder = new TextDecoder();
  let bytes = 0, text = "";
  try {
    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      bytes += value.byteLength;
      if (bytes > maxBytes) throw new Error("Content exceeds download budget");
      text += decoder.decode(value, { stream: true });
    }
    return text + decoder.decode();
  } finally {
    await reader.cancel().catch(() => {});
    reader.releaseLock();
  }
}
