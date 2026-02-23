// ──────────────────────────────────────────
// SSG.COM (쓱닷컴) deal fetcher
// ──────────────────────────────────────────

import fetch from "node-fetch";
import { ProductJson } from "../types";
import { COMMON_HEADERS, DELAYS } from "../config";
import { sleep, sortByDropRate } from "../utils";

const SSG_HEADERS = {
  ...COMMON_HEADERS,
  "Content-Type": "application/json",
  Origin: "https://www.ssg.com",
  Referer: "https://www.ssg.com/page/pc/SpecialPrice.ssg",
};

function ssgTimestamp(): string {
  const now = new Date();
  const y = now.getFullYear();
  const m = String(now.getMonth() + 1).padStart(2, "0");
  const d = String(now.getDate()).padStart(2, "0");
  const h = String(now.getHours()).padStart(2, "0");
  const mi = String(now.getMinutes()).padStart(2, "0");
  const s = String(now.getSeconds()).padStart(2, "0");
  return `${y}${m}${d}${h}${mi}${s}`;
}

function ssgCommonBody() {
  return {
    common: {
      aplVer: "",
      osCd: "",
      ts: ssgTimestamp(),
      mobilAppNo: "99",
      dispDvicDivCd: "10",
      viewSiteNo: "6005",
    },
  };
}

interface SsgItem {
  itemId?: string;
  itemNm?: string;
  displayPrc?: string;
  strikeOutPrc?: string;
  priceInfo?: {
    summary?: {
      discountTxt?: string;
    };
  };
  itemLnkd?: string;
  itemImgUrl?: string;
  brandNm?: string;
  soldOutYn?: string;
  dispStrtDts?: string;
  dispEndDts?: string;
  shppcstInfo?: { dispTxt?: string }[];
  recompPoint?: number;
  recomRegCnt?: number;
}

function parseSsgProduct(
  item: SsgItem,
  seenIds: Set<string>,
  categoryHint?: string
): ProductJson | null {
  const itemId = item.itemId;
  if (!itemId || seenIds.has(itemId)) return null;
  if (item.soldOutYn === "Y") return null;

  seenIds.add(itemId);

  const currentPrice = parseInt(
    (item.displayPrc || "0").replace(/,/g, ""),
    10
  );
  if (currentPrice <= 0) return null;

  const strikeOutPrice = parseInt(
    (item.strikeOutPrc || "0").replace(/,/g, ""),
    10
  );
  const previousPrice =
    strikeOutPrice > currentPrice ? strikeOutPrice : null;

  let imgUrl = item.itemImgUrl || "";
  if (imgUrl.startsWith("//")) imgUrl = "https:" + imgUrl;

  const isFreeShipping = (item.shppcstInfo || []).some(
    (s) => (s.dispTxt || "").includes("무료배송")
  );

  let saleEndDate: string | null = null;
  if (item.dispEndDts) {
    // "YYYYMMDDHHmmss" → ISO
    const s = item.dispEndDts;
    if (s.length >= 14) {
      saleEndDate = `${s.slice(0, 4)}-${s.slice(4, 6)}-${s.slice(6, 8)}T${s.slice(8, 10)}:${s.slice(10, 12)}:${s.slice(12, 14)}`;
    }
  }

  return {
    id: `ssg_${itemId}`,
    title: item.itemNm || "",
    link: item.itemLnkd || `https://www.ssg.com/item/itemView.ssg?itemId=${itemId}`,
    imageUrl: imgUrl,
    currentPrice,
    previousPrice,
    mallName: "SSG",
    brand: item.brandNm || null,
    maker: null,
    category1: categoryHint || "SSG",
    category2: null,
    category3: null,
    productType: "1",
    reviewScore: item.recompPoint || null,
    reviewCount: item.recomRegCnt || null,
    purchaseCount: null,
    rank: null,
    isDeliveryFree: isFreeShipping,
    isArrivalGuarantee: false,
    saleEndDate,
  };
}

function extractItems(json: any): SsgItem[] {
  const items: SsgItem[] = [];
  const areaList = json?.data?.areaList ?? [];
  for (const area of areaList) {
    // area can be a dict with itemList, or a nested array of dicts
    if (Array.isArray(area)) {
      for (const inner of area) {
        for (const item of inner?.itemList ?? []) {
          items.push(item);
        }
      }
    } else {
      for (const item of area?.itemList ?? []) {
        items.push(item);
      }
    }
  }
  for (const item of json?.data?.itemList ?? []) {
    items.push(item);
  }
  return items;
}

async function fetchPageArea(
  pageId: string,
  pageSetId: string,
  pageCmptId: string,
  dispCtgId: string,
  seenIds: Set<string>,
  categoryHint?: string
): Promise<ProductJson[]> {
  const products: ProductJson[] = [];
  try {
    const body = {
      ...ssgCommonBody(),
      params: {
        pageId,
        pageSetId,
        pageCmptId,
        dispDvicDivCd: "10",
        viewSiteNo: "6005",
        dispCtgId,
        pageNo: 1,
        pageSize: 100,
      },
    };

    const res = await fetch(
      "https://frontapi.ssg.com/dp/api/v2/page/area",
      {
        method: "POST",
        headers: SSG_HEADERS,
        body: JSON.stringify(body),
      }
    );
    if (!res.ok) {
      console.log(`[SSG] pageArea ${pageId}/${dispCtgId}: HTTP ${res.status}`);
      return products;
    }

    const json = (await res.json()) as any;
    const rawItems = extractItems(json);
    for (const item of rawItems) {
      const product = parseSsgProduct(item, seenIds, categoryHint);
      if (product) products.push(product);
    }
    console.log(`[SSG] pageArea ${pageId}/${dispCtgId}: ${rawItems.length} raw, ${products.length} new`);
  } catch (e) {
    console.error(`[SSG] pageArea ${pageId}/${dispCtgId} error:`, e);
  }
  return products;
}

// ── SSG 카테고리 ID → 한글 카테고리명 (mapToAppCategory 키워드 매칭용) ──
const SSG_CATEGORY_NAMES: Record<string, string> = {
  "5410000001": "패션의류",
  "1000015891": "패션잡화",
  "5410000002": "뷰티",
  "5410000006": "스포츠/레저",
  "5410000003": "생활/주방",
  "1000015890": "가구/인테리어",
  "5410000004": "유아동",
  "5410000005": "디지털/렌탈",
  "5410000007": "신선식품",
  "1000015925": "가공/건강식품",
  "5000016005": "",       // 전체
  "5000016021": "패션의류",
  "6000060708": "패션잡화",
  "5000016022": "뷰티",
  "5000016044": "스포츠/레저",
  "5000016030": "생활/주방",
  "6000060709": "가구/인테리어",
  "5000016039": "유아동",
  "5000016040": "디지털/렌탈",
  "6000078977": "신선식품",
  "6000078978": "가공/건강식품",
};

// ── 쓱특가 카테고리 IDs ──
const SPECIAL_CATEGORIES = [
  "",             // 전체
  "5410000001",   // 패션의류
  "1000015891",   // 패션잡화
  "5410000002",   // 뷰티
  "5410000006",   // 스포츠/레저
  "5410000003",   // 생활/주방
  "1000015890",   // 가구/인테리어
  "5410000004",   // 유아동
  "5410000005",   // 디지털/렌탈
  "5410000007",   // 신선식품
  "1000015925",   // 가공/건강식품
];

// ── 베스트 랭킹 카테고리 IDs ──
const RANKING_CATEGORIES = [
  "5000016005",   // 전체
  "5000016021",   // 패션의류
  "6000060708",   // 패션잡화
  "5000016022",   // 뷰티
  "5000016044",   // 스포츠/레저
  "5000016030",   // 생활/주방
  "6000060709",   // 가구/인테리어
  "5000016039",   // 유아동
  "5000016040",   // 디지털/렌탈
  "6000078977",   // 신선식품
  "6000078978",   // 가공/건강식품
];

/**
 * SSG 쓱특가 (카테고리별 수집)
 */
async function fetchSsgSpecialDeals(
  seenIds: Set<string>
): Promise<ProductJson[]> {
  const products: ProductJson[] = [];

  for (const catId of SPECIAL_CATEGORIES) {
    const hint = SSG_CATEGORY_NAMES[catId] || undefined;
    const items = await fetchPageArea(
      "100000007533", "2", "4", catId, seenIds, hint
    );
    products.push(...items);
    if (catId !== SPECIAL_CATEGORIES[SPECIAL_CATEGORIES.length - 1]) {
      await sleep(DELAYS.FETCH_BETWEEN);
    }
  }

  console.log(`[SSG] special deals: ${products.length}`);
  return products;
}

/**
 * SSG 베스트 랭킹 (카테고리별 수집)
 */
async function fetchSsgRanking(
  seenIds: Set<string>
): Promise<ProductJson[]> {
  const products: ProductJson[] = [];

  for (const catId of RANKING_CATEGORIES) {
    const hint = SSG_CATEGORY_NAMES[catId] || undefined;
    const items = await fetchPageArea(
      "100000007532", "2", "4", catId, seenIds, hint
    );
    products.push(...items);
    if (catId !== RANKING_CATEGORIES[RANKING_CATEGORIES.length - 1]) {
      await sleep(DELAYS.FETCH_BETWEEN);
    }
  }

  console.log(`[SSG] ranking: ${products.length}`);
  return products;
}

/**
 * SSG 마감특가 (closingsale)
 */
async function fetchSsgClosingSale(
  seenIds: Set<string>
): Promise<ProductJson[]> {
  const products: ProductJson[] = [];

  try {
    const body = {
      ...ssgCommonBody(),
      params: {
        viewSiteNo: "6005",
        dispDvicDivCd: "10",
      },
    };

    const res = await fetch(
      "https://frontapi.ssg.com/dp/api/v1/serviceshop/closingsale",
      {
        method: "POST",
        headers: SSG_HEADERS,
        body: JSON.stringify(body),
      }
    );
    if (!res.ok) return products;

    const json = (await res.json()) as any;
    const dataList = json?.data ?? [];

    for (const section of dataList) {
      const items = section?.items?.resultList ?? [];
      for (const item of items) {
        const product = parseSsgProduct(item, seenIds);
        if (product) products.push(product);
      }
    }
  } catch (e) {
    console.error("[SSG] closing sale error:", e);
  }

  return products;
}

export async function fetchSsgDeals(): Promise<ProductJson[]> {
  const products: ProductJson[] = [];
  const seenIds = new Set<string>();

  // 1) 쓱특가 (카테고리별)
  products.push(...await fetchSsgSpecialDeals(seenIds));
  // 2) 마감특가
  products.push(...await fetchSsgClosingSale(seenIds));
  // 3) 베스트 랭킹 (카테고리별)
  products.push(...await fetchSsgRanking(seenIds));

  sortByDropRate(products);
  console.log(`[SSG] ${products.length} total deals fetched`);
  return products;
}
