/**
 * Sparkle Proxy Worker
 *
 * Proxies requests to Claude and ElevenLabs APIs so the app never
 * ships with raw API keys. Keys are stored as Cloudflare secrets.
 *
 * Routes:
 *   POST /chat  → Anthropic Messages API (streaming)
 *   POST /tts   → ElevenLabs TTS API
 */

interface Env {
  ANTHROPIC_API_KEY: string;
  ELEVENLABS_API_KEY: string;
  ELEVENLABS_VOICE_ID: string;
  ASSEMBLYAI_API_KEY: string;
  WEB_SEARCH_DAILY_LIMIT?: string;
  WEB_SEARCH_RATE_LIMIT_KV?: {
    get(key: string): Promise<string | null>;
    put(key: string, value: string, options?: { expirationTtl?: number }): Promise<void>;
  };
}

const DEFAULT_WEB_SEARCH_DAILY_LIMIT = 20;
const WEB_SEARCH_TOOL_TYPE = "web_search_20250305";
const WEB_SEARCH_TOOL_NAME = "web_search";

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);

    if (request.method !== "POST") {
      return new Response("Method not allowed", { status: 405 });
    }

    try {
      if (url.pathname === "/chat") {
        return await handleChat(request, env);
      }

      if (url.pathname === "/tts") {
        return await handleTTS(request, env);
      }

      if (url.pathname === "/transcribe-token") {
        return await handleTranscribeToken(env);
      }
    } catch (error) {
      console.error(`[${url.pathname}] Unhandled error:`, error);
      return new Response(
        JSON.stringify({ error: String(error) }),
        { status: 500, headers: { "content-type": "application/json" } }
      );
    }

    return new Response("Not found", { status: 404 });
  },
};

async function handleChat(request: Request, env: Env): Promise<Response> {
  const originalBody = await request.text();
  const rateLimitedBody = await applyWebSearchRateLimit(request, env, originalBody);
  if (rateLimitedBody instanceof Response) {
    return rateLimitedBody;
  }

  const response = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "x-api-key": env.ANTHROPIC_API_KEY,
      "anthropic-version": "2023-06-01",
      "content-type": "application/json",
    },
    body: rateLimitedBody,
  });

  if (!response.ok) {
    const errorBody = await response.text();
    console.error(`[/chat] Anthropic API error ${response.status}: ${errorBody}`);
    return new Response(errorBody, {
      status: response.status,
      headers: { "content-type": "application/json" },
    });
  }

  return new Response(response.body, {
    status: response.status,
    headers: {
      "content-type": response.headers.get("content-type") || "text/event-stream",
      "cache-control": "no-cache",
    },
  });
}

async function applyWebSearchRateLimit(
  request: Request,
  env: Env,
  body: string
): Promise<string | Response> {
  let parsedBody: unknown;
  try {
    parsedBody = JSON.parse(body);
  } catch {
    return body;
  }

  if (!isRecord(parsedBody) || !bodyIncludesWebSearchTool(parsedBody)) {
    return body;
  }

  const latestUserText = extractLatestUserText(parsedBody);
  const hasWebSearchIntent = promptLooksLikeWebSearchRequest(latestUserText);
  if (!hasWebSearchIntent) {
    const bodyWithoutWebSearch = removeWebSearchTool(parsedBody);
    return JSON.stringify(bodyWithoutWebSearch);
  }

  const kvNamespace = env.WEB_SEARCH_RATE_LIMIT_KV;
  if (!kvNamespace) {
    console.error("[/chat] Web search requested but WEB_SEARCH_RATE_LIMIT_KV is not configured");
    return jsonResponse(
      { error: "Web search rate limiting is not configured" },
      503
    );
  }

  const rateLimit = parsePositiveInteger(
    env.WEB_SEARCH_DAILY_LIMIT,
    DEFAULT_WEB_SEARCH_DAILY_LIMIT
  );
  const rateLimitKey = await buildWebSearchRateLimitKey(request);
  const currentCount = parsePositiveInteger(await kvNamespace.get(rateLimitKey), 0);
  const secondsUntilTomorrowUTC = getSecondsUntilTomorrowUTC();

  if (currentCount >= rateLimit) {
    return jsonResponse(
      {
        error: "Daily web search limit reached",
        limit: rateLimit,
        retryAfterSeconds: secondsUntilTomorrowUTC,
      },
      429,
      { "retry-after": String(secondsUntilTomorrowUTC) }
    );
  }

  await kvNamespace.put(
    rateLimitKey,
    String(currentCount + 1),
    { expirationTtl: secondsUntilTomorrowUTC + 60 }
  );

  return body;
}

function bodyIncludesWebSearchTool(parsedBody: Record<string, unknown>): boolean {
  const tools = parsedBody.tools;
  if (!Array.isArray(tools)) {
    return false;
  }

  return tools.some((tool) => {
    if (!isRecord(tool)) {
      return false;
    }
    return tool.type === WEB_SEARCH_TOOL_TYPE || tool.name === WEB_SEARCH_TOOL_NAME;
  });
}

function removeWebSearchTool(parsedBody: Record<string, unknown>): Record<string, unknown> {
  const copiedBody = { ...parsedBody };
  const tools = copiedBody.tools;
  if (!Array.isArray(tools)) {
    return copiedBody;
  }

  const filteredTools = tools.filter((tool) => {
    if (!isRecord(tool)) {
      return true;
    }
    return tool.type !== WEB_SEARCH_TOOL_TYPE && tool.name !== WEB_SEARCH_TOOL_NAME;
  });

  if (filteredTools.length === 0) {
    delete copiedBody.tools;
  } else {
    copiedBody.tools = filteredTools;
  }

  return copiedBody;
}

function extractLatestUserText(parsedBody: Record<string, unknown>): string {
  const messages = parsedBody.messages;
  if (!Array.isArray(messages)) {
    return "";
  }

  for (let messageIndex = messages.length - 1; messageIndex >= 0; messageIndex -= 1) {
    const message = messages[messageIndex];
    if (!isRecord(message) || message.role !== "user") {
      continue;
    }

    return extractTextFromMessageContent(message.content);
  }

  return "";
}

function extractTextFromMessageContent(content: unknown): string {
  if (typeof content === "string") {
    return content;
  }

  if (!Array.isArray(content)) {
    return "";
  }

  return content
    .map((contentBlock) => {
      if (!isRecord(contentBlock) || contentBlock.type !== "text") {
        return "";
      }
      return typeof contentBlock.text === "string" ? contentBlock.text : "";
    })
    .filter((text) => text.length > 0)
    .join("\n");
}

function promptLooksLikeWebSearchRequest(prompt: string): boolean {
  const normalizedPrompt = prompt.toLowerCase();
  return [
    "latest",
    "news",
    "current",
    "today",
    "this week",
    "recent",
    "look up",
    "lookup",
    "search",
    "check online",
    "on the web",
    "weather",
    "price",
    "stock",
    "score",
    "release date",
    "announced",
    "announcement",
  ].some((signal) => normalizedPrompt.includes(signal));
}

async function buildWebSearchRateLimitKey(request: Request): Promise<string> {
  const clientIdentifier =
    request.headers.get("cf-connecting-ip") ||
    request.headers.get("x-forwarded-for")?.split(",")[0]?.trim() ||
    "unknown-client";
  const hashedClientIdentifier = await sha256Hex(clientIdentifier);
  const todayUTC = new Date().toISOString().slice(0, 10);
  return `web-search:${todayUTC}:${hashedClientIdentifier}`;
}

async function sha256Hex(value: string): Promise<string> {
  const valueBytes = new TextEncoder().encode(value);
  const hashBuffer = await crypto.subtle.digest("SHA-256", valueBytes);
  return Array.from(new Uint8Array(hashBuffer))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

function getSecondsUntilTomorrowUTC(): number {
  const now = new Date();
  const tomorrowUTC = Date.UTC(
    now.getUTCFullYear(),
    now.getUTCMonth(),
    now.getUTCDate() + 1
  );
  return Math.max(60, Math.ceil((tomorrowUTC - now.getTime()) / 1000));
}

function parsePositiveInteger(value: string | null | undefined, fallback: number): number {
  if (!value) {
    return fallback;
  }

  const parsedValue = Number.parseInt(value, 10);
  if (!Number.isFinite(parsedValue) || parsedValue < 0) {
    return fallback;
  }

  return parsedValue;
}

function jsonResponse(
  body: Record<string, unknown>,
  status: number,
  headers: Record<string, string> = {}
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "content-type": "application/json",
      ...headers,
    },
  });
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

async function handleTranscribeToken(env: Env): Promise<Response> {
  const response = await fetch(
    "https://streaming.assemblyai.com/v3/token?expires_in_seconds=480",
    {
      method: "GET",
      headers: {
        authorization: env.ASSEMBLYAI_API_KEY,
      },
    }
  );

  if (!response.ok) {
    const errorBody = await response.text();
    console.error(`[/transcribe-token] AssemblyAI token error ${response.status}: ${errorBody}`);
    return new Response(errorBody, {
      status: response.status,
      headers: { "content-type": "application/json" },
    });
  }

  const data = await response.text();
  return new Response(data, {
    status: 200,
    headers: { "content-type": "application/json" },
  });
}

async function handleTTS(request: Request, env: Env): Promise<Response> {
  const body = await request.text();
  const voiceId = env.ELEVENLABS_VOICE_ID;

  const response = await fetch(
    `https://api.elevenlabs.io/v1/text-to-speech/${voiceId}`,
    {
      method: "POST",
      headers: {
        "xi-api-key": env.ELEVENLABS_API_KEY,
        "content-type": "application/json",
        accept: "audio/mpeg",
      },
      body,
    }
  );

  if (!response.ok) {
    const errorBody = await response.text();
    console.error(`[/tts] ElevenLabs API error ${response.status}: ${errorBody}`);
    return new Response(errorBody, {
      status: response.status,
      headers: { "content-type": "application/json" },
    });
  }

  return new Response(response.body, {
    status: response.status,
    headers: {
      "content-type": response.headers.get("content-type") || "audio/mpeg",
    },
  });
}
