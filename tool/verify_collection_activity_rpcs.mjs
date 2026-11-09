import { appConfig, ownerLogins } from './backup/lib/config.mjs';
import { api, signIn } from './backup/lib/export_rest.mjs';

const config = appConfig();
let session = null;
for (const login of ownerLogins()) {
  session = await signIn({ ...config, ...login });
  if (session) break;
}
if (!session) throw new Error('Owner sign-in failed.');
const client = api({ ...config, token: session.token });
const missing = '00000000-0000-0000-0000-000000000000';
for (const [name, body] of [
  ['update_collection_activity', {
    p_activity_id: missing,
    p_activity_type: 'call',
    p_outcome: 'RPC verification',
    p_notes: '',
    p_promised_on: null,
    p_promised_amount_centavos: null,
  }],
  ['delete_collection_activity', { p_activity_id: missing }],
]) {
  try {
    await client.rpc(name, body);
    throw new Error(`${name} unexpectedly accepted a missing activity.`);
  } catch (error) {
    const message = String(error);
    if (!message.includes('Collection activity not found')) throw error;
    console.log(`PASS ${name} is available and enforces activity existence`);
  }
}
