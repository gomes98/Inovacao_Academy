# Gamificação — Design Spec
**Data:** 2026-05-21  
**Status:** Aprovado

---

## Visão Geral

Sistema de gamificação para o Inovação Academy LMS que recompensa alunos por engajamento real com o conteúdo. Os pontos são acumulados globalmente mas o ranking e a competição ocorrem dentro de cada grupo. O sistema combina pontuação individual, ranking por grupo, níveis progressivos e badges de conquista.

---

## 1. Banco de Dados

### Tabelas Novas

#### `point_events` — log auditável
```sql
id          uuid PRIMARY KEY DEFAULT gen_random_uuid()
user_id     uuid NOT NULL REFERENCES auth.users(id)
group_id    uuid NOT NULL REFERENCES groups(id)
event_type  text NOT NULL  -- 'video_watched' | 'video_completed' | 'comment_posted' | 'comment_replied'
points      integer NOT NULL
reference_id uuid NOT NULL  -- content_id ou comment_id relacionado
created_at  timestamptz DEFAULT now()

UNIQUE (user_id, event_type, reference_id)
```

#### `user_points` — saldo agregado
```sql
id           uuid PRIMARY KEY DEFAULT gen_random_uuid()
user_id      uuid NOT NULL REFERENCES auth.users(id)
group_id     uuid NOT NULL REFERENCES groups(id)
total_points integer NOT NULL DEFAULT 0
updated_at   timestamptz DEFAULT now()

UNIQUE (user_id, group_id)
```
Atualizado via Postgres trigger a cada INSERT em `point_events`.

#### `badges` — catálogo de conquistas
```sql
id               uuid PRIMARY KEY DEFAULT gen_random_uuid()
slug             text UNIQUE NOT NULL
name             text NOT NULL
description      text NOT NULL
icon_url         text
condition_type   text NOT NULL  -- 'comment_count' | 'video_count' | 'ranking_position' | 'streak_days'
condition_value  integer NOT NULL
```

#### `user_badges` — badges conquistados
```sql
id         uuid PRIMARY KEY DEFAULT gen_random_uuid()
user_id    uuid NOT NULL REFERENCES auth.users(id)
badge_id   uuid NOT NULL REFERENCES badges(id)
earned_at  timestamptz DEFAULT now()

UNIQUE (user_id, badge_id)
```

#### `point_rules` — configuração de pontos (editável pelo admin)
```sql
id         uuid PRIMARY KEY DEFAULT gen_random_uuid()
event_type text UNIQUE NOT NULL
points     integer NOT NULL
is_active  boolean DEFAULT true
```

**Valores default:**
| event_type | points |
|---|---|
| `video_watched` | 10 |
| `video_completed` | 20 |
| `comment_posted` | 5 |
| `comment_replied` | 3 |

### Triggers e Functions

**Trigger `after_point_event_insert`** — atualiza `user_points` com UPSERT após cada evento.

**Function `check_badges(user_id)`** — chamada pelo trigger, verifica todas as condições de badge e insere em `user_badges` se satisfeitas e ainda não conquistadas.

---

## 2. Lógica de Pontuação

### Eventos e Disparo

| Evento | Quando disparar | Frontend |
|---|---|---|
| `video_watched` | Player atinge ≥ 80% do vídeo | `VideoPlayer.vue` callback de progresso |
| `video_completed` | Aluno clica "Marcar como concluído" | `lesson/[id].vue` botão existente |
| `comment_posted` | INSERT de comentário com `parent_id = null` | `lesson/[id].vue` após submit |
| `comment_replied` | INSERT de comentário com `parent_id` preenchido | `CommentItem.vue` após submit |

**Nota:** `video_completed` (20pts) não soma com `video_watched` (10pts) — são eventos distintos com `reference_id` diferente no unique constraint. O aluno pode ganhar ambos assistindo e depois concluindo, ou só o `video_completed` se pular direto.

### Anti-fraude
- Unique constraint `(user_id, event_type, reference_id)` no banco — duplicatas são silenciosamente ignoradas via `ON CONFLICT DO NOTHING`
- RLS do Supabase garante que o `user_id` do evento sempre é o usuário autenticado
- Pontos por vídeo só liberados após ≥ 80% assistido — não basta abrir a página

### Composable `useGamification`

```ts
// app/composables/useGamification.ts
const { trackEvent, userPoints, userLevel, userBadges } = useGamification()

// Registra um evento de pontuação
await trackEvent('video_watched', contentId)
```

Internamente faz INSERT em `point_events`. O trigger cuida do resto.

---

## 3. Níveis

Calculados no frontend a partir de `total_points` — não persistidos no banco.

| Nível | Nome | Pontos mínimos |
|---|---|---|
| 1 | Aprendiz | 0 |
| 2 | Explorador | 100 |
| 3 | Praticante | 300 |
| 4 | Especialista | 700 |
| 5 | Mestre | 1.500 |

A composable `useGamification` expõe `userLevel` com `{ level, name, minPoints, nextLevelPoints, progress }`.

---

## 4. Badges

| Slug | Nome | Condição |
|---|---|---|
| `first_video` | Primeiros Passos | Assistir o 1º vídeo |
| `first_comment` | Primeira Voz | Postar o 1º comentário |
| `video_5` | Maratonista | 5 vídeos assistidos |
| `comment_10` | Participativo | 10 comentários postados |
| `top3_group` | Pódio | Estar no top 3 do ranking do grupo |
| `streak_7` | Constante | Assistir vídeos por 7 dias seguidos |

Verificação server-side via `check_badges()` Postgres function disparada pelo trigger de `point_events`. O badge `top3_group` é verificado também via cron job diário (pois a posição pode mudar sem ação do próprio usuário).

---

## 5. Ranking por Grupo

- Query em `user_points` filtrada por `group_id`, ordenada por `total_points DESC`
- Top 3 recebem destaque visual (ouro, prata, bronze)
- A posição do aluno logado é sempre exibida, mesmo fora do top
- Implementado como view `group_ranking_view` no Supabase para simplificar queries

---

## 6. Interface do Usuário

### Dashboard (`/`)
Widget expansível no topo do catálogo de cursos:
- **Compacto:** ícone de nível + nome + total de pontos + posição no grupo
- **Expandido:** barra de progresso para próximo nível, ranking top 5 do grupo, próximo badge a conquistar

### Página da Aula (`/lesson/[id]`)
- Toast de feedback imediato ao ganhar pontos: "+10 pts — Vídeo assistido!"
- Animação/modal de badge ao desbloquear uma conquista

### Perfil (`/profile`)
- Card com total de pontos, nível atual e barra de progresso
- Grid de badges: conquistados em cor, não conquistados em cinza com cadeado

### Admin
- Tabela editável de `point_rules` em `/admin`
- Visão de ranking geral por grupo
- Ação manual de conceder badge a um aluno

---

## 7. Fora de Escopo

- Recompensas reais (cupons, prêmios físicos)
- Desafios semanais com prazo
- Ranking entre grupos diferentes
- Pontos por outras ações além das 4 definidas

---

## 8. Dependências e Riscos

- O player de vídeo atual (`VideoPlayer.vue`) precisa expor evento de progresso — verificar se a biblioteca suporta callback de percentual
- O badge `streak_7` requer rastrear datas de acesso — pode precisar de tabela auxiliar `user_streaks`
- O badge `top3_group` muda sem ação do aluno — precisa de verificação periódica (cron ou trigger em `user_points`)
