/**
 * Sparkle Proxy Worker
 *
 * Proxies requests to Claude, ElevenLabs, and AssemblyAI so the app never
 * ships with raw API keys. Keys are stored as Cloudflare secrets.
 *
 * Auth model: every request must carry a Sparkle bearer token in the
 * `Authorization: Bearer <token>` header. Tokens are generated locally by
 * the desktop app on first launch and persisted in the macOS Keychain.
 * They are NOT proof of identity — they're a TOFU credential that gives the
 * Worker a stable per-install handle for rate limiting and filters out
 * casual probes that send no auth header at all.
 *
 * Rate limits are tracked in KV under per-token, per-day, per-endpoint keys.
 * Limits are configurable via env vars; sensible defaults are baked in.
 *
 * Routes:
 *   POST /chat              → Anthropic Messages API (streaming)
 *   POST /tts               → ElevenLabs TTS API
 *   POST /transcribe-token  → AssemblyAI temporary streaming token
 */

interface Env {
  ANTHROPIC_API_KEY: string;
  ELEVENLABS_API_KEY: string;
  ELEVENLABS_VOICE_ID: string;
  ASSEMBLYAI_API_KEY: string;
  WEB_SEARCH_DAILY_LIMIT?: string;
  CHAT_DAILY_LIMIT?: string;
  TTS_DAILY_LIMIT?: string;
  TRANSCRIBE_DAILY_LIMIT?: string;
  RATE_LIMIT_KV?: KvNamespace;
}

interface KvNamespace {
  get(key: string): Promise<string | null>;
  put(
    key: string,
    value: string,
    options?: { expirationTtl?: number }
  ): Promise<void>;
}

// Token format. Bumping the version (v1 → v2) lets us reject older
// generations after a leak. The app side mirrors this prefix.
const SPARKLE_TOKEN_PREFIX = "sparkle_v1_";
// 32 random bytes, hex-encoded → 64 hex characters.
const SPARKLE_TOKEN_SUFFIX_LENGTH = 64;
const SPARKLE_TOKEN_SUFFIX_REGEX = /^[0-9a-f]{64}$/;

// Default daily caps per install. Generous enough that a normal user never
// hits them, tight enough that a leaked token can't drain the API budget.
const DEFAULT_CHAT_DAILY_LIMIT = 200;
const DEFAULT_TTS_DAILY_LIMIT = 1000;
const DEFAULT_TRANSCRIBE_DAILY_LIMIT = 200;
const DEFAULT_WEB_SEARCH_DAILY_LIMIT = 20;

const WEB_SEARCH_TOOL_TYPE = "web_search_20250305";
const WEB_SEARCH_TOOL_NAME = "web_search";

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);

    if (request.method !== "POST") {
      return new Response("Method not allowed", { status: 405 });
    }

    // All endpoints require a valid Sparkle bearer token. Rejecting early
    // keeps unauthenticated probes from touching upstream APIs at all.
    const authResult = authenticateSparkleClient(request);
    if (!authResult.ok) {
      return authResult.response;
    }
    const sparkleClientToken = authResult.clientToken;

    try {
      if (url.pathname === "/chat") {
        return await handleChat(request, env, sparkleClientToken);
      }

      if (url.pathname === "/tts") {
        return await handleTTS(request, env, sparkleClientToken);
      }

      if (url.pathname === "/transcribe-token") {
        return await handleTranscribeToken(env, sparkleClientToken);
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

// MARK: - Authentication

interface AuthSuccess {
  ok: true;
  clientToken: string;
}

interface AuthFailure {
  ok: false;
  response: Response;
}

/**
 * Validates the Sparkle bearer token format. Returns the raw token on
 * success so downstream rate limiters can use it as their cache key.
 *
 * We deliberately accept any token whose shape matches `sparkle_v1_<64hex>`
 * — there's no enrolled-client list. The token's only job is to be a
 * stable, per-install identifier that an attacker can't guess. Real
 * identity attestation would require Apple App Attest, which is out of
 * scope.
 */
function authenticateSparkleClient(request: Request): AuthSuccess | AuthFailure {
  const authorizationHeader = request.headers.get("authorization") ?? "";
  const bearerPrefix = "Bearer ";

  if (!authorizationHeader.startsWith(bearerPrefix)) {
    return {
      ok: false,
      response: jsonResponse(
        { error: "Missing or malformed Authorization header" },
        401
      ),
    };
  }

  const presentedToken = authorizationHeader.slice(bearerPrefix.length).trim();
  if (!presentedToken.startsWith(SPARKLE_TOKEN_PREFIX)) {
    return {
      ok: false,
      response: jsonResponse(
        { error: "Unrecognized Sparkle token version" },
        401
      ),
    };
  }

  const tokenSuffix = presentedToken.slice(SPARKLE_TOKEN_PREFIX.length);
  if (
    tokenSuffix.length !== SPARKLE_TOKEN_SUFFIX_LENGTH ||
    !SPARKLE_TOKEN_SUFFIX_REGEX.test(tokenSuffix)
  ) {
    return {
      ok: false,
      response: jsonResponse({ error: "Invalid Sparkle token format" }, 401),
    };
  }

  return { ok: true, clientToken: presentedToken };
}

// MARK: - /chat

async function handleChat(
  request: Request,
  env: Env,
  sparkleClientToken: string
): Promise<Response> {
  const originalBody = await request.text();

  // Per-install daily cap on /chat. Counts every chat call (voice +
  // background metadata) so a runaway loop in the app can't blow the
  // budget either. Web-search-enabled requests are also counted against
  // this cap — they're chat calls too.
  const chatRateLimitDecision = await applyEndpointRateLimit({
    env,
    sparkleClientToken,
    endpointName: "chat",
    dailyLimit: parsePositiveInteger(
      env.CHAT_DAILY_LIMIT,
      DEFAULT_CHAT_DAILY_LIMIT
    ),
  });
  if (chatRateLimitDecision instanceof Response) {
    return chatRateLimitDecision;
  }

  const rateLimitedBody = await applyWebSearchRateLimit(
    env,
    sparkleClientToken,
    originalBody
  );
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

// MARK: - Web Search Rate Limit (per-token)

/**
 * Strips the web_search tool from prompts that don't actually need a web
 * search, and applies a separate per-token daily cap on prompts that do.
 * Web searches cost extra ($10 per 1,000), so we keep this layer tight even
 * within an install's broader chat budget.
 */
async function applyWebSearchRateLimit(
  env: Env,
  sparkleClientToken: string,
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

  const kvNamespace = env.RATE_LIMIT_KV;
  if (!kvNamespace) {
    console.error("[/chat] Web search requested but RATE_LIMIT_KV is not configured");
    return jsonResponse(
      { error: "Web search rate limiting is not configured" },
      503
    );
  }

  const dailyLimit = parsePositiveInteger(
    env.WEB_SEARCH_DAILY_LIMIT,
    DEFAULT_WEB_SEARCH_DAILY_LIMIT
  );
  const rateLimitKey = await buildPerTokenRateLimitKey(
    "web-search",
    sparkleClientToken
  );
  const currentCount = parsePositiveInteger(
    await kvNamespace.get(rateLimitKey),
    0
  );
  const secondsUntilTomorrowUTC = getSecondsUntilTomorrowUTC();

  if (currentCount >= dailyLimit) {
    return jsonResponse(
      {
        error: "Daily web search limit reached",
        limit: dailyLimit,
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

function removeWebSearchTool(
  parsedBody: Record<string, unknown>
): Record<string, unknown> {
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

// MARK: - Generic Per-Endpoint Rate Limiter

/**
 * Counts a request against the daily budget for a given endpoint and
 * returns either a 429 Response (if the budget is exhausted) or `null`
 * (to mean "allowed"). The counter is stored in KV under a per-token key
 * that expires after the UTC day rolls over.
 *
 * If KV is unavailable we fail open — better to let the request through
 * than reject every legitimate user during a binding misconfiguration.
 */
async function applyEndpointRateLimit(args: {
  env: Env;
  sparkleClientToken: string;
  endpointName: string;
  dailyLimit: number;
}): Promise<Response | null> {
  const { env, sparkleClientToken, endpointName, dailyLimit } = args;

  const kvNamespace = env.RATE_LIMIT_KV;
  if (!kvNamespace) {
    console.error(
      `[/${endpointName}] RATE_LIMIT_KV not configured — request allowed without metering`
    );
    return null;
  }

  const rateLimitKey = await buildPerTokenRateLimitKey(
    endpointName,
    sparkleClientToken
  );
  const currentCount = parsePositiveInteger(
    await kvNamespace.get(rateLimitKey),
    0
  );
  const secondsUntilTomorrowUTC = getSecondsUntilTomorrowUTC();

  if (currentCount >= dailyLimit) {
    return jsonResponse(
      {
        error: `Daily ${endpointName} limit reached`,
        limit: dailyLimit,
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

  return null;
}

/**
 * Builds the KV key for a per-token, per-day, per-endpoint counter. The
 * token is hashed (not stored raw) so KV dumps never expose credentials.
 */
async function buildPerTokenRateLimitKey(
  endpointName: string,
  sparkleClientToken: string
): Promise<string> {
  const hashedClientToken = await sha256Hex(sparkleClientToken);
  const todayUTC = new Date().toISOString().slice(0, 10);
  return `${endpointName}:${todayUTC}:${hashedClientToken}`;
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

// MARK: - /transcribe-token

async function handleTranscribeToken(
  env: Env,
  sparkleClientToken: string
): Promise<Response> {
  const transcribeRateLimitDecision = await applyEndpointRateLimit({
    env,
    sparkleClientToken,
    endpointName: "transcribe",
    dailyLimit: parsePositiveInteger(
      env.TRANSCRIBE_DAILY_LIMIT,
      DEFAULT_TRANSCRIBE_DAILY_LIMIT
    ),
  });
  if (transcribeRateLimitDecision instanceof Response) {
    return transcribeRateLimitDecision;
  }

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

// MARK: - /tts

async function handleTTS(
  request: Request,
  env: Env,
  sparkleClientToken: string
): Promise<Response> {
  const ttsRateLimitDecision = await applyEndpointRateLimit({
    env,
    sparkleClientToken,
    endpointName: "tts",
    dailyLimit: parsePositiveInteger(
      env.TTS_DAILY_LIMIT,
      DEFAULT_TTS_DAILY_LIMIT
    ),
  });
  if (ttsRateLimitDecision instanceof Response) {
    return ttsRateLimitDecision;
  }

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
