import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'apikey, content-type',
  'Access-Control-Allow-Methods': 'GET, OPTIONS',
}

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: cors })
  if (request.method !== 'GET') return json({ error: 'Method not allowed' }, 405)

  const token = new URL(request.url).searchParams.get('token') ?? ''
  if (!/^[a-f0-9]{64}$/i.test(token)) return json({ error: 'Invalid or revoked link' }, 400)

  const url = Deno.env.get('SUPABASE_URL')!
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
  const admin = createClient(url, serviceKey, { auth: { persistSession: false } })
  const { data, error } = await admin.rpc('get_shared_payment_qrs', { p_token: token })
  if (error) return json({ error: 'Invalid or revoked link' }, 404)

  const output = []
  for (const item of data ?? []) {
    const { data: signed, error: signError } = await admin.storage
      .from('payment-qrs')
      .createSignedUrl(item.storage_path, 900)
    if (!signError && signed?.signedUrl) {
      output.push({ label: item.label, url: signed.signedUrl })
    }
  }
  return json(output, 200)
})

function json(body: unknown, status: number) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, 'Content-Type': 'application/json', 'Cache-Control': 'no-store' },
  })
}
