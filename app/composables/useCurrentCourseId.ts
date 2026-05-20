import type { ComputedRef } from 'vue'

export function useCurrentCourseId(): ComputedRef<string | undefined> {
  const route = useRoute()
  const currentCourseId = useState<string | undefined>('currentCourseId')

  return computed(() => {
    if (route.name === 'courses-id') {
      return route.params.id as string
    }
    if (route.name === 'lesson-id') {
      return currentCourseId.value
    }
    return undefined
  })
}
