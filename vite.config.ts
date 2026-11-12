import { defineConfig, type Plugin } from "vite";

// VITE_BASE: "/pkm-rpg/" (produção) ou "/pkm-rpg/teste/" (teste), definido na publicação.
const BUILD = String(Date.now());

// grava version.json ao lado do site: o jogo consulta esse arquivo para avisar "nova versão disponível"
const arquivoVersao = (): Plugin => ({
  name: "versao-do-site",
  generateBundle() {
    this.emitFile({ type: "asset", fileName: "version.json", source: JSON.stringify({ build: BUILD }) });
  },
});

export default defineConfig({
  define: { __BUILD__: JSON.stringify(BUILD) },
  base: process.env.VITE_BASE ?? "/",
  plugins: [arquivoVersao()],
  build: { outDir: "dist", sourcemap: false, chunkSizeWarningLimit: 1600 },
});
