export function useCurrentCourseId(): string | undefined {
  const route = useRoute()

  if (route.name === 'courses-id') {
    return route.params.id as string
  }

  if (route.name === 'lesson-id') {
    return useState<string | undefined>('currentCourseId').value
  }

  return undefined
}
