import { fileURLToPath } from "node:url";

export function loadLocalEnv() {
  const path = fileURLToPath(new URL("../.env", import.meta.url));
  try {
    process.loadEnvFile(path);
  } catch (error) {
    if (error.code !== "ENOENT") throw error;
  }
}
