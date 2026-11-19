const test = require('node:test');
const assert = require('node:assert/strict');
const { createHandler } = require('../index');
const env = { APP_SECRET: 'test-only-client-secret', DEEPSEEK_API_KEY: 'test-only-provider-key' };
const event = body => ({ httpMethod: 'POST', headers: { 'X-App-Secret': env.APP_SECRET }, body: JSON.stringify(body) });

test('health probes report configuration without calling the model or exposing credentials', async () => {
  const handler = createHandler({ env, provider: () => { throw new Error('must not call model'); } });
  const response = await handler({ httpMethod: 'GET' });
  assert.equal(response.statusCode, 200);
  assert.deepEqual(JSON.parse(response.body), { ok: true, service: 'lingfer-reading-proxy', version: 2, modelReady: true });
  assert.ok(!response.body.includes(env.DEEPSEEK_API_KEY));
  assert.equal(JSON.parse((await createHandler({ env: {} })({ httpMethod: 'GET' })).body).modelReady, false);
});

test('unauthorized and invalid reading requests never reach the provider', async () => {
  let calls = 0;
  const handler = createHandler({ env, provider: async () => { calls++; } });
  assert.equal((await handler({ ...event({ messages: [] }), headers: {} })).statusCode, 401);
  assert.equal((await handler(event({ messages: [] }))).statusCode, 400);
  assert.equal((await handler(event({ messages: [{ role: 'user', content: 'x'.repeat(25000) }] }))).statusCode, 400);
  assert.equal(calls, 0);
});

test('existing translation request format is preserved while provider/model are server controlled', async () => {
  let received;
  const handler = createHandler({ env, provider: async (payload, key) => {
    received = payload;
    assert.equal(key, env.DEEPSEEK_API_KEY);
    return { statusCode: 200, body: JSON.stringify({ choices: [{ message: { content: '维护；保持' } }] }) };
  } });
  const response = await handler(event({ model: 'untrusted-client-model', messages: [{ role: 'user', content: 'Explain maintain' }], temperature: 99, max_tokens: 99999 }));
  assert.equal(response.statusCode, 200);
  assert.equal(received.model, 'deepseek-chat');
  assert.equal(received.temperature, 1);
  assert.equal(received.max_tokens, 3000);
  assert.equal(JSON.parse(response.body).choices[0].message.content, '维护；保持');
});

test('provider failures return a recoverable response without private exception details', async () => {
  const handler = createHandler({ env, provider: async () => { throw new Error('private-key-and-screen-content'); } });
  const response = await handler(event({ messages: [{ role: 'user', content: 'hello' }] }));
  assert.equal(response.statusCode, 502);
  assert.ok(!response.body.includes('private-key'));
});
