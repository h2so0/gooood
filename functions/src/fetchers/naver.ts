// ──────────────────────────────────────────
// Naver data fetchers (6 sources)
// ──────────────────────────────────────────

import fetch from "node-fetch";
import { ProductJson, KeywordJson, PopularKeywordJson } from "../types";
import { COMMON_HEADERS, DELAYS } from "../config";
import { sleep, extractNextData, sortByDropRate } from "../utils";

// ── Shared waffle parser ──

/**
 * Parse waffle-format layers into ProductJson[].
 * Used by fetchTodayDeals and fetchNaverPromotions to avoid ~80 lines of duplication.
 */
export function parseWaffleProducts(
  layers: any[],
  idPrefix: string,
  category1: string,
  category2: string | null = null,
  seenIds?: Set<string>
): ProductJson[] {
  const products: ProductJson[] = [];

  for (const layer of layers) {
    for (const block of layer.blocks ?? []) {
      for (const item of block.items ?? []) {
        for (const content of item.contents ?? []) {
          if (!content.productId || !content.salePrice) continue;
          if (content.isSoldOut || content.isRental) continue;

          const pid = content.productId.toString();
          if (seenIds) {
            if (seenIds.has(pid)) continue;
            seenIds.add(pid);
          }

          const salePrice = Number(content.salePrice) || 0;
          const discountedPrice = Number(content.discountedPrice) || salePrice;
          const discountedRatio = Number(content.discountedRatio) || 0;

          const currentPrice = discountedRatio > 0 ? discountedPrice : salePrice;
          const previousPrice = discountedRatio > 0 ? salePrice : null;

          if (currentPrice <= 0) continue;

          products.push({
            id: `${idPrefix}${pid}`,
            title: content.name || "",
            link: content.landingUrl || "",
            imageUrl: content.imageUrl || "",
            currentPrice,
            previousPrice,
            mallName: content.mallName || content.channelName || "스마트스토어",
            brand: null,
            maker: null,
            category1,
            category2,
            category3: null,
            productType: "1",
            reviewScore: content.averageReviewScore
              ? Number(content.averageReviewScore)
              : null,
            reviewCount: content.totalReviewCount
              ? Number(content.totalReviewCount)
              : null,
            purchaseCount: content.cumulationSaleCount
              ? Number(content.cumulationSaleCount)
              : null,
            rank: null,
            isDeliveryFree: content.isDeliveryFree === true,
            isArrivalGuarantee: content.isArrivalGuarantee === true,
            saleEndDate: content.saleEndDate || null,
          });
        }
      }
    }
  }

  return products;
}

// ── Fetchers ──

export async function fetchTodayDeals(): Promise<ProductJson[]> {
  const res = await fetch("https://shopping.naver.com/ns/home/today-event", {
    headers: COMMON_HEADERS,
  });
  if (!res.ok) return [];

  const html = await res.text();
  const nextData = extractNextData(html);
  if (!nextData) return [];

  const waffleData = nextData?.props?.pageProps?.waffleData;
  if (!waffleData) return [];

  const layers = waffleData?.pageData?.layers ?? [];
  const products = parseWaffleProducts(layers, "deal_", "오늘의딜");

  sortByDropRate(products);
  return products;
}

export async function fetchBest100(
  sortType: string,
  categoryId: string,
  naverCategoryName?: string,
): Promise<ProductJson[]> {
  const res = await fetch(
    `https://snxbest.naver.com/api/v1/snxbest/product/rank?ageType=ALL&categoryId=${categoryId}&sortType=${sortType}&periodType=DAILY`,
    {
      headers: {
        "User-Agent":
          "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36",
        Accept: "application/json",
        Referer: "https://snxbest.naver.com/home",
      },
    }
  );
  if (!res.ok) return [];

  const json = (await res.json()) as any;
  const rawProducts = json.products ?? [];
  const products: ProductJson[] = [];

  for (const item of rawProducts) {
    if (!item.productId || !item.title) continue;

    const discountPrice = Number(item.discountPriceValue) || 0;
    const originalPrice = Number(item.priceValue) || 0;
    const price = discountPrice > 0 ? discountPrice : originalPrice;
    const discountRateVal =
      parseInt(item.discountRate?.toString() || "0", 10) || 0;

    products.push({
      id: `best_${item.productId}`,
      title: item.title,
      link: item.linkUrl || "",
      imageUrl: item.imageUrl || "",
      currentPrice: price,
      previousPrice: discountRateVal > 0 ? originalPrice : null,
      mallName: item.mallNm || "BEST100",
      brand: null,
      maker: null,
      category1: naverCategoryName || "BEST100",
      category2: null,
      category3: null,
      productType: "1",
      reviewCount: item.reviewCount
        ? parseInt(item.reviewCount.toString().replace(/,/g, ""), 10) || null
        : null,
      reviewScore: item.reviewScore
        ? parseFloat(item.reviewScore.toString()) || null
        : null,
      purchaseCount: null,
      rank: item.rank ? Number(item.rank) : null,
      isDeliveryFree: item.deliveryFeeType === "FREE",
      isArrivalGuarantee: item.isArrivalGuarantee === true,
      saleEndDate: null,
    });
  }

  sortByDropRate(products);
  return products;
}

export async function fetchKeywordRank(): Promise<KeywordJson[]> {
  const res = await fetch(
    "https://snxbest.naver.com/api/v1/snxbest/keyword/rank?ageType=ALL&categoryId=A&sortType=KEYWORD_NEW&periodType=WEEKLY",
    {
      headers: {
        "User-Agent":
          "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36",
        Accept: "application/json",
        Referer: "https://snxbest.naver.com/home",
      },
    }
  );
  if (!res.ok) return [];

  const rawList = (await res.json()) as any[];
  const keywords: KeywordJson[] = [];

  for (const item of rawList) {
    const title = item.title?.toString() || "";
    if (!title) continue;
    const rank = Number(item.rank) || 0;
    const fluctuation = Number(item.rankFluctuation) || 0;
    const status = item.status?.toString() || "STABLE";

    keywords.push({
      keyword: title,
      ratio: 20 - rank + 1,
      rankChange: status === "NEW" ? null : fluctuation,
    });
  }

  return keywords;
}

export async function fetchPopularKeywords(
  categoryId: string,
  categoryName: string
): Promise<PopularKeywordJson[]> {
  const now = new Date();
  const today = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, "0")}-${String(now.getDate()).padStart(2, "0")}`;

  const res = await fetch(
    "https://datalab.naver.com/shoppingInsight/getKeywordRank.naver",
    {
      method: "POST",
      headers: {
        "Content-Type": "application/x-www-form-urlencoded",
        Referer:
          "https://datalab.naver.com/shoppingInsight/sCategory.naver",
        "User-Agent":
          "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36",
      },
      body: `cid=${categoryId}&timeUnit=date&startDate=${today}&endDate=${today}&age=&gender=&device=`,
    }
  );
  if (!res.ok) return [];

  const json = (await res.json()) as any[];
  if (json.length === 0) return [];

  const latest = json[json.length - 1];
  const ranks = latest.ranks ?? [];

  return ranks.map((r: any) => ({
    rank: Number(r.rank),
    keyword: r.keyword as string,
    category: categoryName,
  }));
}

export async function fetchShoppingLive(): Promise<ProductJson[]> {
  const res = await fetch("https://shoppinglive.naver.com/home", {
    headers: COMMON_HEADERS,
  });
  if (!res.ok) return [];

  const html = await res.text();
  const nextData = extractNextData(html);
  if (!nextData) return [];

  const trendingLives =
    nextData?.props?.pageProps?.initialRecoilState?.trendingLives ?? [];

  const products: ProductJson[] = [];

  for (const live of trendingLives) {
    const status = live.status || "";
    if (status !== "ONAIR" && status !== "STANDBY") continue;

    const liveProducts = live.products ?? [];
    const channelName = live.channelName || "쇼핑라이브";
    const liveTitle = live.title || "";
    const broadcastId = live.broadcastId || "";

    for (const prod of liveProducts) {
      const name = prod.name || "";
      if (!name) continue;

      const price = Number(prod.price) || 0;
      const discountRate = Number(prod.discountRate) || 0;
      const originalPrice =
        discountRate > 0 && price > 0
          ? Math.round(price / (1 - discountRate / 100))
          : null;

      if (price <= 0) continue;

      const productId =
        prod.productId || prod.id || `${broadcastId}_${name.slice(0, 10)}`;

      products.push({
        id: `live_${productId}`,
        title: name,
        link:
          prod.linkUrl ||
          `https://shoppinglive.naver.com/lives/${broadcastId}`,
        imageUrl: prod.imageUrl || live.standByThumbnailImageUrl || "",
        currentPrice: price,
        previousPrice: originalPrice,
        mallName: `${channelName}`,
        brand: null,
        maker: null,
        category1: "쇼핑라이브",
        category2: liveTitle,
        category3: null,
        productType: "1",
        reviewScore: null,
        reviewCount: null,
        purchaseCount: live.orderMemberCount
          ? Number(live.orderMemberCount)
          : null,
        rank: null,
        isDeliveryFree: prod.deliveryFee === 0 || prod.deliveryFee === "0",
        isArrivalGuarantee: false,
        saleEndDate: null,
      });
    }
  }

  sortByDropRate(products);
  return products;
}

export async function fetchNaverPromotions(): Promise<ProductJson[]> {
  const pageRes = await fetch("https://shopping.naver.com/promotion", {
    headers: COMMON_HEADERS,
  });
  if (!pageRes.ok) return [];

  const html = await pageRes.text();
  const nextData = extractNextData(html);
  if (!nextData) return [];

  const pageProps = nextData?.props?.pageProps;
  if (!pageProps) return [];

  // dehydratedState에서 탭 목록 추출
  const queries = pageProps?.dehydratedState?.queries ?? [];
  let tabList: any[] = [];
  for (const q of queries) {
    const key = q?.queryKey?.[0] || "";
    if (key.toLowerCase().includes("tab") || key.toLowerCase().includes("promotion")) {
      const data = q?.state?.data;
      if (Array.isArray(data) && data.length > 0) {
        tabList = data;
        break;
      }
    }
  }
  if (tabList.length === 0) {
    tabList = pageProps?.tabList ?? [];
  }

  // WAFFLE 타입 탭의 UID 수집 (첫 번째 = 스페셜딜 = todayDeals 중복이므로 제외)
  const waffleUids: { uid: string; name: string }[] = [];
  let isFirst = true;
  for (const tab of tabList) {
    const tabType = tab.tabType ?? tab.type ?? "";
    const uid = tab.uid ?? tab.promotionUid ?? "";
    const name = tab.title ?? tab.tabTitle ?? tab.name ?? "";
    if (tabType !== "WAFFLE") continue;
    if (!uid) continue;
    if (isFirst) {
      isFirst = false;
      continue;
    }
    waffleUids.push({ uid, name });
  }

  console.log(
    `[Promo] ${waffleUids.length} promo tabs: ${waffleUids.map((u) => u.name).join(", ")}`
  );

  // 각 탭의 Waffle API로 상품 데이터 가져오기
  const products: ProductJson[] = [];
  const seenIds = new Set<string>();

  for (const { uid, name } of waffleUids) {
    try {
      const dataRes = await fetch(
        `https://shopping.naver.com/api/waffle/v1/waffle-maker/data/pages/${uid}`,
        {
          headers: {
            ...COMMON_HEADERS,
            Accept: "application/json",
            Referer: "https://shopping.naver.com/promotion",
          },
        }
      );
      if (!dataRes.ok) {
        console.log(`[Promo] Tab "${name}" API ${dataRes.status}`);
        continue;
      }

      const data = (await dataRes.json()) as any;
      const layers = data?.layers ?? [];
      const tabProducts = parseWaffleProducts(
        layers, "promo_", "프로모션", name || null, seenIds
      );
      products.push(...tabProducts);
      console.log(`[Promo] Tab "${name}": ${tabProducts.length} products`);
    } catch (e) {
      console.error(`[Promo] Tab "${name}" error:`, e);
    }
    await sleep(DELAYS.FETCH_BETWEEN);
  }

  sortByDropRate(products);
  return products;
}
