// Créditos: os sprites animados do seguidor vêm do PMDCollab SpriteCollab (artistas da comunidade).
import { el } from "./dom";
import { creditosSeguidor } from "./dados";

type Modal = { abrir: (titulo: string, ...nos: Node[]) => void; fechar: () => void };

export async function abrirCreditos(modal: Modal): Promise<void> {
  const c = await creditosSeguidor();
  const nos: Node[] = [
    el("p", { class: "sub" }, "Jogo privado, sem fins comerciais, feito para o Mestre e seus amigos. Pokémon e seus personagens pertencem à Nintendo, Game Freak e The Pokémon Company."),
    el("p", { class: "sub" }, "Sprites animados do Pokémon que acompanha o treinador: PMDCollab SpriteCollab (github.com/PMDCollab/SpriteCollab), criados pela comunidade. Obrigado aos artistas:"),
  ];
  if (c?.autores?.length) nos.push(el("div", { class: "rec-lista" }, ...c.autores.map((a) => el("span", {}, a))));
  else nos.push(el("p", { class: "sub" }, "Lista de artistas indisponível no momento."));
  modal.abrir("📜 Créditos", ...nos);
}
