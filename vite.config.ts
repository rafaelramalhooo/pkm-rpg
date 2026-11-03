import { defineConfig } from "vite";

// VITE_BASE: "/pkm-rpg/" (produção) ou "/pkm-rpg/teste/" (teste), definido na publicação.
export default defineConfig({
  base: process.env.VITE_BASE ?? "/",
  build: { outDir: "dist", sourcemap: false },
});
