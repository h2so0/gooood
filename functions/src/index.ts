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
  const match = html.match(
    /<script id="__NEXT_DATA__" type="application\/json">(.*?)<\/script>/
  );
  if (!match) return [];

  const nextData = JSON.parse(match[1]);
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

  products.sort((a, b) => dropRate(b) - dropRate(a));
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

  products.sort((a, b) => dropRate(b) - dropRate(a));
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

    // ① 오늘의딜
    try {
      const deals = await fetchTodayDeals();
      await writeCache("todayDeals", deals);
      results.push(`todayDeals: ${deals.length}`);
    } catch (e) {
      results.push(`todayDeals: ERROR ${e}`);
    }

    // ② BEST100
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

    // ③ 키워드
    try {
      const keywords = await fetchKeywordRank();
      await writeCache("keywordRank", keywords);
      results.push(`keywordRank: ${keywords.length}`);
    } catch (e) {
      results.push(`keywordRank: ERROR ${e}`);
    }

    // ④ 인기 검색어
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
