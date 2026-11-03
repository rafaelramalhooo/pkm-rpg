# pkm-rpg

RPG de Pokémon em navegador (PWA), estilo Game Boy, para jogar com amigos.
**Uso privado e sem fins comerciais.**

## Stack
- Front-end estático (GitHub Pages) + PWA
- Supabase (Auth, Postgres, Realtime, Storage, Edge Functions)
- Phaser 3 + mapas do Tiled
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

## Regras do repositório
- Nunca versionar chaves, senhas ou arquivos `.env`.
- Nunca versionar sprites, músicas ou outras artes protegidas (ficam no Supabase Storage privado).
- Dados dos Pokémon são extraídos uma vez (pokemondb.net e PokéAPI) e guardados como JSON; o jogo nunca consulta essas fontes em tempo real.

## Aviso
Pokémon e seus nomes são marcas da Nintendo, Game Freak e Creatures Inc. Este é um projeto de fãs, privado, sem afiliação nem fins lucrativos.
