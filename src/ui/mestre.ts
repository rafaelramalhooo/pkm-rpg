// Ferramentas do Mestre: importar dados do jogo (JSON do repositório) e sprites (PokeAPI → bucket privado).
import { supabase } from "../supabase";

const BASE = import.meta.env.BASE_URL as string;
type Progresso = (texto: string) => void;

interface MapaJson {
  id: string; nome: string; w: number; h: number; solido: string; grama: string;
  portais: unknown[]; pois: unknown[]; spawn?: { x: number; y: number };
}

async function json<T>(caminho: string): Promise<T> {
  const r = await fetch(`${BASE}${caminho}?t=${Date.now()}`);
  if (!r.ok) throw new Error(`Não achei ${caminho}`);
  return (await r.json()) as T;
}

async function enviar(tabela: string, linhas: unknown[], p: Progresso): Promise<void> {
  const TAM = 400;
  for (let i = 0; i < linhas.length; i += TAM) {
    p(`${tabela}: ${Math.min(i + TAM, linhas.length)}/${linhas.length}`);
    const { error } = await supabase.rpc("importar_dados", { p_tabela: tabela, p_linhas: linhas.slice(i, i + TAM) });
    if (error) throw new Error(`${tabela}: ${error.message}`);
  }
}

export async function importarDados(p: Progresso): Promise<void> {
  const mapas: unknown[] = [];
  for (const id of ["pallet", "rota1", "viridian"]) {
    const m = await json<MapaJson>(`assets/mapas/${id}.json`);
    mapas.push({
      id: m.id, nome: m.nome, largura: m.w, altura: m.h,
      spawn_x: m.spawn?.x ?? Math.floor(m.w / 2), spawn_y: m.spawn?.y ?? Math.floor(m.h / 2),
      tipo: "andavel", solido: m.solido, grama: m.grama, portais: m.portais, pois: m.pois,
    });
  }
  await enviar("mapas", mapas, p);
  const { error: ec } = await supabase.rpc("corrigir_posicoes");
  if (ec) throw new Error(`corrigir_posicoes: ${ec.message}`);
  p("treinadores...");
  const { error: et } = await supabase.rpc("importar_treinadores", { p_linhas: await json<unknown[]>("data/treinadores.json") });
  if (et) throw new Error(`treinadores: ${et.message}`);
  for (const t of ["especies", "golpes", "aprende", "eficacia", "naturezas", "itens", "encontros"]) {
    await enviar(t, await json<unknown[]>(`data/${t}.json`), p);
  }
  p("Dados importados.");
}

const FONTE = "https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/versions/generation-v/black-white";

/** Baixa os sprites animados (frente e costas) dos #1–151 e envia ao bucket privado `sprites`. */
export async function importarSprites(p: Progresso): Promise<void> {
  const { data: existentes } = await supabase.storage.from("sprites").list("frente", { limit: 1000 });
  const { data: existentesC } = await supabase.storage.from("sprites").list("costas", { limit: 1000 });
  const tem = new Set([
    ...(existentes ?? []).map((o) => `frente/${o.name}`),
    ...(existentesC ?? []).map((o) => `costas/${o.name}`),
  ]);
  let feitos = 0;
  let falhas = 0;
  for (let id = 1; id <= 151; id++) {
    for (const lado of ["frente", "costas"] as const) {
      const caminho = `${lado}/${id}.gif`;
      if (tem.has(caminho)) continue;
      try {
        const origem = lado === "frente" ? `${FONTE}/animated/${id}.gif` : `${FONTE}/animated/back/${id}.gif`;
        const r = await fetch(origem);
        if (!r.ok) throw new Error(String(r.status));
        const blob = await r.blob();
        const { error } = await supabase.storage.from("sprites").upload(caminho, blob, { upsert: true, contentType: "image/gif" });
        if (error) throw new Error(error.message);
        feitos++;
      } catch {
        falhas++;
      }
    }
    p(`Sprites: ${id}/151 (novos: ${feitos}, falhas: ${falhas})`);
  }
  p(`Sprites prontos. Novos: ${feitos}. Falhas: ${falhas}${falhas ? " (rode de novo para tentar as que faltam)" : ""}.`);
}
