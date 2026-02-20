export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const key = url.pathname.slice(1); // strip leading /

    // Handle CORS preflight
    if (request.method === "OPTIONS") {
      return new Response(null, { headers: corsHeaders() });
    }

    if (!key) {
      return new Response("Not found", { status: 404, headers: corsHeaders() });
    }

    const object = await env.BUCKET.get(key);
    if (!object) {
      return new Response("Not found", { status: 404, headers: corsHeaders() });
    }

    // Log download event
    env.ANALYTICS.writeDataPoint({
      blobs: [key, request.headers.get("cf-connecting-ip") || "unknown"],
      indexes: [key],
    });

    const headers = new Headers();
    object.writeHttpMetadata(headers);
    headers.set("etag", object.httpEtag);
    // Cache DMGs (large, stable) but not metadata files
    if (key.endsWith(".json") || key.endsWith(".md")) {
      headers.set("cache-control", "no-cache");
    } else {
      headers.set("cache-control", "public, max-age=300");
    }

    if (key.endsWith(".dmg")) {
      headers.set("content-disposition", `attachment; filename="${key.split("/").pop()}"`);
    }

    // CORS
    headers.set("access-control-allow-origin", "*");

    return new Response(object.body, { headers });
  },
};

function corsHeaders() {
  return {
    "access-control-allow-origin": "*",
    "access-control-allow-methods": "GET, OPTIONS",
    "access-control-max-age": "86400",
  };
}
