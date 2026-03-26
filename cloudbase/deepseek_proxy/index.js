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

const DEEPSEEK_API_KEY = process.env.DEEPSEEK_API_KEY || ''; // <-- set in CloudBase env
const APP_SECRET = process.env.APP_SECRET || ''; // <-- set in CloudBase env

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

function deepSeekRequest(bodyObj) {
  return new Promise((resolve, reject) => {
    const postData = JSON.stringify(bodyObj ?? {});
    const req = https.request(
      'https://api.deepseek.com/chat/completions',
      {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${DEEPSEEK_API_KEY}`,
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

exports.main_handler = async (event, context) => {
  const headers = (event && (event.headers || event.header)) || {};
  const method = String(event && (event.httpMethod || event.method) || 'POST').toUpperCase();

  // Basic CORS for HTTP triggers (safe default).
  const corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'Content-Type, X-App-Secret',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Content-Type': 'application/json; charset=utf-8',
  };

  if (method === 'OPTIONS') {
    return { statusCode: 204, headers: corsHeaders, body: '' };
  }

  if (!DEEPSEEK_API_KEY) {
    return {
      statusCode: 500,
      headers: corsHeaders,
      body: JSON.stringify({ error: 'Server misconfigured: missing DEEPSEEK_API_KEY' }),
    };
  }

  const provided = headerValue(headers, 'X-App-Secret');
  if (!APP_SECRET || provided !== APP_SECRET) {
    return {
      statusCode: 401,
      headers: corsHeaders,
      body: JSON.stringify({ error: 'Unauthorized' }),
    };
  }

  const bodyObj = parseJsonBody(event);
  if (!bodyObj || typeof bodyObj !== 'object') {
    return {
      statusCode: 400,
      headers: corsHeaders,
      body: JSON.stringify({ error: 'Invalid JSON body' }),
    };
  }

  try {
    const upstream = await deepSeekRequest(bodyObj);
    return {
      statusCode: upstream.statusCode,
      headers: { ...corsHeaders },
      body: upstream.body,
    };
  } catch (err) {
    return {
      statusCode: 502,
      headers: corsHeaders,
      body: JSON.stringify({ error: 'Bad gateway', detail: String(err && err.message || err) }),
    };
  }
};

