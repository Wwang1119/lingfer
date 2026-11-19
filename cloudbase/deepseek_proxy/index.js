/**
 * Tencent CloudBase (Cloud Development) HTTP-triggered cloud function.
 *
 * - Verifies `X-App-Secret` from request headers.
 * - Proxies request body to DeepSeek chat completions API.
 * - Returns DeepSeek response as-is.
 *
 * NOTE:
 * - Put secrets in environment variables, not in code.
 *   - DEEPSEEK_API_KEY: DeepSeek API key
 *   - APP_SECRET: shared secret expected in `X-App-Secret`
 */

'use strict';

const https = require('https');

const crypto = require('node:crypto');

function headerValue(headers, key) {
  if (!headers) return '';
  const lower = key.toLowerCase();
  for (const k of Object.keys(headers)) {
    if (k.toLowerCase() === lower) return String(headers[k] ?? '');
  }
  return '';
}

function parseJsonBody(event) {
  const raw = event && (event.body ?? event.data);
  if (raw == null) return null;
  if (typeof raw === 'object') return raw;
  if (typeof raw !== 'string') return null;
  try {
    return JSON.parse(raw);
  } catch (_) {
    return null;
  }
}

function deepSeekRequest(bodyObj, apiKey) {
  return new Promise((resolve, reject) => {
    const postData = JSON.stringify(bodyObj ?? {});
    const req = https.request(
      'https://api.deepseek.com/chat/completions',
      {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${apiKey}`,
          'Content-Length': Buffer.byteLength(postData),
        },
        timeout: 25_000,
      },
      (res) => {
        let data = '';
        res.setEncoding('utf8');
        res.on('data', (chunk) => (data += chunk));
        res.on('end', () => {
          resolve({
            statusCode: res.statusCode || 500,
            headers: res.headers || {},
            body: data,
          });
        });
      },
    );

    req.on('timeout', () => {
      req.destroy(new Error('Upstream timeout'));
    });
    req.on('error', reject);
    req.write(postData);
    req.end();
  });
}

function createHandler({ env = process.env, provider = deepSeekRequest } = {}) {
 return async (event, context) => {
  const headers = (event && (event.headers || event.header)) || {};
  const method = String(event && (event.httpMethod || event.method) || 'POST').toUpperCase();

  // Basic CORS for HTTP triggers (safe default).
  const corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'Content-Type, X-App-Secret',
    'Access-Control-Allow-Methods': 'GET, HEAD, POST, OPTIONS',
    'Content-Type': 'application/json; charset=utf-8',
  };

  if (method === 'OPTIONS') {
    return { statusCode: 204, headers: corsHeaders, body: '' };
  }

  // A health probe checks deployment/configuration only. It never sends screen
  // content to a model and never consumes model tokens.
  if (method === 'GET' || method === 'HEAD') {
    return { statusCode: 200, headers: corsHeaders, body: method === 'HEAD' ? '' : JSON.stringify({
      ok: true, service: 'lingfer-reading-proxy', version: 2,
      modelReady: Boolean(env.DEEPSEEK_API_KEY && env.APP_SECRET),
    }) };
  }
  if (method !== 'POST') return { statusCode: 405, headers: corsHeaders, body: JSON.stringify({ error: 'Method not allowed' }) };

  if (!env.DEEPSEEK_API_KEY) {
    return {
      statusCode: 500,
      headers: corsHeaders,
      body: JSON.stringify({ error: 'Server misconfigured: missing DEEPSEEK_API_KEY' }),
    };
  }

  const provided = headerValue(headers, 'X-App-Secret');
  const expected = env.APP_SECRET || '';
  const valid = expected && provided && Buffer.byteLength(expected) === Buffer.byteLength(provided)
    && crypto.timingSafeEqual(Buffer.from(expected), Buffer.from(provided));
  if (!valid) {
    return {
      statusCode: 401,
      headers: corsHeaders,
      body: JSON.stringify({ error: 'Unauthorized' }),
    };
  }

  const bodyObj = parseJsonBody(event);
  if (!bodyObj || typeof bodyObj !== 'object' || !Array.isArray(bodyObj.messages)
      || bodyObj.messages.length === 0 || bodyObj.messages.length > 12
      || bodyObj.messages.some(message => !message || !['system', 'user', 'assistant'].includes(message.role)
        || typeof message.content !== 'string')
      || JSON.stringify(bodyObj).length > 24000) {
    return {
      statusCode: 400,
      headers: corsHeaders,
      body: JSON.stringify({ error: 'Invalid JSON body' }),
    };
  }

  try {
    const payload = {
      model: env.DEEPSEEK_MODEL || 'deepseek-chat',
      messages: bodyObj.messages,
      temperature: typeof bodyObj.temperature === 'number' ? Math.max(0, Math.min(1, bodyObj.temperature)) : 0.2,
      max_tokens: Math.max(128, Math.min(3000, Number(bodyObj.max_tokens) || 1600)),
    };
    const upstream = await provider(payload, env.DEEPSEEK_API_KEY);
    return {
      statusCode: upstream.statusCode,
      headers: { ...corsHeaders },
      body: upstream.body,
    };
  } catch (err) {
    return {
      statusCode: 502,
      headers: corsHeaders,
      body: JSON.stringify({ error: 'AI service temporarily unavailable' }),
    };
  }
 };
}

exports.createHandler = createHandler;
exports.main_handler = createHandler();

