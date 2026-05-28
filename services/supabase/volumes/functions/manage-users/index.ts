import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? ''
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    
    const supabaseClient = createClient(supabaseUrl, serviceRoleKey, {
      global: { headers: { Authorization: req.headers.get('Authorization')! } }
    })

    // Get current user and check admin role
    const { data: { user: caller }, error: authError } = await supabaseClient.auth.getUser()
    if (authError || !caller) throw new Error('Não autorizado')

    const { data: profile } = await supabaseClient
      .from('perfis')
      .select('role')
      .eq('id', caller.id)
      .single()

    if (profile?.role !== 'admin') {
      throw new Error('Acesso negado: Somente administradores')
    }

    const { action, email, password, userId, role, name } = await req.json()
    const adminClient = createClient(supabaseUrl, serviceRoleKey)

    if (action === 'invite') {
      const { data, error } = await adminClient.auth.admin.inviteUserByEmail(email, {
        data: { name: name || 'Usuário Convidado' }
      })
      if (error) throw error
      
      // Update role in perfis if specified
      if (role) {
        await adminClient.from('perfis').update({ role }).eq('id', data.user.id)
      }
      
      return new Response(JSON.stringify(data), { headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    if (action === 'create') {
      const { data, error } = await adminClient.auth.admin.createUser({
        email,
        password,
        email_confirm: true,
        user_metadata: { name: name || 'Novo Usuário' }
      })
      if (error) throw error
      
      // Update role in perfis if specified (trigger creates it as disabled)
      if (role) {
        await adminClient.from('perfis').update({ role }).eq('id', data.user.id)
      }
      
      return new Response(JSON.stringify(data), { headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    if (action === 'delete') {
      const { error } = await adminClient.auth.admin.deleteUser(userId)
      if (error) throw error
      return new Response(JSON.stringify({ success: true }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    if (action === 'update_user') {
      // Update Auth email if provided
      if (email) {
        const { error } = await adminClient.auth.admin.updateUserById(userId, { email })
        if (error) throw error
      }
      
      // Update Profile
      const updateData: any = {}
      if (name) updateData.name = name
      if (role) updateData.role = role
      
      const { error } = await adminClient.from('perfis').update(updateData).eq('id', userId)
      if (error) throw error
      
      return new Response(JSON.stringify({ success: true }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    throw new Error('Ação inválida')
  } catch (error) {
    return new Response(JSON.stringify({ error: error.message }), {
      status: 400,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }
})
