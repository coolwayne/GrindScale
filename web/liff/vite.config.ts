import { defineConfig, loadEnv } from "vite";

export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, process.cwd(), "");
  const apiTarget =
    env.VITE_API_PROXY_TARGET ||
    process.env.GRINDSCALE_API_PROXY ||
    "http://127.0.0.1:8000";

  return {
    root: ".",
    build: {
      outDir: "dist",
      emptyOutDir: true,
    },
    server: {
      port: 5173,
      proxy: {
        "/v1": { target: apiTarget, changeOrigin: true },
        "/healthz": { target: apiTarget, changeOrigin: true },
      },
    },
    preview: {
      port: 4173,
      host: "127.0.0.1",
      allowedHosts: true,
      proxy: {
        "/v1": { target: apiTarget, changeOrigin: true },
        "/healthz": { target: apiTarget, changeOrigin: true },
      },
    },
  };
});
