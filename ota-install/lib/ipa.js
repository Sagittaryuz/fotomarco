const { pipeline } = require('node:stream/promises');
const { Readable } = require('node:stream');

const blockSize = 512 * 1024;
const concurrentBlocks = 8;

async function readBlock(url, first, last, total) {
  for (let attempt = 0; attempt < 3; attempt++) {
    try {
      const response = await fetch(url, {
        headers: { Range: `bytes=${first}-${last}`, 'Accept-Encoding': 'identity' },
        signal: AbortSignal.timeout(12_000)
      });
      const range = /^bytes (\d+)-(\d+)\/(\d+)$/.exec(response.headers.get('content-range') || '');
      if (response.status !== 206 || !range || +range[1] !== first ||
          +range[2] !== last || (total && +range[3] !== total)) {
        await response.body?.cancel();
        throw new Error('Unexpected IPA range.');
      }
      const bytes = Buffer.from(await response.arrayBuffer());
      if (bytes.length !== last - first + 1) throw new Error('Incomplete IPA range.');
      return { bytes, size: +range[3] };
    } catch (error) {
      if (attempt === 2) throw error;
    }
  }
}

function requestedRange(header, size) {
  if (header === undefined) return [0, size - 1];
  const match = /^bytes=(\d*)-(\d*)$/.exec(header);
  if (!match || (!match[1] && !match[2])) return null;
  const first = match[1] ? +match[1] : Math.max(0, size - +match[2]);
  const last = !match[1] || !match[2] ? size - 1 : Math.min(+match[2], size - 1);
  return first <= last ? [first, last] : null;
}

async function* blocks(url, first, last, size, res) {
  for (let offset = first; offset <= last && !res.destroyed;) {
    const pending = [];
    for (let i = 0; i < concurrentBlocks && offset <= last; i++) {
      const end = Math.min(offset + blockSize - 1, last);
      pending.push(readBlock(url, offset, end, size));
      offset = end + 1;
    }
    const batch = await Promise.all(pending);
    for (const block of batch) yield block.bytes;
  }
}

async function serveIpa(req, res, url) {
  let size;
  try {
    ({ size } = await readBlock(url, 0, 0));
  } catch {
    return res.status(502).send('Download indisponível.');
  }
  res.setHeader('Accept-Ranges', 'bytes');
  const range = requestedRange(req.headers.range, size);
  if (!range) {
    res.setHeader('Content-Range', `bytes */${size}`);
    return res.status(416).end();
  }
  const [first, last] = range;
  if (req.headers.range !== undefined) {
    res.status(206);
    res.setHeader('Content-Range', `bytes ${first}-${last}/${size}`);
  }
  res.setHeader('Content-Type', 'application/octet-stream');
  res.setHeader('Content-Length', last - first + 1);
  if (req.method === 'HEAD') return res.end();
  res.flushHeaders();
  try {
    await pipeline(blocks(url, first, last, size, res), res);
  } catch {
    // Let the client resume an incomplete transfer with a new Range request.
    res.destroy();
  }
}

async function serveBlobIpa(req, res, source, signUrl) {
  const range = requestedRange(req.headers.range, source.size);
  res.setHeader('Accept-Ranges', 'bytes');
  if (!range) {
    res.setHeader('Content-Range', `bytes */${source.size}`);
    return res.status(416).end();
  }
  const [first, last] = range;
  const partial = req.headers.range !== undefined;
  const expectedStatus = partial ? 206 : 200;
  const rangeHeader = `bytes ${first}-${last}/${source.size}`;
  const count = last - first + 1;
  let upstream;
  try {
    const method = req.method === 'HEAD' ? 'head' : 'get';
    const url = await signUrl(source.pathname, method);
    const headers = { 'Accept-Encoding': 'identity' };
    if (partial && method === 'get') headers.Range = `bytes=${first}-${last}`;
    upstream = await fetch(url, {
      method: method.toUpperCase(), headers, redirect: 'error', signal: AbortSignal.timeout(180_000)
    });
    const status = method === 'head' ? 200 : expectedStatus;
    const length = method === 'head' ? source.size : count;
    if (upstream.status !== status || +upstream.headers.get('content-length') !== length ||
        (method === 'get' && partial && upstream.headers.get('content-range') !== rangeHeader)) {
      await upstream.body?.cancel();
      return res.status(502).send('Download indisponível.');
    }
  } catch {
    return res.status(502).send('Download indisponível.');
  }
  res.status(expectedStatus);
  res.setHeader('Content-Type', 'application/octet-stream');
  res.setHeader('Content-Length', count);
  if (partial) res.setHeader('Content-Range', rangeHeader);
  if (req.method === 'HEAD') return res.end();
  res.flushHeaders();
  try { await pipeline(Readable.fromWeb(upstream.body), res); }
  catch { res.destroy(); }
}

module.exports = { serveIpa, serveBlobIpa };
