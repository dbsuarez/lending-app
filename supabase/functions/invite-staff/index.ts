import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: cors })
  try {
    const authorization = request.headers.get('Authorization') ?? ''
    const url = Deno.env.get('SUPABASE_URL')!
    const anonKey = Deno.env.get('SUPABASE_ANON_KEY')!
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const caller = createClient(url, anonKey, { global: { headers: { Authorization: authorization } } })
    const admin = createClient(url, serviceKey)
    const { data: auth, error: authError } = await caller.auth.getUser()
    if (authError || !auth.user) throw new Error('Authentication is required')

    const body = await request.json()
    const email = String(body.email ?? '').trim().toLowerCase()
    const role = String(body.role ?? '')
    const organizationId = String(body.organization_id ?? '')
    if (!email.includes('@') || !['owner', 'manager', 'collector', 'auditor'].includes(role)) {
      throw new Error('A valid email and role are required')
    }

    const { data: invitationId, error: invitationError } = await caller.rpc('create_staff_invitation', {
      p_organization_id: organizationId,
      p_email: email,
      p_role: role,
    })
    if (invitationError) throw invitationError

    const { data: invited, error: inviteError } = await admin.auth.admin.inviteUserByEmail(email, {
      data: { organization_id: organizationId, organization_role: role, invitation_id: invitationId },
    })
    if (inviteError) throw inviteError
    if (!invited.user) throw new Error('The invitation did not return a user')

    const { error: memberError } = await admin.from('organization_members').upsert({
      organization_id: organizationId,
      user_id: invited.user.id,
      role,
      status: 'active',
    })
    if (memberError) throw memberError
    await admin.from('staff_invitations').update({
      status: 'accepted',
      accepted_at: new Date().toISOString(),
    }).eq('id', invitationId)

    return new Response(JSON.stringify({ invitation_id: invitationId }), {
      headers: { ...cors, 'Content-Type': 'application/json' },
    })
  } catch (error) {
    return new Response(JSON.stringify({ error: error instanceof Error ? error.message : String(error) }), {
      status: 400,
      headers: { ...cors, 'Content-Type': 'application/json' },
    })
  }
})
