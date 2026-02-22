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
  seenIds: Set<string>
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
    category1: "SSG",
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

/**
 * SSG 쓱특가 페이지네이션 (v2/page/area)
 */
async function fetchSsgSpecialDeals(
  seenIds: Set<string>
): Promise<ProductJson[]> {
  const products: ProductJson[] = [];
  const maxPages = 5;

  for (let page = 1; page <= maxPages; page++) {
    try {
      const body = {
        ...ssgCommonBody(),
        params: {
          pageId: "100000007533",
          pageSetId: "2",
          pageCmptId: "4",
          dispDvicDivCd: "10",
          viewSiteNo: "6005",
          dispCtgId: "",
          pageNo: page,
          pageSize: 40,
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
      if (!res.ok) break;

      const json = (await res.json()) as any;

      // 아이템 추출: data.areaList[].itemList[] 또는 data.itemList[]
      const areaList = json?.data?.areaList ?? [];
      let pageItems = 0;
      for (const area of areaList) {
        for (const item of area.itemList ?? []) {
          const product = parseSsgProduct(item, seenIds);
          if (product) {
            products.push(product);
            pageItems++;
          }
        }
      }

      // 직접 itemList가 있는 경우
      for (const item of json?.data?.itemList ?? []) {
        const product = parseSsgProduct(item, seenIds);
        if (product) {
          products.push(product);
          pageItems++;
        }
      }

      if (pageItems === 0 || json?.data?.hasNext === false) break;
      await sleep(DELAYS.FETCH_BETWEEN);
    } catch (e) {
      console.error(`[SSG] page ${page} error:`, e);
      break;
    }
  }

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

  // 쓱특가 페이지네이션
  products.push(...await fetchSsgSpecialDeals(seenIds));
  // 마감특가
  products.push(...await fetchSsgClosingSale(seenIds));

  sortByDropRate(products);
  console.log(`[SSG] ${products.length} deals fetched`);
  return products;
}
