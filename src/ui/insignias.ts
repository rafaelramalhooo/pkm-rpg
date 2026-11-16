// Insígnias dos 8 Ginásios: imagem colorida (conquistada) ou em cinza (ainda não).
export interface InfoInsignia { slug: string; nome: string; cidade: string; mapa: string }
export const INSIGNIAS: InfoInsignia[] = [
  { slug: "tijolo", nome: "Tijolo", cidade: "Argila", mapa: "argila" },
  { slug: "folha", nome: "Folha", cidade: "Verdelume", mapa: "verdelume" },
  { slug: "mare", nome: "Maré", cidade: "Azurana", mapa: "azurana" },
  { slug: "petala", nome: "Pétala", cidade: "Quartzo Rosa", mapa: "quartzo" },
  { slug: "faisca", nome: "Faísca", cidade: "Âmbar", mapa: "ambar" },
  { slug: "brasa", nome: "Brasa", cidade: "Carmesim", mapa: "carmesim" },
  { slug: "nevoa", nome: "Névoa", cidade: "Ametista", mapa: "ametista" },
  { slug: "eclipse", nome: "Eclipse", cidade: "Obsidiana", mapa: "obsidiana" },
];
export const urlInsignia = (slug: string): string => `${import.meta.env.BASE_URL}assets/insignias/${slug}.png`;
export const insigniaDoMapa = (mapa: string): InfoInsignia | undefined => INSIGNIAS.find((i) => i.mapa === mapa);
