import * as admin from "firebase-admin";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { onRequest } from "firebase-functions/v2/https";
import fetch from "node-fetch";

admin.initializeApp();

// ──────────────────────────────────────────
// 설정
// ──────────────────────────────────────────

const NAVER_CLIENT_ID = "hiD1em_BVH7_sHIirwVD";
const NAVER_CLIENT_SECRET = "b6yEA6sv6W";
const NAVER_SHOP_URL = "https://openapi.naver.com/v1/search/shop.json";

const CATEGORY_MAP: Record<string, string> = {
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

const CATEGORY_NAME_MAP: Record<string, string> = {};
for (const [name, id] of Object.entries(CATEGORY_MAP)) {
  CATEGORY_NAME_MAP[id] = name;
}

const BEST100_CATEGORIES = ["A", ...Object.values(CATEGORY_MAP)];

// ──────────────────────────────────────────
// 타입
// ──────────────────────────────────────────

interface ProductJson {
  id: string;
  title: string;
  link: string;
  imageUrl: string;
  currentPrice: number;
  previousPrice: number | null;
  mallName: string;
  brand: string | null;
  maker: string | null;
  category1: string;
  category2: string | null;
  category3: string | null;
  productType: string;
  reviewCount: number | null;
  purchaseCount: number | null;
  reviewScore: number | null;
  rank: number | null;
  isDeliveryFree: boolean;
  isArrivalGuarantee: boolean;
  saleEndDate: string | null;
}

interface KeywordJson {
  keyword: string;
  ratio: number;
  rankChange: number | null;
}

interface PopularKeywordJson {
  rank: number;
  keyword: string;
  category: string;
}

// ──────────────────────────────────────────
// 유틸
// ──────────────────────────────────────────

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

function dropRate(p: ProductJson): number {
  if (!p.previousPrice || p.previousPrice <= 0) return 0;
  return ((p.previousPrice - p.currentPrice) / p.previousPrice) * 100;
}

function sortByDropRate(products: ProductJson[]): void {
  products.sort((a, b) => dropRate(b) - dropRate(a));
}

/** Extract __NEXT_DATA__ JSON from an HTML page */
function extractNextData(html: string): any | null {
  // 1차: 정규식
  const match = html.match(
    /<script id="__NEXT_DATA__" type="application\/json">(.*?)<\/script>/s
  );
  if (match) return JSON.parse(match[1]);

  // 2차: indexOf (속성 순서가 다를 수 있음)
  let startMarker = '<script id="__NEXT_DATA__" type="application/json">';
  let startIdx = html.indexOf(startMarker);
  if (startIdx === -1) {
    const altIdx = html.indexOf("__NEXT_DATA__");
    if (altIdx !== -1) {
      const tagEnd = html.indexOf(">", altIdx);
      if (tagEnd !== -1) {
        const tagStart = html.lastIndexOf("<script", altIdx);
        startMarker = html.substring(tagStart, tagEnd + 1);
        startIdx = tagStart;
      }
    }
    if (startIdx === -1) return null;
  }
  const jsonStart = startIdx + startMarker.length;
  const endIdx = html.indexOf("</script>", jsonStart);
  if (endIdx === -1) return null;
  return JSON.parse(html.substring(jsonStart, endIdx));
}

async function writeCache(docId: string, items: unknown[]): Promise<void> {
  await admin.firestore().collection("cache").doc(docId).set({
    items,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });
}

// ──────────────────────────────────────────
// 네이버 데이터 수집
// ──────────────────────────────────────────

async function fetchTodayDeals(): Promise<ProductJson[]> {
  const res = await fetch("https://shopping.naver.com/ns/home/today-event", {
    headers: {
      "User-Agent":
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
    },
  });
  if (!res.ok) return [];

  const html = await res.text();
  const nextData = extractNextData(html);
  if (!nextData) return [];

  const waffleData = nextData?.props?.pageProps?.waffleData;
  if (!waffleData) return [];

  const layers = waffleData?.pageData?.layers ?? [];
  const products: ProductJson[] = [];

  for (const layer of layers) {
    for (const block of layer.blocks ?? []) {
      for (const item of block.items ?? []) {
        for (const content of item.contents ?? []) {
          if (!content.productId || !content.salePrice) continue;
          if (content.isSoldOut || content.isRental) continue;

          const salePrice = Number(content.salePrice) || 0;
          const discountedPrice =
            Number(content.discountedPrice) || salePrice;
          const discountedRatio = Number(content.discountedRatio) || 0;
          const label = (content.labelText || "")
            .replace(/\n/g, " ")
            .trim();

          const currentPrice =
            discountedRatio > 0 ? discountedPrice : salePrice;
          const previousPrice = discountedRatio > 0 ? salePrice : null;

          products.push({
            id: `deal_${content.productId}`,
            title: content.name || "",
            link: content.landingUrl || "",
            imageUrl: content.imageUrl || "",
            currentPrice,
            previousPrice,
            mallName: label || "스마트스토어",
            brand: null,
            maker: null,
            category1: "오늘의딜",
            category2: null,
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

  sortByDropRate(products);
  return products;
}

async function fetchBest100(
  sortType: string,
  categoryId: string
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
      category1: "BEST100",
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

async function fetchKeywordRank(): Promise<KeywordJson[]> {
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

async function fetchPopularKeywords(
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

// ──────────────────────────────────────────
// 새 데이터 소스 수집
// ──────────────────────────────────────────

const COMMON_HEADERS = {
  "User-Agent":
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
};

async function fetchShoppingLive(): Promise<ProductJson[]> {
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
    // ONAIR 또는 STANDBY 방송만
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

async function fetchNaverPromotions(): Promise<ProductJson[]> {
  // 1. 프로모션 페이지에서 탭 목록 추출
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
  // fallback: pageProps.tabList
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
    // 첫 번째 WAFFLE 탭 = todayDeals와 중복 → 제외
    if (isFirst) {
      isFirst = false;
      continue;
    }
    waffleUids.push({ uid, name });
  }

  console.log(
    `[Promo] ${waffleUids.length} promo tabs: ${waffleUids.map((u) => u.name).join(", ")}`
  );

  // 2. 각 탭의 Waffle API로 상품 데이터 가져오기
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

      let tabCount = 0;
      for (const layer of layers) {
        for (const block of layer.blocks ?? []) {
          for (const item of block.items ?? []) {
            for (const content of item.contents ?? []) {
              if (!content.productId || !content.salePrice) continue;
              if (content.isSoldOut || content.isRental) continue;

              const pid = content.productId.toString();
              if (seenIds.has(pid)) continue;
              seenIds.add(pid);

              const salePrice = Number(content.salePrice) || 0;
              const discountedPrice =
                Number(content.discountedPrice) || salePrice;
              const discountedRatio =
                Number(content.discountedRatio) || 0;
              const currentPrice =
                discountedRatio > 0 ? discountedPrice : salePrice;
              const previousPrice =
                discountedRatio > 0 ? salePrice : null;

              if (currentPrice <= 0) continue;

              const label = (content.labelText || "")
                .replace(/\n/g, " ")
                .trim();

              products.push({
                id: `promo_${pid}`,
                title: content.name || "",
                link: content.landingUrl || "",
                imageUrl: content.imageUrl || "",
                currentPrice,
                previousPrice,
                mallName: label || name || "네이버 프로모션",
                brand: null,
                maker: null,
                category1: "프로모션",
                category2: name || null,
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
              tabCount++;
            }
          }
        }
      }
      console.log(`[Promo] Tab "${name}": ${tabCount} products`);
    } catch (e) {
      console.error(`[Promo] Tab "${name}" error:`, e);
    }
    await sleep(300);
  }

  sortByDropRate(products);
  return products;
}

// ──────────────────────────────────────────
// 외부 커머스 데이터 수집
// ──────────────────────────────────────────

async function fetch11stDeals(): Promise<ProductJson[]> {
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

        let imgUrl = item.imageUrl1 || "";
        if (imgUrl.startsWith("//")) imgUrl = "https:" + imgUrl;
        // 720x360 배너 → 400x400 정사각형으로 변경
        imgUrl = imgUrl.replace(/resize\/\d+x\d+/, "resize/400x400");

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
function parseGianexItems(
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

        let imgUrl = item.imageUrl || "";
        if (imgUrl.startsWith("//")) imgUrl = "https:" + imgUrl;

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

async function fetchGmarketDeals(): Promise<ProductJson[]> {
  const BASE = "https://elsa-fe.gmarket.co.kr/n/home/api/page";
  const products: ProductJson[] = [];
  const seenIds = new Set<string>();

  for (let page = 1; page <= 3; page++) {
    try {
      const res = await fetch(
        `${BASE}?sectionSeq=2&pageTypeSeq=1&pagingNumber=${page}`,
        { headers: { Accept: "application/json", ...COMMON_HEADERS } }
      );
      if (!res.ok) break;
      const data = (await res.json()) as any;
      products.push(...parseGianexItems(data, "gmkt", seenIds));
      if (!data.hasNext) break;
      await sleep(300);
    } catch (e) {
      console.error(`[Gmarket] page ${page} error:`, e);
      break;
    }
  }

  sortByDropRate(products);
  console.log(`[Gmarket] ${products.length} deals fetched`);
  return products;
}

async function fetchAuctionDeals(): Promise<ProductJson[]> {
  const BASE = "https://elsa-fe.gmarket.co.kr/n/home/api/page";
  const products: ProductJson[] = [];
  const seenIds = new Set<string>();

  try {
    const res = await fetch(
      `${BASE}?sectionSeq=1037&pageTypeSeq=1&pagingNumber=1`,
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

// ──────────────────────────────────────────
// 카테고리 매칭 (알림용)
// ──────────────────────────────────────────

async function matchCategory(title: string): Promise<string | null> {
  const query = title.substring(0, 30);
  const url = `${NAVER_SHOP_URL}?query=${encodeURIComponent(query)}&display=1`;

  try {
    const res = await fetch(url, {
      headers: {
        "X-Naver-Client-Id": NAVER_CLIENT_ID,
        "X-Naver-Client-Secret": NAVER_CLIENT_SECRET,
      },
    });
    if (!res.ok) return null;

    const json = (await res.json()) as any;
    const items = json.items ?? [];
    if (items.length === 0) return null;

    const category1 = items[0].category1 || "";
    for (const [name] of Object.entries(CATEGORY_MAP)) {
      const keyword = name.split("/")[0];
      if (category1.includes(keyword)) return name;
    }
    return category1 || null;
  } catch {
    return null;
  }
}

// ──────────────────────────────────────────
// FCM 발송
// ──────────────────────────────────────────

async function sendToTopic(
  topic: string,
  title: string,
  body: string,
  type: string,
  productId?: string
): Promise<void> {
  try {
    await admin.messaging().send({
      topic,
      notification: { title, body },
      data: {
        type,
        ...(productId ? { productId } : {}),
      },
      android: {
        priority: "high",
        notification: {
          channelId:
            type === "hotDeal"
              ? "hot_deal"
              : type === "saleEnd"
                ? "sale_end"
                : "daily_best",
        },
      },
      apns: {
        payload: { aps: { sound: "default" } },
      },
    });
  } catch (e) {
    console.error(`FCM send failed for topic ${topic}:`, e);
  }
}

// ──────────────────────────────────────────
// Cloud Functions
// ──────────────────────────────────────────

/**
 * syncDeals: 15분마다
 * - 오늘의딜 → Firestore 캐시
 * - 핫딜 알림 (할인율 30%+)
 * - 마감임박 알림 (1시간 이내)
 * - 오래된 발송 기록 정리
 */
export const syncDeals = onSchedule(
  {
    schedule: "every 15 minutes",
    timeZone: "Asia/Seoul",
    region: "asia-northeast3",
    timeoutSeconds: 120,
  },
  async () => {
    const products = await fetchTodayDeals();
    console.log(`Fetched ${products.length} today deals`);

    // ① Firestore 캐시
    await writeCache("todayDeals", products);

    // ② 핫딜 알림
    const hotDeals = products.filter((p) => dropRate(p) >= 30);
    if (hotDeals.length > 0) {
      const db = admin.firestore();
      const sentRef = db.collection("sent_notifications");
      const sentSnap = await sentRef
        .where("type", "==", "hotDeal")
        .orderBy("timestamp", "desc")
        .limit(200)
        .get();
      const sentIds = new Set(sentSnap.docs.map((d) => d.data().productId));

      // 카테고리 매칭 (상위 10개, 알림 토픽용)
      const categoryMap = new Map<string, string>();
      for (let i = 0; i < Math.min(hotDeals.length, 10); i++) {
        const cat = await matchCategory(hotDeals[i].title);
        if (cat) categoryMap.set(hotDeals[i].id, cat);
        await sleep(200);
      }

      let sent = 0;
      for (const deal of hotDeals) {
        if (sent >= 3) break;
        if (sentIds.has(deal.id)) continue;

        const rate = Math.round(dropRate(deal));
        const title = `🔥 핫딜 ${rate}% 할인!`;

        await sendToTopic("hotDeal", title, deal.title, "hotDeal", deal.id);

        const matchedCat = categoryMap.get(deal.id);
        if (matchedCat && CATEGORY_MAP[matchedCat]) {
          const catId = CATEGORY_MAP[matchedCat];
          await sendToTopic(
            `hotDeal_${catId}`,
            title,
            deal.title,
            "hotDeal",
            deal.id
          );
        }

        await sentRef.add({
          productId: deal.id,
          type: "hotDeal",
          timestamp: admin.firestore.FieldValue.serverTimestamp(),
        });
        sent++;
      }
    }

    // ③ 마감임박 알림
    const now = Date.now();
    const endingSoon = products.filter((p) => {
      if (!p.saleEndDate) return false;
      const endTime = new Date(p.saleEndDate).getTime();
      const diffMin = (endTime - now) / 60000;
      return diffMin > 0 && diffMin <= 60;
    });

    if (endingSoon.length > 0) {
      const db = admin.firestore();
      const sentRef = db.collection("sent_notifications");
      const sentSnap = await sentRef
        .where("type", "==", "saleEnd")
        .orderBy("timestamp", "desc")
        .limit(200)
        .get();
      const sentIds = new Set(sentSnap.docs.map((d) => d.data().productId));

      let sent = 0;
      for (const deal of endingSoon) {
        if (sent >= 3) break;
        if (sentIds.has(deal.id)) continue;

        const endTime = new Date(deal.saleEndDate!).getTime();
        const minutesLeft = Math.round((endTime - now) / 60000);

        await sendToTopic(
          "saleEnd",
          `⏰ ${minutesLeft}분 후 마감!`,
          deal.title,
          "saleEnd",
          deal.id
        );

        await sentRef.add({
          productId: deal.id,
          type: "saleEnd",
          timestamp: admin.firestore.FieldValue.serverTimestamp(),
        });
        sent++;
      }
    }

    // ④ 오래된 발송 기록 정리 (7일 이상)
    const cutoff = new Date();
    cutoff.setDate(cutoff.getDate() - 7);
    const db = admin.firestore();
    const oldSnap = await db
      .collection("sent_notifications")
      .where("timestamp", "<", cutoff)
      .limit(100)
      .get();
    if (!oldSnap.empty) {
      const batch = db.batch();
      oldSnap.docs.forEach((d) => batch.delete(d.ref));
      await batch.commit();
    }
  }
);

/**
 * syncBest100: 30분마다
 * - BEST100 전체 + 카테고리별 → Firestore 캐시
 */
export const syncBest100 = onSchedule(
  {
    schedule: "every 30 minutes",
    timeZone: "Asia/Seoul",
    region: "asia-northeast3",
    timeoutSeconds: 120,
  },
  async () => {
    for (const categoryId of BEST100_CATEGORIES) {
      try {
        const products = await fetchBest100("PRODUCT_CLICK", categoryId);
        await writeCache(`best100_${categoryId}`, products);
        console.log(
          `Cached best100_${categoryId}: ${products.length} products`
        );
      } catch (e) {
        console.error(`Failed best100 ${categoryId}:`, e);
      }
      await sleep(500);
    }
  }
);

/**
 * syncKeywords: 1시간마다
 * - 키워드 랭킹 + 카테고리별 인기 검색어 → Firestore 캐시
 */
export const syncKeywords = onSchedule(
  {
    schedule: "every 60 minutes",
    timeZone: "Asia/Seoul",
    region: "asia-northeast3",
    timeoutSeconds: 120,
  },
  async () => {
    // ① 키워드 랭킹
    try {
      const keywords = await fetchKeywordRank();
      await writeCache("keywordRank", keywords);
      console.log(`Cached keywordRank: ${keywords.length} keywords`);
    } catch (e) {
      console.error("Failed keyword rank:", e);
    }

    // ② 카테고리별 인기 검색어
    const allKeywords: PopularKeywordJson[] = [];
    for (const [name, id] of Object.entries(CATEGORY_MAP)) {
      try {
        const keywords = await fetchPopularKeywords(id, name);
        await writeCache(`popularKeywords_${id}`, keywords);
        allKeywords.push(...keywords);
        console.log(
          `Cached popularKeywords_${id}: ${keywords.length} keywords`
        );
      } catch (e) {
        console.error(`Failed popular keywords ${name}:`, e);
      }
      await sleep(300);
    }
    await writeCache("popularKeywords_all", allKeywords);
  }
);

/**
 * syncShoppingLive: 10분마다
 * - 네이버 쇼핑라이브 상품 → Firestore 캐시
 */
export const syncShoppingLive = onSchedule(
  {
    schedule: "every 10 minutes",
    timeZone: "Asia/Seoul",
    region: "asia-northeast3",
    timeoutSeconds: 60,
  },
  async () => {
    try {
      const products = await fetchShoppingLive();
      await writeCache("shoppingLive", products);
      console.log(`Cached shoppingLive: ${products.length} products`);
    } catch (e) {
      console.error("Failed shoppingLive:", e);
    }
  }
);

/**
 * syncPromotions: 30분마다
 * - 네이버 프로모션 (스페셜딜/브랜드데이) → Firestore 캐시
 */
export const syncPromotions = onSchedule(
  {
    schedule: "every 30 minutes",
    timeZone: "Asia/Seoul",
    region: "asia-northeast3",
    timeoutSeconds: 60,
  },
  async () => {
    try {
      const promos = await fetchNaverPromotions();
      await writeCache("naverPromotions", promos);
      console.log(`Cached naverPromotions: ${promos.length} products`);
    } catch (e) {
      console.error("Failed naverPromotions:", e);
    }
  }
);

/**
 * syncExternalDeals: 15분마다
 * - 11번가, G마켓, 옥션 딜 → Firestore 캐시
 */
export const syncExternalDeals = onSchedule(
  {
    schedule: "every 15 minutes",
    timeZone: "Asia/Seoul",
    region: "asia-northeast3",
    timeoutSeconds: 120,
  },
  async () => {
    try {
      const st = await fetch11stDeals();
      await writeCache("11stDeals", st);
      console.log(`Cached 11stDeals: ${st.length}`);
    } catch (e) {
      console.error("Failed 11stDeals:", e);
    }
    await sleep(1000);
    try {
      const gm = await fetchGmarketDeals();
      await writeCache("gmarketDeals", gm);
      console.log(`Cached gmarketDeals: ${gm.length}`);
    } catch (e) {
      console.error("Failed gmarketDeals:", e);
    }
    await sleep(1000);
    try {
      const au = await fetchAuctionDeals();
      await writeCache("auctionDeals", au);
      console.log(`Cached auctionDeals: ${au.length}`);
    } catch (e) {
      console.error("Failed auctionDeals:", e);
    }
  }
);

/**
 * dailyBest: 매일 오전 9시
 * - 캐시에서 TOP 5 → dailyBest 토픽 알림
 */
export const dailyBest = onSchedule(
  {
    schedule: "0 9 * * *",
    timeZone: "Asia/Seoul",
    region: "asia-northeast3",
  },
  async () => {
    // 캐시에서 읽기
    const cacheDoc = await admin
      .firestore()
      .collection("cache")
      .doc("todayDeals")
      .get();
    let products: ProductJson[] = cacheDoc.exists
      ? ((cacheDoc.data()?.items as ProductJson[]) ?? [])
      : [];

    // 캐시 없으면 직접 가져오기 (fallback)
    if (products.length === 0) {
      products = await fetchTodayDeals();
    }
    if (products.length === 0) return;

    // 오늘 이미 보냈는지 확인
    const db = admin.firestore();
    const today = new Date().toISOString().substring(0, 10);
    const sentRef = db.collection("sent_notifications");
    const existing = await sentRef
      .where("type", "==", "dailyBest")
      .where("dateKey", "==", today)
      .limit(1)
      .get();
    if (!existing.empty) return;

    const top5 = products.slice(0, 5);
    const body = top5
      .map(
        (d, i) =>
          `${i + 1}. ${d.title} (${Math.round(dropRate(d))}%↓)`
      )
      .join("\n");

    await sendToTopic(
      "dailyBest",
      "📊 오늘의 BEST 딜 TOP 5",
      body,
      "dailyBest"
    );

    await sentRef.add({
      type: "dailyBest",
      dateKey: today,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
    });
  }
);

/** 동기화 태스크 정의 (manualSync에서 루프 처리) */
const SYNC_TASKS: { name: string; fn: () => Promise<unknown[]>; key: string; delay?: number }[] = [
  { name: "todayDeals",      fn: fetchTodayDeals,      key: "todayDeals" },
  { name: "shoppingLive",    fn: fetchShoppingLive,     key: "shoppingLive" },
  { name: "naverPromotions", fn: fetchNaverPromotions,  key: "naverPromotions" },
  { name: "11stDeals",       fn: fetch11stDeals,        key: "11stDeals" },
  { name: "gmarketDeals",    fn: fetchGmarketDeals,     key: "gmarketDeals" },
  { name: "auctionDeals",    fn: fetchAuctionDeals,     key: "auctionDeals" },
  { name: "keywordRank",     fn: fetchKeywordRank,      key: "keywordRank" },
];

/**
 * manualSync: 수동 데이터 동기화 (테스트/초기 세팅용)
 * GET /manualSync 으로 호출
 */
export const manualSync = onRequest(
  {
    region: "asia-northeast3",
    timeoutSeconds: 300,
  },
  async (_req, res) => {
    const results: string[] = [];

    // ① 기본 소스 동기화
    for (const task of SYNC_TASKS) {
      try {
        const items = await task.fn();
        await writeCache(task.key, items);
        results.push(`${task.name}: ${items.length}`);
      } catch (e) {
        results.push(`${task.name}: ERROR ${e}`);
      }
    }

    // ② BEST100 (카테고리별)
    for (const categoryId of BEST100_CATEGORIES) {
      try {
        const products = await fetchBest100("PRODUCT_CLICK", categoryId);
        await writeCache(`best100_${categoryId}`, products);
        results.push(`best100_${categoryId}: ${products.length}`);
      } catch (e) {
        results.push(`best100_${categoryId}: ERROR ${e}`);
      }
      await sleep(500);
    }

    // ③ 인기 검색어 (카테고리별)
    for (const [name, id] of Object.entries(CATEGORY_MAP)) {
      try {
        const keywords = await fetchPopularKeywords(id, name);
        await writeCache(`popularKeywords_${id}`, keywords);
        results.push(`popularKeywords_${name}: ${keywords.length}`);
      } catch (e) {
        results.push(`popularKeywords_${name}: ERROR ${e}`);
      }
      await sleep(300);
    }

    res.json({ ok: true, results });
  }
);

/**
 * imageProxy: 웹에서 외부 이미지 CORS 우회
 * GET /imageProxy?url=https://...
 */
export const imageProxy = onRequest(
  {
    region: "asia-northeast3",
    cors: true,
  },
  async (req, res) => {
    const url = req.query.url as string;
    if (!url || !url.startsWith("http")) {
      res.status(400).send("Missing or invalid url");
      return;
    }

    try {
      const response = await fetch(url, {
        headers: {
          "User-Agent":
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36",
        },
      });

      if (!response.ok) {
        res.status(response.status).send("Upstream error");
        return;
      }

      const contentType =
        response.headers.get("content-type") || "image/jpeg";
      const buffer = await response.buffer();

      res.set("Access-Control-Allow-Origin", "*");
      res.set("Content-Type", contentType);
      res.set("Cache-Control", "public, max-age=86400");
      res.send(buffer);
    } catch {
      res.status(500).send("Proxy error");
    }
  }
);
