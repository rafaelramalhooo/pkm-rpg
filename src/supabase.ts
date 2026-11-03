import { createClient } from "@supabase/supabase-js";
import { SUPABASE_ANON_KEY, SUPABASE_URL } from "./config";

export const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
  auth: { persistSession: true, autoRefreshToken: true },
});

export type Direcao = "cima" | "baixo" | "esquerda" | "direita";

export interface Jogador {
  id: string;
  nome: string;
  papel: "jogador" | "mestre";
  aparencia: number;
  mapa_id: string;
  x: number;
  y: number;
  direcao: Direcao;
}
