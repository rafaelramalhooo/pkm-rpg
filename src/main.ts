import "./style.css";
import { AMBIENTE } from "./config";
import { supabase, type Jogador } from "./supabase";
import { telaLogin } from "./ui/login";
import { telaPersonagem } from "./ui/personagem";
import { telaJogo } from "./ui/jogo";

if (AMBIENTE !== "producao") {
  const tag = document.createElement("div");
  tag.className = "amb";
  tag.textContent = `ambiente: ${AMBIENTE}`;
  document.body.append(tag);
}

let usuarioAtual: string | null = null;

async function rotear(userId: string | null): Promise<void> {
  usuarioAtual = userId;
  if (!userId) {
    telaLogin();
    return;
  }
  const { data, error } = await supabase
    .from("jogadores")
    .select("id, nome, papel, aparencia, mapa_id, x, y, direcao")
    .eq("id", userId)
    .maybeSingle();
  if (usuarioAtual !== userId) return; // mudou de usuário enquanto carregava
  if (error) {
    telaLogin();
    return;
  }
  if (!data) telaPersonagem((j: Jogador) => telaJogo(j));
  else telaJogo(data as Jogador);
}

supabase.auth.onAuthStateChange((evento, sessao) => {
  const id = sessao?.user.id ?? null;
  // Ignora renovações de token do mesmo usuário.
  if (evento === "TOKEN_REFRESHED" || (evento === "SIGNED_IN" && id === usuarioAtual)) return;
  void rotear(id);
});

void supabase.auth.getSession().then(({ data }) => rotear(data.session?.user.id ?? null));
