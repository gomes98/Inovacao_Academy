import type { SearchResult } from '~/server/api/search.get'

export function useSearch() {
  const query = ref('')
  const results = ref<SearchResult[]>([])
  const isLoading = ref(false)
  const error = ref<string | null>(null)
  const courseId = useCurrentCourseId()

  let debounceTimer: ReturnType<typeof setTimeout> | null = null
  let abortController: AbortController | null = null

  async function performSearch(q: string) {
    if (q.length < 2) {
      results.value = []
      return
    }

    isLoading.value = true
    error.value = null

    // Aborta request anterior se ainda estiver em andamento
    abortController?.abort()
    abortController = new AbortController()

    const timeout = setTimeout(() => abortController?.abort(), 5000)

    try {
      const params = new URLSearchParams({ q })
      if (courseId) params.set('courseId', courseId)

      const data = await $fetch<SearchResult[]>(`/api/search?${params}`, {
        signal: abortController.signal,
      })
      results.value = data
    } catch (err: any) {
      if (err?.name !== 'AbortError') {
        error.value = 'Erro ao buscar. Tente novamente.'
      }
      results.value = []
    } finally {
      clearTimeout(timeout)
      isLoading.value = false
    }
  }

  watch(query, (q) => {
    if (debounceTimer) clearTimeout(debounceTimer)
    if (q.length < 2) {
      results.value = []
      isLoading.value = false
      return
    }
    debounceTimer = setTimeout(() => performSearch(q), 400)
  })

  function clear() {
    query.value = ''
    results.value = []
    error.value = null
    abortController?.abort()
  }

  return { query, results, isLoading, error, clear }
}
