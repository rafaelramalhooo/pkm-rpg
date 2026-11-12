import "./style.css";
import { AMBIENTE } from "./config";
import { supabase, type Jogador } from "./supabase";
import { telaLogin, telaNovaSenha } from "./ui/login";
import { telaPersonagem } from "./ui/personagem";
import { telaJogo } from "./ui/jogo";
import { vigiarVersao } from "./ui/versao";

vigiarVersao();

if (AMBIENTE !== "producao") {
  const tag = document.createElement("div");
  tag.className = "amb";
  tag.textContent = `ambiente: ${AMBIENTE}`;
  document.body.append(tag);
}

let usuarioAtual: string | null | undefined; // undefined = ainda não roteado
let recuperando = /type=recovery/.test(window.location.hash); // abriu pelo link "Esqueci a senha"

async function rotear(userId: string | null): Promise<void> {
  if (userId === usuarioAtual) return; // o Supabase avisa a mesma sessão mais de uma vez
  usuarioAtual = userId;
  if (!userId) {
    telaLogin();
    return;
  }
  const { data, error } = await supabase
    .from("jogadores")
    .select("id, nome, papel, aparencia, mapa_id, x, y, direcao, pa, dinheiro")
    .eq("id", userId)
    .maybeSingle();
  if (usuarioAtual !== userId) return; // mudou de usuário enquanto carregava
  if (error) {
    telaLogin();
    return;
  }
  if (!data) telaPersonagem((j: Jogador) => void telaJogo(j));
  else void telaJogo(data as Jogador);
}

supabase.auth.onAuthStateChange((evento, sessao) => {
  const id = sessao?.user.id ?? null;
  if (evento === "PASSWORD_RECOVERY") recuperando = true;
  if (recuperando) {
    if (!id) return;
    telaNovaSenha(() => { recuperando = false; usuarioAtual = undefined; window.history.replaceState(null, "", window.location.pathname); void rotear(id); });
    return;
  }
  // Ignora renovações de token do mesmo usuário.
  if (evento === "TOKEN_REFRESHED") return;
  void rotear(id);
});

void supabase.auth.getSession().then(({ data }) => { if (!recuperando) void rotear(data.session?.user.id ?? null); });
