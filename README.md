# pkm-rpg

RPG de Pokémon que roda direto no navegador (computador e celular, sem instalar nada), estilo Game Boy, para jogar com amigos.
**Uso privado e sem fins comerciais.**

## Stack
- Front-end estático (GitHub Pages), direto no navegador (sem PWA)
- Supabase (Auth, Postgres, Realtime, Storage, Edge Functions)
- Vite + TypeScript; Phaser 3 + mapas do Tiled (a partir do M1b)
- Motor de batalha: simulador do Pokémon Showdown (`@pkmn/sim`), no servidor

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

## Aviso
Pokémon e seus nomes são marcas da Nintendo, Game Freak e Creatures Inc. Este é um projeto de fãs, privado, sem afiliação nem fins lucrativos.

## Extração de dados
O fluxo **Extrair dados** (aba *Actions* do GitHub) roda `scripts/extract.js`, que usa a PokéAPI como fonte principal e o pokemondb.net como conferência (no máximo 1 requisição a cada 4 s). Rode primeiro com a faixa `1-3` para testar, depois `1-151` (Etapa A, Geração 1). O resultado vai para `data/*.json` e um relatório em `data/extraction-report.json`.
