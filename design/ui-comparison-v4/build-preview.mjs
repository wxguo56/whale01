import { readFile, writeFile } from "node:fs/promises";

const root = new URL("../../", import.meta.url);
const source = new URL("web/ui-comparison-v4/", root);
const names = ["index.html", "styles.css", "variants.css", "visuals.js", "views.js", "app.js"];
const [html, layout, variants, visuals, views, app] = await Promise.all(names.map(name => readFile(new URL(name, source), "utf8")));
const standalone = html
  .replace('<link rel="stylesheet" href="styles.css">', () => `<style>\n${layout}\n</style>`)
  .replace('<link rel="stylesheet" href="variants.css">', () => `<style>\n${variants}\n</style>`)
  .replace('<script src="visuals.js"></script>', () => `<script>\n${visuals}\n</script>`)
  .replace('<script src="views.js"></script>', () => `<script>\n${views}\n</script>`)
  .replace('<script src="app.js"></script>', () => `<script>\n${app}\n</script>`)
  .replace('href="../ui-proposal-v3/index.html"', 'href="http://127.0.0.1:8088/ui-proposal-v3/index.html"');
await writeFile(new URL("comparison.html", import.meta.url), standalone, "utf8");
console.log("Standalone comparison.html generated.");
