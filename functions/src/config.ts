// ──────────────────────────────────────────
// Environment variables, constants & config
// ──────────────────────────────────────────

export const NAVER_CLIENT_ID = (process.env.NAVER_CLIENT_ID || "").trim();
export const NAVER_CLIENT_SECRET = (process.env.NAVER_CLIENT_SECRET || "").trim();
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

export const SNXBEST_HEADERS = {
  "User-Agent":
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36",
  Accept: "application/json",
  Referer: "https://snxbest.naver.com/home",
};

export const GIANEX_API_BASE = "https://elsa-fe.gmarket.co.kr/n/home/api/page";

// ── Magic number constants ──

export const AI_FULL_BATCH = 30;
export const AI_SUB_BATCH = 50;
export const FIRESTORE_BATCH_LIMIT = 500;
export const CLEANUP_BATCH_LIMIT = 200;

export const RATE_LIMIT = {
  PRICE_DROP: 14_400_000,      // 4 hours
  CATEGORY_ALERT: 14_400_000,  // 4 hours
  SMART_DIGEST: 86_400_000,    // 1 day
  HOT_DEAL: 14_400_000,        // 4 hours
  SALE_END: 14_400_000,        // 4 hours
  KEYWORD_ALERT: 21_600_000,   // 6 hours
} as const;

export const DELAYS = {
  AI_BATCH: 500,
  AI_SUB_BATCH: 1000,
  FETCH_BETWEEN: 300,
  BEST100_BETWEEN: 500,
  EXTERNAL_BETWEEN: 1000,
} as const;

// ── 피드 소스 쿼터 설정 ──
// maxRatio: 소스가 전체 피드에서 차지할 수 있는 최대 비율
// minRatio: 소스에 최소 보장되는 비율 (상품이 충분할 때)

export const SOURCE_QUOTA: Record<string, { maxRatio: number; minRatio: number }> = {
  best100:      { maxRatio: 0.20, minRatio: 0.05 },
  todayDeal:    { maxRatio: 0.12, minRatio: 0.03 },
  shoppingLive: { maxRatio: 0.08, minRatio: 0.02 },
  naverPromo:   { maxRatio: 0.10, minRatio: 0.02 },
  "11st":       { maxRatio: 0.12, minRatio: 0.06 },
  gmarket:      { maxRatio: 0.12, minRatio: 0.06 },
  auction:      { maxRatio: 0.08, minRatio: 0.03 },
  lotteon:      { maxRatio: 0.10, minRatio: 0.04 },
  ssg:          { maxRatio: 0.10, minRatio: 0.04 },
};

// 네이버 소스 합계 최대 50%
export const NAVER_SOURCES = ["best100", "todayDeal", "shoppingLive", "naverPromo"];
export const NAVER_MAX_TOTAL_RATIO = 0.50;
// 외부 소스 합계 최소 30%
export const EXTERNAL_SOURCES_LIST = ["11st", "gmarket", "auction", "lotteon", "ssg"];
export const EXTERNAL_MIN_TOTAL_RATIO = 0.30;
