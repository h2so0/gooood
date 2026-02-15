// ──────────────────────────────────────────
// Environment variables, constants & config
// ──────────────────────────────────────────

export const NAVER_CLIENT_ID = process.env.NAVER_CLIENT_ID || "";
export const NAVER_CLIENT_SECRET = process.env.NAVER_CLIENT_SECRET || "";
export const NAVER_SHOP_URL = "https://openapi.naver.com/v1/search/shop.json";

export const CATEGORY_MAP: Record<string, string> = {
  "디지털/가전": "50000003",
  "패션의류": "50000000",
  "화장품/미용": "50000002",
  "생활/건강": "50000008",
  "식품": "50000006",
  "스포츠/레저": "50000007",
  "출산/육아": "50000005",
  "패션잡화": "50000001",
  "가구/인테리어": "50000004",
};

export const CATEGORY_NAME_MAP: Record<string, string> = {};
for (const [name, id] of Object.entries(CATEGORY_MAP)) {
  CATEGORY_NAME_MAP[id] = name;
}

export const BEST100_CATEGORIES = ["A", ...Object.values(CATEGORY_MAP)];

export const COMMON_HEADERS = {
  "User-Agent":
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
};

export const GIANEX_API_BASE = "https://elsa-fe.gmarket.co.kr/n/home/api/page";

// ── Magic number constants ──

export const AI_FULL_BATCH = 30;
export const AI_SUB_BATCH = 50;
export const FIRESTORE_BATCH_LIMIT = 500;
export const CLEANUP_BATCH_LIMIT = 200;

export const RATE_LIMIT = {
  PRICE_DROP: 3_600_000,       // 1 hour
  CATEGORY_ALERT: 7_200_000,   // 2 hours
  SMART_DIGEST: 86_400_000,    // 1 day
  HOT_DEAL: 3_600_000,         // 1 hour
  SALE_END: 3_600_000,         // 1 hour
} as const;

export const DELAYS = {
  AI_BATCH: 500,
  AI_SUB_BATCH: 1000,
  FETCH_BETWEEN: 300,
  BEST100_BETWEEN: 500,
  EXTERNAL_BETWEEN: 1000,
} as const;
