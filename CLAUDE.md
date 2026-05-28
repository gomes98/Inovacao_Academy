# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
npm run dev          # Start dev server at http://localhost:3000
npm run build        # Production build
npm run generate     # Static site generation
npm run preview      # Preview production build
npm install          # Install dependencies (also runs nuxt prepare)
```

There are no test commands configured in this project.

## Architecture

**Inovação Academy** is a Learning Management System (LMS) built with Nuxt 4 + Supabase.

### Stack
- **Frontend:** Nuxt 4 (Vue 3), TypeScript, Tailwind CSS v3
- **Backend:** Supabase (PostgreSQL, Auth, Storage)
- **Modules:** `@nuxtjs/supabase`, `@nuxtjs/tailwindcss`

### Key Nuxt Patterns
- Nuxt **auto-imports** are used throughout — no explicit imports for `ref`, `watch`, `computed`, `useSupabaseClient`, `useSupabaseUser`, `useAsyncData`, `navigateTo`, etc.
- The `app/` directory structure follows Nuxt 4 conventions.
- Authentication is handled globally via `nuxt.config.ts` `supabase.redirect` option: unauthenticated users are sent to `/login`, post-auth callback goes to `/confirm`.

### Auth Flow
`/login` → Supabase Auth → `/confirm` (email verification redirect) → `/` (dashboard). The `@nuxtjs/supabase` module handles middleware automatically based on `nuxt.config.ts` redirect config.

### Database Layer
`app/types/database.types.ts` contains auto-generated Supabase TypeScript types. When updating schema, regenerate this file via the Supabase CLI (`supabase gen types typescript`).

Key tables: `courses`, `modules`, `contents`, `comments`, `private_notes`, `perfis` (user profiles), `attachments`, `user_progress`, `content_transcriptions`, `content_chunks`, `user_access_mode`, `user_course_access`, `permission_groups`, `group_course_access`, `user_groups`, `point_rules`, `point_events`, `user_points`, `badges`, `user_badges`, `user_streaks`.

Key views used for queries (prefer these over raw table joins):
- `course_catalog` — courses with module/content counts
- `course_structure` — flattened course→module→content hierarchy
- `content_comments_view` — comments with user display names
- `content_private_notes_view` — notes with user metadata

`has_role()` is a Supabase RLS function used for admin access control.

### File Storage
- `avatars` bucket: user profile pictures, path `{userId}/{timestamp}.{ext}`
- `courses` bucket: course content files, path `course-{courseId}/{moduleId}/{filename}.{ext}`

### Pages Overview
| Route | Purpose |
|-------|---------|
| `/` | Student dashboard — course catalog |
| `/login` | Auth (login + signup) |
| `/confirm` | Email verification redirect |
| `/profile` | User profile + avatar upload |
| `/courses/[id]` | Course detail — module/content structure |
| `/lesson/[id]` | Lesson viewer — video/document + comments + private notes |
| `/admin/courses` | Admin — list and create courses |
| `/admin/courses/[id]` | Admin — manage modules and content, file uploads |
| `/admin/gamification` | Admin — gamification rules and badges |
| `/admin/groups` | Admin — permission groups management |
| `/admin/users` | Admin — user management |

### Data Fetching Convention
- Initial page data: `useAsyncData()` for SSR-compatible fetching
- Mutations and event-driven fetches: direct `useSupabaseClient()` calls
- Supabase error code `PGRST116` = no rows found (not an error in most cases)

### UI Conventions
- Dark theme: `#050505` background, white/gray text
- Glassmorphism cards with `backdrop-blur`
- Accent colors: purple (`#a855f7`) and blue gradients
- Font: Barlow + Barlow Condensed (loaded via Google Fonts in `app.vue`)
