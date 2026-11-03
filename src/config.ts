// Valores públicos por desenho (URL do projeto e chave publishable/anon). A segurança vem do RLS.
export const SUPABASE_URL = import.meta.env.VITE_SUPABASE_URL as string;
export const SUPABASE_ANON_KEY = import.meta.env.VITE_SUPABASE_ANON_KEY as string;
export const AMBIENTE = (import.meta.env.VITE_AMBIENTE as string) ?? "producao";

if (!SUPABASE_URL || !SUPABASE_ANON_KEY) {
  throw new Error("Configuração do Supabase ausente (veja .env.example).");
}
