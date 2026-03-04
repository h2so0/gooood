// ──────────────────────────────────────────
// Coupang Partners API fetcher
// ──────────────────────────────────────────

import fetch from "node-fetch";
import * as crypto from "crypto";
import { ProductJson } from "../types";
import { sortByDropRate } from "../utils";
import { mapToAppCategory } from "../classify";

const COUPANG_API_BASE = "https://api-gateway.coupang.com/v2/providers/affiliate_open_api/apis/openapi/v1";

// ── HMAC-SHA256 인증 ──

function generateHmacSignature(
  method: string,
  path: string,
  query: string,
  datetime: string,
  secretKey: string
): string {
  const message = `${datetime}${method}${path}${query}`;
  return crypto
    .createHmac("sha256", secretKey)
    .update(message)
    .digest("hex");
}

function getCoupangDatetime(): string {
  const now = new Date();
  const y = String(now.getUTCFullYear()).slice(2);
  const m = String(now.getUTCMonth() + 1).padStart(2, "0");
  const d = String(now.getUTCDate()).padStart(2, "0");
  const h = String(now.getUTCHours()).padStart(2, "0");
  const mi = String(now.getUTCMinutes()).padStart(2, "0");
  const s = String(now.getUTCSeconds()).padStart(2, "0");
  return `${y}${m}${d}T${h}${mi}${s}Z`;
}

function buildAuthHeader(
  method: string,
  path: string,
  query: string,
  accessKey: string,
  secretKey: string
): string {
  const datetime = getCoupangDatetime();
  const signature = generateHmacSignature(method, path, query, datetime, secretKey);
  return `CEA algorithm=HmacSHA256, access-key=${accessKey}, signed-date=${datetime}, signature=${signature}`;
}

// ── 쿠팡 카테고리 ID → 앱 카테고리 매핑 ──

const COUPANG_BEST_CATEGORIES: { id: number; name: string }[] = [
  { id: 1001, name: "패션의류" },
  { id: 1002, name: "패션잡화" },
  { id: 1010, name: "화장품/미용" },
  { id: 1011, name: "생활/건강" },
  { id: 1013, name: "식품" },
  { id: 1014, name: "출산/육아" },
  { id: 1015, name: "스포츠/레저" },
  { id: 1016, name: "디지털/가전" },
  { id: 1017, name: "가구/인테리어" },
  { id: 1018, name: "생활용품" },
  { id: 1019, name: "반려동물" },
  { id: 1020, name: "식품" },
  { id: 1021, name: "건강식품" },
  { id: 1024, name: "문구/오피스" },
];

// ── Goldbox (골드박스) 데일리딜 ──

interface CoupangGoldboxItem {
  productId?: number;
  productName?: string;
  productPrice?: number;
  productImage?: string;
  productUrl?: string;
  isRocket?: boolean;
  isFreeShipping?: boolean;
  categoryName?: string;
  rank?: number;
  originalPrice?: number;
}

async function fetchCoupangGoldbox(
  accessKey: string,
  secretKey: string
): Promise<ProductJson[]> {
  const products: ProductJson[] = [];

  const path = "/v2/providers/affiliate_open_api/apis/openapi/v1/products/goldbox";
  const query = "subId=gooddeal";
  const method = "GET";

  const authorization = buildAuthHeader(method, path, query, accessKey, secretKey);

  try {
    const url = `${COUPANG_API_BASE}/products/goldbox?subId=gooddeal`;
    const res = await fetch(url, {
      headers: {
        Authorization: authorization,
        "Content-Type": "application/json",
      },
    });

    if (!res.ok) {
      console.error(`[Coupang] Goldbox HTTP ${res.status}: ${await res.text()}`);
      return products;
    }

    const json = (await res.json()) as any;
    const data = json?.data ?? [];

    for (const item of data) {
      const product = parseCoupangProduct(item as CoupangGoldboxItem, undefined, true);
      if (product) products.push(product);
    }

    console.log(`[Coupang] Goldbox: ${products.length} products`);
  } catch (e) {
    console.error("[Coupang] Goldbox error:", e);
  }

  return products;
}

// ── Best Categories ──

async function fetchCoupangBestCategories(
  accessKey: string,
  secretKey: string
): Promise<ProductJson[]> {
  const products: ProductJson[] = [];
  const seenIds = new Set<string>();

  for (const cat of COUPANG_BEST_CATEGORIES) {
    try {
      const path = `/v2/providers/affiliate_open_api/apis/openapi/v1/products/bestcategories/${cat.id}`;
      const query = "subId=gooddeal";
      const method = "GET";

      const authorization = buildAuthHeader(method, path, query, accessKey, secretKey);
      const url = `${COUPANG_API_BASE}/products/bestcategories/${cat.id}?subId=gooddeal`;

      const res = await fetch(url, {
        headers: {
          Authorization: authorization,
          "Content-Type": "application/json",
        },
      });

      if (!res.ok) {
        console.error(`[Coupang] BestCategory ${cat.name} HTTP ${res.status}`);
        continue;
      }

      const json = (await res.json()) as any;
      const data = json?.data ?? [];

      let catCount = 0;
      for (const item of data) {
        const gItem = item as CoupangGoldboxItem;
        const pid = String(gItem.productId ?? "");
        if (!pid || seenIds.has(pid)) continue;
        seenIds.add(pid);

        const product = parseCoupangProduct(gItem, cat.name);
        if (product) {
          products.push(product);
          catCount++;
        }
      }

      console.log(`[Coupang] BestCategory ${cat.name}: ${catCount} products`);
    } catch (e) {
      console.error(`[Coupang] BestCategory ${cat.name} error:`, e);
    }
  }

  return products;
}

// ── 골드박스 종료 시간 (다음 날 오전 7시 KST) ──

function getGoldboxEndTime(): string {
  const now = new Date();
  // 7:00 AM KST = 22:00 UTC (previous day)
  const endUTC = new Date(Date.UTC(
    now.getUTCFullYear(),
    now.getUTCMonth(),
    now.getUTCDate(),
    22, 0, 0, 0
  ));
  // 이미 22:00 UTC 지났으면 (= 7AM KST 지남) 다음 날로
  if (now.getTime() >= endUTC.getTime()) {
    endUTC.setUTCDate(endUTC.getUTCDate() + 1);
  }
  return endUTC.toISOString();
}

// ── 상품 파싱 ──

function parseCoupangProduct(
  item: CoupangGoldboxItem,
  categoryHint?: string,
  isGoldbox = false
): ProductJson | null {
  const productId = item.productId;
  if (!productId) return null;

  const currentPrice = item.productPrice ?? 0;
  if (currentPrice <= 0) return null;

  const originalPrice = item.originalPrice ?? 0;
  const previousPrice = originalPrice > currentPrice ? originalPrice : null;

  let imageUrl = item.productImage || "";
  if (imageUrl.startsWith("//")) imageUrl = "https:" + imageUrl;

  const categoryName = categoryHint || item.categoryName || "쿠팡";

  // mapToAppCategory로 앱 카테고리 매핑 시도
  const catResult = mapToAppCategory(categoryName);
  const category1 = catResult?.category || categoryName;

  return {
    id: `coupang_${productId}`,
    title: item.productName || "",
    link: item.productUrl || `https://www.coupang.com/vp/products/${productId}`,
    imageUrl,
    currentPrice,
    previousPrice,
    mallName: "쿠팡",
    brand: null,
    maker: null,
    category1,
    category2: null,
    category3: null,
    productType: "1",
    reviewScore: null,
    reviewCount: null,
    purchaseCount: null,
    rank: item.rank || null,
    isDeliveryFree: item.isFreeShipping ?? false,
    isArrivalGuarantee: item.isRocket ?? false,
    saleEndDate: isGoldbox ? getGoldboxEndTime() : null,
  };
}

// ── 메인 export ──

export async function fetchCoupangDeals(): Promise<ProductJson[]> {
  const accessKey = (process.env.COUPANG_ACCESS_KEY || "").trim();
  const secretKey = (process.env.COUPANG_SECRET_KEY || "").trim();

  if (!accessKey || !secretKey) {
    console.warn("[Coupang] Missing API keys, skipping");
    return [];
  }

  const products: ProductJson[] = [];

  // 1) Goldbox 데일리딜
  products.push(...await fetchCoupangGoldbox(accessKey, secretKey));
  // 2) Best Categories
  products.push(...await fetchCoupangBestCategories(accessKey, secretKey));

  // Goldbox에서 이미 수집된 상품 dedup
  const seen = new Set<string>();
  const deduped: ProductJson[] = [];
  for (const p of products) {
    if (!seen.has(p.id)) {
      seen.add(p.id);
      deduped.push(p);
    }
  }

  sortByDropRate(deduped);
  console.log(`[Coupang] ${deduped.length} total deals fetched`);
  return deduped;
}
