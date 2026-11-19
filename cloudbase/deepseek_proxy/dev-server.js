'use strict';

// Run in this same repository: node --env-file=.env.local cloudbase/deepseek_proxy/dev-server.js
const http = require('node:http');
const { main_handler } = require('./index');
const port = Number(process.env.LINGFER_PORT || 3000);

http.createServer(async (request, response) => {
  let body = '';
  for await (const chunk of request) {
    body += chunk.toString('utf8');
    if (Buffer.byteLength(body) > 65536) {
      response.writeHead(413, { 'Content-Type': 'application/json' });
      response.end(JSON.stringify({ error: 'Request too large' }));
      return;
    }
  }
  const result = await main_handler({ httpMethod: request.method, headers: request.headers, body });
  response.writeHead(result.statusCode, result.headers);
  response.end(result.body);
}).listen(port, '127.0.0.1', () => {
  console.log(`Lingfer reading proxy listening on http://127.0.0.1:${port}`);
});
