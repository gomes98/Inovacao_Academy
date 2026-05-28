import OpenAI from 'openai'
import { createClient } from '@supabase/supabase-js'

export interface SearchResult {
  contentId: string
  contentTitle: string
  thumbnailUrl: string | null
  moduleName: string
  courseName: string
  chunkText: string
  startTime: number
  matchType: 'semantic' | 'fulltext'
}

export default defineEventHandler(async (event) => {
  const config = useRuntimeConfig()
  const query = getQuery(event)

  const q = String(query.q || '').trim()
  const courseId = query.courseId ? String(query.courseId) : null

  if (q.length < 2) {
    return []
  }

  const supabaseUrl = process.env.NUXT_PUBLIC_SUPABASE_URL!
  const supabaseKey = process.env.NUXT_PUBLIC_SUPABASE_KEY!
  const supabase = createClient(supabaseUrl, supabaseKey)

  // --- Busca full-text (ILIKE) ---
  const fulltextQuery = supabase.rpc('search_content_fulltext', {
    search_query: q,
    filter_course_id: courseId,
  })

  // --- Busca semântica (pgvector) ---
  let semanticRows: any[] = []
  try {
    const openai = new OpenAI({ apiKey: config.openaiApiKey })
    const embeddingRes = await openai.embeddings.create({
      model: 'text-embedding-3-small',
      input: q,
    })
    const vector = embeddingRes.data[0].embedding

    const { data: semData } = await supabase.rpc('search_content_semantic', {
      query_embedding: vector,
      filter_course_id: courseId,
      match_count: 20,
    })
    semanticRows = semData || []
  } catch {
    // fallback silencioso para apenas full-text se OpenAI falhar
  }

  const { data: fulltextRows } = await fulltextQuery

  // --- União e deduplicação ---
  // full-text tem prioridade: se chunk_id aparece nos dois, fica como 'fulltext'
  const seen = new Set<string>()
  const merged: SearchResult[] = []

  for (const row of (fulltextRows || [])) {
    if (seen.has(row.chunk_id)) continue
    seen.add(row.chunk_id)
    merged.push({
      contentId: row.content_id,
      contentTitle: row.content_title,
      thumbnailUrl: row.thumbnail_url,
      moduleName: row.module_title,
      courseName: row.course_title,
      chunkText: row.chunk_text,
      startTime: Number(row.start_time),
      matchType: 'fulltext',
    })
  }

  for (const row of semanticRows) {
    if (seen.has(row.chunk_id)) continue
    seen.add(row.chunk_id)
    merged.push({
      contentId: row.content_id,
      contentTitle: row.content_title,
      thumbnailUrl: row.thumbnail_url,
      moduleName: row.module_title,
      courseName: row.course_title,
      chunkText: row.chunk_text,
      startTime: Number(row.start_time),
      matchType: 'semantic',
    })
  }

  return merged.slice(0, 10)
})
