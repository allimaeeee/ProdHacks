const functions = require('firebase-functions');
const https = require('https');

/**
 * Proxies requests to Google Maps APIs. Runs in us-central1 to fix wrong-country
 * geocode results (e.g. Turkey instead of Pittsburgh) caused by public CORS proxies.
 *
 * GET: ?url=encoded_target_url
 * POST: { "url": "https://...", "body": "...", "apiKey": "..." }  -- apiKey added as X-Goog-Api-Key for Places API
 */
exports.mapsProxy = functions
  .region('us-central1')
  .runWith({ timeoutSeconds: 30 })
  .https.onRequest(async (req, res) => {
    res.set('Access-Control-Allow-Origin', '*');
    if (req.method === 'OPTIONS') {
      res.set('Access-Control-Allow-Methods', 'GET, POST');
      res.set('Access-Control-Allow-Headers', 'Content-Type');
      res.status(204).send('');
      return;
    }

    let targetUrl, body, method = 'GET', apiKey = null;
    if (req.method === 'POST' && req.body) {
      targetUrl = req.body.url;
      body = req.body.body || null;
      apiKey = req.body.apiKey || null;
      method = body ? 'POST' : 'GET';
    } else if (req.method === 'GET' && req.query.url) {
      targetUrl = decodeURIComponent(req.query.url);
    } else {
      res.status(400).json({ error: 'Missing url' });
      return;
    }

    if (!targetUrl || (!targetUrl.startsWith('https://maps.googleapis.com/') && !targetUrl.startsWith('https://places.googleapis.com/'))) {
      res.status(400).json({ error: 'Invalid url' });
      return;
    }

    try {
      const data = await fetchUrl(targetUrl, method, body, apiKey);
      res.set('Content-Type', 'application/json');
      res.send(data);
    } catch (e) {
      console.error('Proxy error:', e);
      res.status(502).json({ error: 'Proxy failed: ' + e.message });
    }
  });

function fetchUrl(url, method, body, apiKey) {
  return new Promise((resolve, reject) => {
    const u = new URL(url);
    const headers = method === 'POST' ? { 'Content-Type': 'application/json' } : {};
    if (apiKey) headers['X-Goog-Api-Key'] = apiKey;
    const opts = {
      hostname: u.hostname,
      path: u.pathname + u.search,
      method: method,
      headers,
    };
    const req = https.request(opts, (res) => {
      let data = '';
      res.on('data', (chunk) => (data += chunk));
      res.on('end', () => {
        if (res.statusCode >= 200 && res.statusCode < 300) resolve(data);
        else reject(new Error('HTTP ' + res.statusCode));
      });
    });
    req.on('error', reject);
    req.setTimeout(25000, () => { req.destroy(); reject(new Error('Timeout')); });
    if (body) req.write(body);
    req.end();
  });
}
