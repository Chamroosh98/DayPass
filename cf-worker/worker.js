/**
 * DayPass - OpenWrt package mirror (Cloudflare Worker)
 *
 * Reverse-proxies downloads.openwrt.org so opkg / apk on the router can
 * fetch packages through the Cloudflare edge.
 *
 * Deployed by modules/network/relays/cloudflare/worker.sh as the script
 * "daypass-mirror"; worker.sh recognises a genuine deployment through
 * GET /daypass-health.
 */

const MIRROR_ID = 'daypass-openwrt';
const MIRROR_VERSION = '2.0.0';
const UPSTREAM_HOST = 'downloads.openwrt.org';
const HEALTH_PATH = '/daypass-health';
const MODULE_NAME = 'worker.js';

// Package payloads never change once published, so they can sit in the
// edge cache for a long time.
const IMMUTABLE_RE = /\.(ipk|apk)$/i;
const IMMUTABLE_TTL = 2592000; // 30 days

// Indexes, signatures and checksums must stay fresh: a stale index and a
// fresh package feed make opkg/apk fail with a hash mismatch.
const VOLATILE_RE = /(^|\/)(Packages(\.gz|\.sig)?|APKINDEX\.tar\.gz|index\.json|sha256sums(\.asc|\.sig)?|.*\.(sig|pub|asc|manifest))$/i;
const VOLATILE_TTL = 300; // 5 minutes

// Request headers worth forwarding upstream. Everything else (cookies,
// authorization, CF internals) is dropped so the cache key stays stable
// and nothing client-specific leaks to the origin.
const FORWARD_HEADERS = [
    'range',
    'if-range',
    'if-none-match',
    'if-modified-since',
    'accept',
    'accept-encoding',
    'user-agent',
];

const CORS_HEADERS = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, HEAD, OPTIONS',
    'Access-Control-Allow-Headers':
        'Range, If-Range, If-None-Match, If-Modified-Since, Accept, Accept-Encoding, User-Agent',
    'Access-Control-Expose-Headers':
        'Accept-Ranges, Content-Range, Content-Length, Content-Encoding, ETag, Last-Modified, X-DayPass-Cache',
    'Access-Control-Max-Age': '86400',
};

// Statuses that must be sent without a body.
const BODYLESS_STATUS = new Set([204, 205, 304]);

function withCors(headers) {
    for (const [name, value] of Object.entries(CORS_HEADERS)) {
        headers.set(name, value);
    }
    return headers;
}

function jsonResponse(payload, status, extra) {
    const headers = withCors(
        new Headers({
            'Content-Type': 'application/json; charset=utf-8',
            'Cache-Control': 'no-store',
            'X-DayPass-Mirror': MIRROR_ID,
            ...extra,
        }),
    );
    return new Response(`${JSON.stringify(payload)}\n`, { status, headers });
}

/**
 * Identity endpoint. worker.sh probes this to tell a real DayPass mirror
 * apart from any other host the user may have typed in.
 */
function healthResponse(request) {
    return jsonResponse(
        {
            status: 'ok',
            mirror: MIRROR_ID,
            version: MIRROR_VERSION,
            upstream: UPSTREAM_HOST,
            colo: (request.cf && request.cf.colo) || null,
            time: new Date().toISOString(),
        },
        200,
    );
}

/** How long the edge may keep this path, and whether it is immutable. */
function cachePolicy(pathname) {
    if (IMMUTABLE_RE.test(pathname)) {
        return { ttl: IMMUTABLE_TTL, immutable: true, storable: true };
    }
    if (VOLATILE_RE.test(pathname)) {
        return { ttl: VOLATILE_TTL, immutable: false, storable: false };
    }
    return { ttl: VOLATILE_TTL, immutable: false, storable: false };
}

function upstreamUrl(request) {
    const url = new URL(request.url);
    url.protocol = 'https:';
    url.hostname = UPSTREAM_HOST;
    url.port = '';
    return url;
}

function buildUpstreamRequest(request, url) {
    const headers = new Headers();
    for (const name of FORWARD_HEADERS) {
        const value = request.headers.get(name);
        if (value) headers.set(name, value);
    }

    // GET upstream even for HEAD: Cloudflare answers the client's HEAD
    // from it and the response stays cacheable.
    return new Request(url.toString(), {
        method: 'GET',
        headers,
        redirect: 'follow',
    });
}

/**
 * Copies the upstream response and streams its body straight through, so
 * a 300 MB package never lands in the Worker's memory.
 */
function proxyResponse(request, upstream, policy, cacheState) {
    const headers = withCors(new Headers(upstream.headers));

    headers.set('X-DayPass-Mirror', MIRROR_ID);
    headers.set('X-DayPass-Cache', cacheState);
    headers.delete('Set-Cookie');

    if (upstream.status === 200 || upstream.status === 206) {
        headers.set('Accept-Ranges', 'bytes');
    }

    if (policy.immutable && upstream.status === 200) {
        headers.set('Cache-Control', `public, max-age=${policy.ttl}, immutable`);
    } else if (upstream.status === 200 || upstream.status === 206) {
        headers.set('Cache-Control', `public, max-age=${policy.ttl}, must-revalidate`);
    }

    // 304 and friends must not carry a body, and a HEAD answer has none.
    const body =
        BODYLESS_STATUS.has(upstream.status) || request.method === 'HEAD'
            ? null
            : upstream.body;

    return new Response(body, {
        status: upstream.status,
        statusText: upstream.statusText,
        headers,
    });
}

/** One retry, so a single upstream hiccup does not fail a long install. */
async function fetchUpstream(upstreamRequest, ttl) {
    const options = { cf: { cacheEverything: true, cacheTtl: ttl } };

    try {
        return await fetch(upstreamRequest.clone(), options);
    } catch (err) {
        return await fetch(upstreamRequest, options);
    }
}

export default {
    async fetch(request, env, ctx) {
        const url = new URL(request.url);

        if (request.method === 'OPTIONS') {
            return new Response(null, {
                status: 204,
                headers: withCors(new Headers({ 'Cache-Control': 'no-store' })),
            });
        }

        if (url.pathname === HEALTH_PATH || url.pathname === `${HEALTH_PATH}/`) {
            return healthResponse(request);
        }

        if (request.method !== 'GET' && request.method !== 'HEAD') {
            return jsonResponse(
                { status: 'error', mirror: MIRROR_ID, error: 'method not allowed' },
                405,
                { Allow: 'GET, HEAD, OPTIONS' },
            );
        }

        const target = upstreamUrl(request);
        const policy = cachePolicy(target.pathname);
        const isRange = request.headers.has('Range');
        const cache = caches.default;

        // The Cache API cannot slice a stored body, so it is used only for
        // whole-file GETs of package payloads. Range requests (opkg/curl
        // resuming a download) go to fetch() with cacheEverything, which is
        // Cloudflare's HTTP cache and does serve 206 from a cached object.
        const useCacheApi =
            policy.storable && policy.immutable && request.method === 'GET' && !isRange;
        const cacheKey = new Request(target.toString(), { method: 'GET' });

        if (useCacheApi) {
            const hit = await cache.match(cacheKey);
            if (hit) {
                const headers = withCors(new Headers(hit.headers));
                headers.set('X-DayPass-Mirror', MIRROR_ID);
                headers.set('X-DayPass-Cache', 'HIT');
                headers.set('Accept-Ranges', 'bytes');
                return new Response(hit.body, {
                    status: hit.status,
                    statusText: hit.statusText,
                    headers,
                });
            }
        }

        let upstream;
        try {
            upstream = await fetchUpstream(buildUpstreamRequest(request, target), policy.ttl);
        } catch (err) {
            return jsonResponse(
                {
                    status: 'error',
                    mirror: MIRROR_ID,
                    error: 'upstream unreachable',
                    detail: String((err && err.message) || err),
                },
                502,
            );
        }

        const response = proxyResponse(request, upstream, policy, useCacheApi ? 'MISS' : 'EDGE');

        if (useCacheApi && upstream.status === 200) {
            // clone() tees the stream: one copy goes to the client while
            // the other is written to the cache in the background.
            ctx.waitUntil(cache.put(cacheKey, response.clone()));
        }

        return response;
    },
};

export { MIRROR_ID, MIRROR_VERSION, MODULE_NAME, UPSTREAM_HOST, HEALTH_PATH };
