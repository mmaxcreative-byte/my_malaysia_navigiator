// Cloudflare Worker. Set TOLLGURU_API_KEY as a Worker secret.
const api = 'https://apis.tollguru.com/toll/v2/complete-polyline-from-mapping-service';
const maxPolylineLength = 250_000;

export default {
  async fetch(request, env) {
    if (request.method !== 'POST') {
      return new Response(null, { status: 405, headers: { Allow: 'POST' } });
    }

    let polyline;
    try {
      const body = await request.json();
      polyline = body?.polyline;
    } catch {
      return new Response(null, { status: 400 });
    }
    if (typeof polyline !== 'string' || polyline.length < 4 ||
        polyline.length > maxPolylineLength || !/^[?-~]+$/.test(polyline)) {
      return new Response(null, { status: 400 });
    }
    if (!env.TOLLGURU_API_KEY) return new Response(null, { status: 503 });

    try {
      const response = await fetch(api, {
        method: 'POST',
        redirect: 'error',
        headers: {
          'Content-Type': 'application/json',
          'x-api-key': env.TOLLGURU_API_KEY,
        },
        body: JSON.stringify({
          mapProvider: 'mapbox',
          polyline,
          vehicle: { type: '2AxlesAuto' },
        }),
        signal: AbortSignal.timeout(8_000),
      });
      if (!response.ok) return new Response(null, { status: 502 });
      const body = await response.json();
      const { route, summary } = body;
      const amount = route?.hasTolls === false
        ? 0
        : route?.costs?.minimumTollCost;
      if (body.status?.toUpperCase() !== 'OK' || summary?.currency !== 'MYR' ||
          !Number.isFinite(amount) || amount < 0 ||
          (amount === 0 && route?.hasTolls !== false)) {
        return new Response(null, { status: 422 });
      }
      return Response.json({ currency: 'MYR', amount });
    } catch {
      return new Response(null, { status: 502 });
    }
  },
};
