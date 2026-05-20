import { serverSupabaseClient } from '#supabase/server'

export default defineEventHandler(async (event) => {
  const { contentId } = getRouterParams(event)

  if (!/^[0-9a-f-]{36}$/i.test(contentId)) {
    throw createError({ statusCode: 400, message: 'contentId inválido' })
  }

  const supabase = await serverSupabaseClient(event)

  const { data: { user }, error: authError } = await supabase.auth.getUser()
  if (authError || !user) {
    throw createError({ statusCode: 401, message: 'Não autenticado' })
  }

  const { data: isAdmin, error: roleError } = await supabase
    .rpc('has_role', { required_roles: ['admin', 'publicador'] })
  if (roleError || !isAdmin) {
    throw createError({ statusCode: 403, message: 'Acesso negado' })
  }

  const config = useRuntimeConfig()
  if (!config.workerUrl || !config.workerSecret) {
    throw createError({ statusCode: 503, message: 'Worker não configurado' })
  }

  const workerRes = await fetch(
    `${config.workerUrl}/jobs/transcribe/${contentId}`,
    {
      method: 'POST',
      headers: { Authorization: `Bearer ${config.workerSecret}` },
    }
  )

  if (!workerRes.ok) {
    const body = await workerRes.text()
    throw createError({ statusCode: workerRes.status, message: `Worker error: ${body}` })
  }

  return { accepted: true, contentId }
})
