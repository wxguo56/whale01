// Serve the sideload IPA over the LAN so AltStore/SideStore can pull it.
// Usage: node tools/serve-ipa.mjs [directory] [port]
// Defaults: directory=release, port=8089
import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const root = path.resolve(repoRoot, process.argv[2] || "release");
const port = Number(process.argv[3] || process.env.IPA_PORT || 8089);

const server = http.createServer((req, res) => {
  const urlPath = decodeURIComponent((req.url || "/").split("?")[0]);
  const target = path.resolve(root, "." + urlPath);
  const relative = path.relative(root, target);
  if (relative.startsWith("..") || path.isAbsolute(relative)) {
    res.writeHead(403);
    res.end("forbidden");
    return;
  }
  fs.stat(target, (err, stat) => {
    if (err || !stat.isFile()) {
      res.writeHead(404);
      res.end("not found");
      return;
    }
    res.writeHead(200, {
      "Content-Type": "application/octet-stream",
      "Content-Length": stat.size
    });
    fs.createReadStream(target).pipe(res);
  });
});

server.listen(port, "0.0.0.0", () => {
  console.log(`serving ${root} on http://0.0.0.0:${port}`);
});
