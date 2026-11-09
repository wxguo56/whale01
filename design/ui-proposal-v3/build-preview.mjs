import { readFile, writeFile } from "node:fs/promises";

const root = new URL("../../", import.meta.url);
const source = new URL("web/ui-proposal-v3/", root);
const [html, css, script] = await Promise.all([
  readFile(new URL("index.html", source), "utf8"),
  readFile(new URL("styles.css", source), "utf8"),
  readFile(new URL("app.js", source), "utf8")
]);
const standalone = html
  .replace('<link rel="stylesheet" href="styles.css">', () => `<style>\n${css}\n</style>`)
  .replace('<script src="app.js"></script>', () => `<script>\n${script}\n</script>`)
  .replace('href="../capability-summary/index.html"', 'href="http://127.0.0.1:8088/capability-summary/index.html"');
const output = new URL("preview.html", import.meta.url);
await writeFile(output, standalone, "utf8");
console.log(`Standalone design preview saved: ${output.pathname}`);
