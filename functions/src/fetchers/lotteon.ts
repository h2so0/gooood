// ──────────────────────────────────────────
// LotteON (롯데ON) deal fetcher
// ──────────────────────────────────────────

import fetch from "node-fetch";
import { ProductJson } from "../types";
import { COMMON_HEADERS } from "../config";
import { sortByDropRate } from "../utils";

const LOTTEON_HEADERS = {
  ...COMMON_HEADERS,
  Accept: "application/json, text/plain, */*",
  "Accept-Language": "ko-KR,ko;q=0.9",
  Referer: "https://www.lotteon.com/p/display/main/lotteon",
  Origin: "https://www.lotteon.com",
};

interface LotteonProduct {
  pdNo?: string;
  spdNm?: string;
  slPrc?: number;
  scndFvrPrc?: number;
  dcVal?: number;
  slStatCd?: string;
  imgFullUrl?: string;
  trNm?: string;
  brdNm?: string;
  sndDvCst?: number;
  stscrAvgScr?: number;
  rvCnt?: number;
  slEndDttm?: string;
  flagInfoList?: { flagName?: string }[];
}

function parseLotteonProduct(
  item: LotteonProduct,
  seenIds: Set<string>
): ProductJson | null {
  const pdNo = item.pdNo;
  if (!pdNo || seenIds.has(pdNo)) return null;
  if (item.slStatCd === "SOUT") return null; // 품절 제외

  seenIds.add(pdNo);

  const originalPrice = item.slPrc || 0;
  const salePrice = item.scndFvrPrc || originalPrice;
  if (salePrice <= 0) return null;

  const discRate = item.dcVal || 0;
  const previousPrice =
    discRate > 0 && originalPrice > salePrice ? originalPrice : null;

  let imgUrl = item.imgFullUrl || "";
  if (imgUrl.startsWith("//")) imgUrl = "https:" + imgUrl;

  const flags = (item.flagInfoList || []).map((f) => f.flagName || "");
  const isFreeShipping =
    (item.sndDvCst ?? -1) === 0 || flags.includes("무료배송");

  let saleEndDate: string | null = null;
  if (item.slEndDttm && !item.slEndDttm.startsWith("9999")) {
    // "2026-02-23 23:59:00" → ISO format
    saleEndDate = item.slEndDttm.replace(" ", "T");
  }

  return {
    id: `lotte_${pdNo}`,
    title: (item.spdNm || "").replace(/\[.*?\]\s*/g, "").trim() || item.spdNm || "",
    link: `https://www.lotteon.com/p/product/detail/sale/${pdNo}`,
    imageUrl: imgUrl,
    currentPrice: salePrice,
    previousPrice,
    mallName: "롯데ON",
    brand: item.brdNm || null,
    maker: item.trNm || null,
    category1: "롯데ON",
    category2: null,
    category3: null,
    productType: "1",
    reviewScore: item.stscrAvgScr || null,
    reviewCount: item.rvCnt || null,
    purchaseCount: null,
    rank: null,
    isDeliveryFree: isFreeShipping,
    isArrivalGuarantee: false,
    saleEndDate,
  };
}

/**
 * 롯데ON 벌크 딜 카탈로그 (deal-mab) - 최대 ~800개 상품을 한 번에 반환
 */
async function fetchLotteonBulkDeals(
  seenIds: Set<string>
): Promise<ProductJson[]> {
  const products: ProductJson[] = [];

  try {
    const res = await fetch(
      "https://pbf.lotteon.com/display/v2/async/recommend/pd_tab_n02/deal-mab" +
        "?collectionId=SELECT&dshopNo=60875&mallNo=1&tmplNo=2&tmplSeq=17949" +
        "&dcornId=pd_tab_n02&dcornNo=M001675&dcornLnkSeq=1234756" +
        "&dpInfwCd=MAT60875&areaId=M&rndEpsrCd=01",
      { headers: LOTTEON_HEADERS }
    );
    if (!res.ok) return products;

    const json = (await res.json()) as any;
    const sets = json?.data?.dpLnkDpTgtSetList ?? [];

    for (const set of sets) {
      const dtgtList = set.dtgtJsn ?? [];
      for (const dtgt of dtgtList) {
        const items = dtgt?.pdList?.dataList ?? [];
        for (const item of items) {
          const product = parseLotteonProduct(item, seenIds);
          if (product) products.push(product);
        }
      }
    }
  } catch (e) {
    console.error("[LotteON] bulk deals error:", e);
  }

  return products;
}

/**
 * 롯데ON 스페셜특가 (dshopNo=60938)
 */
async function fetchLotteonSpecialDeals(
  seenIds: Set<string>
): Promise<ProductJson[]> {
  const products: ProductJson[] = [];

  try {
    const res = await fetch(
      "https://pbf.lotteon.com/display/v2/dpShop/seltMainShop?dshopNo=60938",
      { headers: LOTTEON_HEADERS }
    );
    if (!res.ok) return products;

    const json = (await res.json()) as any;
    const modules = json?.data?.dpShopMdulList ?? [];

    for (const mod of modules) {
      const sets = mod.dpLnkDpTgtSetList ?? [];
      for (const set of sets) {
        const dtgtList = set.dtgtJsn ?? [];
        for (const dtgt of dtgtList) {
          const items = dtgt?.pdList?.dataList ?? [];
          for (const item of items) {
            const product = parseLotteonProduct(item, seenIds);
            if (product) products.push(product);
          }
        }
      }
    }
  } catch (e) {
    console.error("[LotteON] special deals error:", e);
  }

  return products;
}

export async function fetchLotteonDeals(): Promise<ProductJson[]> {
  const products: ProductJson[] = [];
  const seenIds = new Set<string>();

  // 스페셜특가만 수집 (확실한 기획전/특가 상품)
  products.push(...await fetchLotteonSpecialDeals(seenIds));

  sortByDropRate(products);
  console.log(`[LotteON] ${products.length} deals fetched`);
  return products;
}
