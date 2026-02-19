// ──────────────────────────────────────────
// External commerce fetchers (11st, Gmarket, Auction)
// ──────────────────────────────────────────

import fetch from "node-fetch";
import { ProductJson } from "../types";
import { COMMON_HEADERS, GIANEX_API_BASE, DELAYS } from "../config";
import { sleep, sortByDropRate } from "../utils";

function normalizeImageUrl(url: string): string {
  let imgUrl = url;
  if (imgUrl.startsWith("//")) imgUrl = "https:" + imgUrl;
  return imgUrl.replace(/resize\/\d+x\d+/, "resize/800x800");
}

export async function fetch11stDeals(): Promise<ProductJson[]> {
  const res = await fetch(
    "https://apis.11st.co.kr/pui/v2/page?pageId=PCHOMEHOME",
    { headers: { Accept: "application/json", ...COMMON_HEADERS } }
  );
  if (!res.ok) return [];

  const data = (await res.json()) as any;
  const carriers = data?.data ?? [];
  const DEAL_TYPES = [
    "PC_Product_Deal_Focus",
    "PC_Product_Deal_Time",
    "PC_Product_Deal_Emergency",
    "PC_Product_Deal_Shooting",
  ];

  const products: ProductJson[] = [];
  const seenIds = new Set<string>();

  for (const carrier of carriers) {
    for (const block of carrier.blockList ?? []) {
      if (!DEAL_TYPES.includes(block.type)) continue;
      for (const item of block.list ?? []) {
        const prdNo = item.prdNo?.toString();
        if (!prdNo || seenIds.has(prdNo)) continue;
        seenIds.add(prdNo);

        const sellPrice =
          parseInt((item.sellPrice || "0").replace(/,/g, ""), 10) || 0;
        const finalPrice =
          parseInt((item.finalDscPrice || "0").replace(/,/g, ""), 10) || 0;
        const discRate = parseInt(item.discountRate || "0", 10) || 0;
        const currentPrice = finalPrice > 0 ? finalPrice : sellPrice;
        const previousPrice = discRate > 0 && sellPrice > currentPrice ? sellPrice : null;

        if (currentPrice <= 0) continue;

        const imgUrl = normalizeImageUrl(item.imageUrl1 || "");

        products.push({
          id: `11st_${prdNo}`,
          title: item.title1 || "",
          link: item.linkUrl1 || `https://www.11st.co.kr/products/${prdNo}`,
          imageUrl: imgUrl,
          currentPrice,
          previousPrice,
          mallName: "11번가",
          brand: null,
          maker: null,
          category1: "11번가",
          category2: block.type.replace("PC_Product_Deal_", ""),
          category3: null,
          productType: "1",
          reviewScore: null,
          reviewCount: null,
          purchaseCount: item.selQty
            ? parseInt((item.selQty || "0").replace(/,/g, ""), 10) || null
            : null,
          rank: null,
          isDeliveryFree: JSON.stringify(item.benefit ?? {}).includes("무료배송"),
          isArrivalGuarantee: false,
          saleEndDate: item.displayEndDate
            ? item.displayEndDate.replace(
                /(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})/,
                "$1-$2-$3T$4:$5:$6"
              )
            : null,
        });
      }
    }
  }

  sortByDropRate(products);
  console.log(`[11st] ${products.length} deals fetched`);
  return products;
}

/** G마켓/옥션 공통 modules→tabs→components 파서 */
export function parseGianexItems(
  data: any,
  source: "gmkt" | "auction",
  seenIds: Set<string>
): ProductJson[] {
  const products: ProductJson[] = [];
  const mallName = source === "gmkt" ? "G마켓" : "옥션";

  for (const mod of data.modules ?? []) {
    for (const tab of mod.tabs ?? []) {
      for (const item of tab.components ?? []) {
        const itemNo = item.itemNo?.toString();
        if (!itemNo || seenIds.has(itemNo)) continue;
        seenIds.add(itemNo);

        const salePrice = Number(item.itemPrice) || 0;
        const origPrice = Number(item.sellPrice) || 0;
        const discRate = Number(item.discountRate) || 0;
        if (salePrice <= 0) continue;

        const imgUrl = normalizeImageUrl(item.imageUrl || "");

        let link: string;
        if (source === "gmkt") {
          link = item.itemUrl ? item.itemUrl.split("&utparam-url=")[0] : "";
          if (!link) link = `https://m.gmarket.co.kr/n/superdeal?goodsCode=${itemNo}`;
        } else {
          link = `https://m.auction.co.kr/ItemDetail?itemno=${itemNo}`;
        }

        products.push({
          id: `${source === "gmkt" ? "gmkt" : "auction"}_${itemNo}`,
          title: item.itemName || "",
          link,
          imageUrl: imgUrl,
          currentPrice: salePrice,
          previousPrice: discRate > 0 && origPrice > salePrice ? origPrice : null,
          mallName,
          brand: null,
          maker: null,
          category1: mallName,
          category2: null,
          category3: null,
          productType: "1",
          reviewScore: item.reviewPoint?.starPoint
            ? Number(item.reviewPoint.starPoint)
            : null,
          reviewCount: item.reviewPoint?.reviewCount
            ? Number(item.reviewPoint.reviewCount)
            : null,
          purchaseCount: null,
          rank: null,
          isDeliveryFree: item.isFreeShipping === true,
          isArrivalGuarantee: false,
          saleEndDate: item.superDealDispInfo?.dispEndDt || null,
        });
      }
    }
  }
  return products;
}

export async function fetchGmarketDeals(): Promise<ProductJson[]> {
  const products: ProductJson[] = [];
  const seenIds = new Set<string>();

  for (let page = 1; page <= 3; page++) {
    try {
      const res = await fetch(
        `${GIANEX_API_BASE}?sectionSeq=2&pageTypeSeq=1&pagingNumber=${page}`,
        { headers: { Accept: "application/json", ...COMMON_HEADERS } }
      );
      if (!res.ok) break;
      const data = (await res.json()) as any;
      products.push(...parseGianexItems(data, "gmkt", seenIds));
      if (!data.hasNext) break;
      await sleep(DELAYS.FETCH_BETWEEN);
    } catch (e) {
      console.error(`[Gmarket] page ${page} error:`, e);
      break;
    }
  }

  sortByDropRate(products);
  console.log(`[Gmarket] ${products.length} deals fetched`);
  return products;
}

export async function fetchAuctionDeals(): Promise<ProductJson[]> {
  const products: ProductJson[] = [];
  const seenIds = new Set<string>();

  try {
    const res = await fetch(
      `${GIANEX_API_BASE}?sectionSeq=1037&pageTypeSeq=1&pagingNumber=1`,
      { headers: { Accept: "application/json", ...COMMON_HEADERS } }
    );
    if (res.ok) {
      const data = (await res.json()) as any;
      products.push(...parseGianexItems(data, "auction", seenIds));
    }
  } catch (e) {
    console.error("[Auction] error:", e);
  }

  sortByDropRate(products);
  console.log(`[Auction] ${products.length} deals fetched`);
  return products;
}
