# Ferramentas de mapas

Fluxo novo (Fase 0): os mapas saem direto dos mapas Tiled do Tuxemon (CC-BY-SA 4.0, ver `docs/CREDITOS-TUXEMON.md`).

1. Obter o Tuxemon (só mapas e tilesets):
   `git clone --depth 1 --filter=blob:none --sparse https://github.com/Tuxemon/Tuxemon.git /tmp/tux && cd /tmp/tux && git sparse-checkout set mods/tuxemon/maps mods/tuxemon/gfx/tilesets`
2. Receita do mapa: `scripts/mapas/fontes/<id>.meta.json` (mapa de origem, áreas a limpar, portais, tinta de cor).
3. Gerar: `python3 scripts/mapas/tmx2jogo.py <id>` (variável `TUXEMON_DIR` muda o caminho; padrão `/tmp/tux/mods/tuxemon`).
4. Conferir: `node scripts/lint-mapas.mjs` (0 erros) e `python3 scripts/mapas/grade.py <arquivo.tmx> saida.png` (grade numerada para escolher portas e portais).

Arquivos: `tmx.py` (leitor TMX: camadas, colisão por objetos, água e saltos por propriedade do tile), `tmx2jogo.py` (gera png, -cima.png e json),
`grade.py` (folha com grade), `lint-mapas.mjs` (verificador), `lote*.{py,mjs}` e `gruta-inverter.py`/`piloto-azurana.py` (correções antigas por remendo, histórico).
