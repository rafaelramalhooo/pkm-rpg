# pkm-rpg

RPG de Pokémon que roda direto no navegador (computador e celular, sem instalar nada), estilo Game Boy, para jogar com amigos.
**Uso privado e sem fins comerciais.**

## Stack
- Front-end estático (GitHub Pages), direto no navegador (sem PWA)
- Supabase (Auth, Postgres, Realtime, Storage, Edge Functions)
- Vite + TypeScript; Phaser 3 desenhando mapas de tiles andáveis (estilo Game Boy); passos são grátis e PA é gasto em ações (procurar Pokémon etc.)
- Regras (andar, encontros, batalha, captura) em funções PL/pgSQL no Supabase; o cliente só mostra o resultado

## Estrutura
| Pasta | Conteúdo |
|---|---|
| `src/` | Código do jogo (cliente) |
| `public/` | Arquivos estáticos (sem arte da Nintendo) |
| `data/` | JSONs extraídos (Pokémon, golpes, tipos, naturezas...) |
| `data/raw/` | Cache bruto da extração (não versionado) |
| `scripts/` | Scripts de extração e manutenção |
| `supabase/migrations/` | Migrações do banco |
| `supabase/functions/` | Edge Functions (regras do jogo) |
| `docs/` | Documentação |

## Desenvolvimento local
1. `npm install`
2. Copie `.env.example` para `.env.local` e preencha com a URL e a chave **publishable** do projeto de **teste** (nunca a chave secreta).
3. `npm run dev`

A publicação é automática (GitHub Actions): produção na raiz do site e teste em `/teste/`.

## Regras do repositório
- Nunca versionar chaves, senhas ou arquivos `.env`.
- Nunca versionar sprites, músicas ou outras artes protegidas (ficam no Supabase Storage privado).
- Dados dos Pokémon são extraídos uma vez (pokemondb.net e PokéAPI) e guardados como JSON; o jogo nunca consulta essas fontes em tempo real.

## Créditos de arte
- Mapas e sprites de treinadores: projeto [Tuxemon](https://github.com/Tuxemon/Tuxemon) (arte e mapas sob CC-BY-SA 4.0, CC-BY e domínio público, conforme o autor de cada arquivo; lista completa em `docs/CREDITOS-TUXEMON.md`). Os mapas `public/assets/mapas/*.png` são recomposições feitas por script a partir dessa arte e, por isso, **continuam sob CC-BY-SA 4.0** (compartilhar igual, com crédito).
- Tiles do mapa hexagonal antigo (ideia guardada para o mapa-múndi): [Hexagon Pack](https://www.kenney.nl/assets/hexagon-pack), de Kenney (CC0), em `public/assets/hex/`.
- Sprites dos Pokémon: não ficam no repositório (bucket privado do Supabase, enviados pelo Mestre).

## Aviso
Pokémon e seus nomes são marcas da Nintendo, Game Freak e Creatures Inc. Este é um projeto de fãs, privado, sem afiliação nem fins lucrativos.

## Extração de dados
O fluxo **Extrair dados** (aba *Actions* do GitHub) roda `scripts/extract.js`, que usa a PokéAPI como fonte principal e o pokemondb.net como conferência (no máximo 1 requisição a cada 4 s). Rode primeiro com a faixa `1-3` para testar, depois `1-151` (Etapa A, Geração 1). O resultado vai para `data/*.json` e um relatório em `data/extraction-report.json`.
