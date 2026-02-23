import * as admin from "firebase-admin";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { onRequest } from "firebase-functions/v2/https";
import { defineSecret } from "firebase-functions/params";
import fetch from "node-fetch";

import { ProductJson, PopularKeywordJson } from "./types";
import {
  CATEGORY_MAP,
  CATEGORY_NAME_MAP,
  BEST100_CATEGORIES,
  DELAYS,
  RATE_LIMIT,
  NAVER_CLIENT_ID,
  NAVER_CLIENT_SECRET,
  NAVER_SHOP_URL,
} from "./config";
import {
  sleep,
  dropRate,
  extractRawId,
  sanitizeDocId,
  writeProducts,
  writeCache,
  cleanupOldProducts,
  cleanupOldNotificationRecords,
} from "./utils";
import { backfillSubCategories, backfillSearchKeywords } from "./classify";
import {
  sendToTopic,
  sendToDevice,
  isQuietHour,
  matchCategory,
  checkPriceDrops,
  loadEligibleProfiles,
  checkKeywordPriceAlerts as checkKeywordPriceAlertsImpl,
} from "./notifications";
import {
  fetchTodayDeals,
  fetchBest100,
  fetchKeywordRank,
  fetchPopularKeywords,
  fetchShoppingLive,
  fetchNaverPromotions,
} from "./fetchers/naver";
import {
  fetch11stDeals,
  fetchGmarketDeals,
  fetchAuctionDeals,
  probeGianexSections,
} from "./fetchers/external";
import { fetchLotteonDeals } from "./fetchers/lotteon";
import { fetchSsgDeals } from "./fetchers/ssg";
import { refreshFeedData } from "./feed";

// SA key secret for FCM authentication in Gen 2 Cloud Functions
const ADMIN_SA_KEY = defineSecret("ADMIN_SA_KEY");

// Initialize with explicit credential if SA key is available (fixes FCM auth in Cloud Run)
function initAdmin() {
  if (admin.apps.length > 0) return;
  const saKeyJson = process.env.ADMIN_SA_KEY;
  if (saKeyJson) {
    try {
      const sa = JSON.parse(saKeyJson);
      admin.initializeApp({ credential: admin.credential.cert(sa) });
      return;
    } catch (e) {
      console.warn("[initAdmin] Failed to parse SA key, falling back to ADC:", e);
    }
  }
  admin.initializeApp();
}

initAdmin();

// ── Shared alert helper ──

async function sendTimeBoundAlert(
  candidates: ProductJson[],
  type: string,
  rateLimitMs: number,
  formatTitle: (deal: ProductJson) => string,
  extraTopics?: (deal: ProductJson, docId: string) => Promise<void>,
): Promise<void> {
  if (candidates.length === 0) return;

  // 기본 알림금지시간(22:00-08:00 KST) 동안 토픽 알림 차단
  if (isQuietHour(22, 8)) return;

  const db = admin.firestore();
  const sentRef = db.collection("sent_notifications");

  const recent = await sentRef
    .where("type", "==", type)
    .orderBy("timestamp", "desc")
    .limit(1)
    .get();
  const lastTime = recent.docs[0]?.data()?.timestamp?.toDate?.();
  if (lastTime && (Date.now() - lastTime.getTime()) < rateLimitMs) return;

  const sentSnap = await sentRef
    .where("type", "==", type)
    .orderBy("timestamp", "desc")
    .limit(200)
    .get();
  const sentIds = new Set(sentSnap.docs.map((d) => d.data().productId));

  for (const deal of candidates) {
    if (sentIds.has(deal.id)) continue;

    const title = formatTitle(deal);
    const rawId = extractRawId(deal.id);
    const docId = sanitizeDocId(rawId ?? deal.id);

    await sendToTopic(type, title, deal.title, type, docId);
    if (extraTopics) await extraTopics(deal, docId);

    await sentRef.add({
      productId: deal.id,
      type,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
    });
    break;
  }
}

// ──────────────────────────────────────────
// SYNC_TASKS (manualSync에서 루프 처리)
// ──────────────────────────────────────────

const SYNC_TASKS: {
  name: string;
  fn: () => Promise<unknown[]>;
  key: string;
  source?: string;
  keepCache?: boolean;
}[] = [
  { name: "todayDeals",      fn: fetchTodayDeals,      key: "todayDeals",        source: "todayDeal" },
  { name: "shoppingLive",    fn: fetchShoppingLive,     key: "shoppingLive",      source: "shoppingLive" },
  { name: "naverPromotions", fn: fetchNaverPromotions,  key: "naverPromotions",   source: "naverPromo" },
  { name: "11stDeals",       fn: fetch11stDeals,        key: "11stDeals",         source: "11st" },
  { name: "gmarketDeals",    fn: fetchGmarketDeals,     key: "gmarketDeals",      source: "gmarket" },
  { name: "auctionDeals",    fn: fetchAuctionDeals,     key: "auctionDeals",      source: "auction" },
  { name: "lotteonDeals",   fn: fetchLotteonDeals,     key: "lotteonDeals",      source: "lotteon" },
  { name: "ssgDeals",       fn: fetchSsgDeals,         key: "ssgDeals",          source: "ssg" },
  { name: "keywordRank",     fn: fetchKeywordRank,      key: "keywordRank", keepCache: true },
];

// ──────────────────────────────────────────
// Cloud Functions
// ──────────────────────────────────────────

export const syncDeals = onSchedule(
  {
    schedule: "every 15 minutes",
    timeZone: "Asia/Seoul",
    region: "asia-northeast3",
    timeoutSeconds: 120,
    secrets: ["GEMINI_API_KEY", "NAVER_CLIENT_ID", "NAVER_CLIENT_SECRET", ADMIN_SA_KEY],
  },
  async () => {
    initAdmin();
    const products = await fetchTodayDeals();
    console.log(`Fetched ${products.length} today deals`);

    await writeProducts(products, "todayDeal", { deleteStale: true });

    // ② 핫딜 알림 (시간당 최대 1건)
    const hotDeals = products.filter((p) => dropRate(p) >= 30);
    await sendTimeBoundAlert(
      hotDeals,
      "hotDeal",
      RATE_LIMIT.HOT_DEAL,
      (deal) => `🔥 핫딜 ${Math.round(dropRate(deal))}% 할인!`,
      async (deal, docId) => {
        const cat = await matchCategory(deal.title);
        if (cat && CATEGORY_MAP[cat]) {
          const title = `🔥 핫딜 ${Math.round(dropRate(deal))}% 할인!`;
          await sendToTopic(`hotDeal_${CATEGORY_MAP[cat]}`, title, deal.title, "hotDeal", docId);
        }
      },
    );

    // ③ 마감임박 알림 (시간당 최대 1건)
    const now = Date.now();
    const endingSoon = products.filter((p) => {
      if (!p.saleEndDate) return false;
      const endTime = new Date(p.saleEndDate).getTime();
      const diffMin = (endTime - now) / 60000;
      return diffMin > 0 && diffMin <= 60;
    });
    await sendTimeBoundAlert(
      endingSoon,
      "saleEnd",
      RATE_LIMIT.SALE_END,
      (deal) => {
        const endTime = new Date(deal.saleEndDate!).getTime();
        const minutesLeft = Math.round((endTime - now) / 60000);
        return `⏰ ${minutesLeft}분 후 마감!`;
      },
    );

    // ④ 오래된 발송 기록 정리 (7일 이상)
    await cleanupOldNotificationRecords();

    await cleanupOldProducts();
    await checkPriceDrops();
  }
);

export const syncBest100 = onSchedule(
  {
    schedule: "every 30 minutes",
    timeZone: "Asia/Seoul",
    region: "asia-northeast3",
    timeoutSeconds: 120,
    secrets: ["GEMINI_API_KEY"],
  },
  async () => {
    for (const categoryId of BEST100_CATEGORIES) {
      try {
        const catName = CATEGORY_NAME_MAP[categoryId];
        const products = await fetchBest100("PRODUCT_CLICK", categoryId, catName);
        await writeProducts(products, "best100");
        console.log(
          `Synced best100_${categoryId}: ${products.length} products`
        );
      } catch (e) {
        console.error(`Failed best100 ${categoryId}:`, e);
      }
      await sleep(DELAYS.BEST100_BETWEEN);
    }
  }
);

export const syncKeywords = onSchedule(
  {
    schedule: "every 60 minutes",
    timeZone: "Asia/Seoul",
    region: "asia-northeast3",
    timeoutSeconds: 120,
  },
  async () => {
    try {
      const keywords = await fetchKeywordRank();
      await writeCache("keywordRank", keywords);
      console.log(`Cached keywordRank: ${keywords.length} keywords`);
    } catch (e) {
      console.error("Failed keyword rank:", e);
    }

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
      await sleep(DELAYS.FETCH_BETWEEN);
    }
    await writeCache("popularKeywords_all", allKeywords);
  }
);

export const syncShoppingLive = onSchedule(
  {
    schedule: "every 10 minutes",
    timeZone: "Asia/Seoul",
    region: "asia-northeast3",
    timeoutSeconds: 60,
    secrets: ["GEMINI_API_KEY"],
  },
  async () => {
    try {
      const products = await fetchShoppingLive();
      await writeProducts(products, "shoppingLive", { deleteStale: true });
      console.log(`Synced shoppingLive: ${products.length} products`);
    } catch (e) {
      console.error("Failed shoppingLive:", e);
    }
  }
);

export const syncPromotions = onSchedule(
  {
    schedule: "every 30 minutes",
    timeZone: "Asia/Seoul",
    region: "asia-northeast3",
    timeoutSeconds: 60,
    secrets: ["GEMINI_API_KEY"],
  },
  async () => {
    try {
      const promos = await fetchNaverPromotions();
      await writeProducts(promos, "naverPromo", { deleteStale: true });
      console.log(`Synced naverPromotions: ${promos.length} products`);
    } catch (e) {
      console.error("Failed naverPromotions:", e);
    }
  }
);

const EXTERNAL_SOURCES = [
  { name: "11stDeals", fn: fetch11stDeals, source: "11st" },
  { name: "gmarketDeals", fn: fetchGmarketDeals, source: "gmarket" },
  { name: "auctionDeals", fn: fetchAuctionDeals, source: "auction" },
  { name: "lotteonDeals", fn: fetchLotteonDeals, source: "lotteon" },
  { name: "ssgDeals", fn: fetchSsgDeals, source: "ssg" },
] as const;

export const syncExternalDeals = onSchedule(
  {
    schedule: "every 15 minutes",
    timeZone: "Asia/Seoul",
    region: "asia-northeast3",
    timeoutSeconds: 120,
    secrets: ["GEMINI_API_KEY"],
  },
  async () => {
    for (let i = 0; i < EXTERNAL_SOURCES.length; i++) {
      const { name, fn, source } = EXTERNAL_SOURCES[i];
      try {
        const products = await fn();
        await writeProducts(products, source, { deleteStale: true });
        console.log(`Synced ${name}: ${products.length}`);
      } catch (e) {
        console.error(`Failed ${name}:`, e);
      }
      if (i < EXTERNAL_SOURCES.length - 1) await sleep(DELAYS.EXTERNAL_BETWEEN);
    }
  }
);

export const refreshFeed = onSchedule(
  {
    schedule: "every 60 minutes",
    timeZone: "Asia/Seoul",
    region: "asia-northeast3",
    timeoutSeconds: 120,
  },
  async () => {
    await refreshFeedData();
  }
);

export const dailyBest = onSchedule(
  {
    schedule: "0 9 * * *",
    timeZone: "Asia/Seoul",
    region: "asia-northeast3",
    secrets: [ADMIN_SA_KEY],
  },
  async () => {
    initAdmin();
    const snap = await admin
      .firestore()
      .collection("products")
      .orderBy("dropRate", "desc")
      .limit(5)
      .get();
    let products: ProductJson[] = snap.docs.map((d) => d.data() as ProductJson);

    if (products.length === 0) {
      products = (await fetchTodayDeals()).slice(0, 5);
    }
    if (products.length === 0) return;

    const db = admin.firestore();
    const today = new Date().toISOString().substring(0, 10);
    const sentRef = db.collection("sent_notifications");
    const existing = await sentRef
      .where("type", "==", "dailyBest")
      .where("dateKey", "==", today)
      .limit(1)
      .get();
    if (!existing.empty) return;

    const body = products
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

export const sendCategoryAlerts = onSchedule(
  {
    schedule: "every 2 hours",
    timeZone: "Asia/Seoul",
    region: "asia-northeast3",
    timeoutSeconds: 120,
    secrets: [ADMIN_SA_KEY],
  },
  async () => {
    initAdmin();
    const eligible = await loadEligibleProfiles({
      field: "enableCategoryAlert",
      rateLimitField: "lastCategoryAlertSentAt",
      rateLimitMs: RATE_LIMIT.CATEGORY_ALERT,
    });

    if (eligible.length === 0) return;

    const db = admin.firestore();
    let sentCount = 0;

    for (const { doc: profileDoc, token, tokenHash, profile } of eligible) {
      const catScores = (profile.categoryScores || {}) as Record<string, number>;
      if (Object.keys(catScores).length === 0) continue;

      const topCat = Object.entries(catScores)
        .sort(([, a], [, b]) => b - a)[0]?.[0];
      if (!topCat) continue;

      try {
        const dealSnap = await db
          .collection("products")
          .where("category", "==", topCat)
          .orderBy("dropRate", "desc")
          .limit(1)
          .get();

        if (dealSnap.empty) continue;

        const deal = dealSnap.docs[0].data();
        const rate = Math.round(deal.dropRate || 0);
        if (rate < 10) continue;

        const title = `🏷️ ${topCat} 핫딜 ${rate}% 할인!`;
        const body = deal.title as string;

        const sent = await sendToDevice(
          token, tokenHash, title, body, "categoryInterest", dealSnap.docs[0].id
        );
        if (sent) {
          await profileDoc.ref.update({
            lastCategoryAlertSentAt: admin.firestore.FieldValue.serverTimestamp(),
          });
          sentCount++;
        }
      } catch (e) {
        console.error(`[sendCategoryAlerts] error for ${tokenHash.substring(0, 8)}...:`, e);
      }
    }

    if (sentCount > 0) {
      console.log(`[sendCategoryAlerts] sent ${sentCount} category alerts`);
    }
  }
);

export const sendSmartDigests = onSchedule(
  {
    schedule: "5 9 * * *",
    timeZone: "Asia/Seoul",
    region: "asia-northeast3",
    timeoutSeconds: 120,
    secrets: [ADMIN_SA_KEY],
  },
  async () => {
    initAdmin();
    const eligible = await loadEligibleProfiles({
      field: "enableSmartDigest",
      rateLimitField: "lastDigestSentAt",
      rateLimitMs: RATE_LIMIT.SMART_DIGEST,
    });

    if (eligible.length === 0) return;

    const db = admin.firestore();
    let sentCount = 0;

    for (const { doc: profileDoc, token, tokenHash, profile } of eligible) {
      const catScores = (profile.categoryScores || {}) as Record<string, number>;
      if (Object.keys(catScores).length === 0) continue;

      const topCats = Object.entries(catScores)
        .sort(([, a], [, b]) => b - a)
        .slice(0, 3)
        .map(([cat]) => cat);

      const deals: { title: string; rate: number }[] = [];
      for (const cat of topCats) {
        try {
          const snap = await db
            .collection("products")
            .where("category", "==", cat)
            .orderBy("dropRate", "desc")
            .limit(1)
            .get();
          if (!snap.empty) {
            const d = snap.docs[0].data();
            deals.push({
              title: d.title as string,
              rate: Math.round(d.dropRate || 0),
            });
          }
        } catch (_) {}
      }

      if (deals.length === 0) continue;

      const body = deals
        .map((d, i) => `${i + 1}. ${d.title} (${d.rate}%↓)`)
        .join("\n");

      const sent = await sendToDevice(
        token, tokenHash, "✨ 오늘의 맞춤 추천", body, "smartDigest"
      );
      if (sent) {
        await profileDoc.ref.update({
          lastDigestSentAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        sentCount++;
      }
    }

    if (sentCount > 0) {
      console.log(`[sendSmartDigests] sent ${sentCount} smart digests`);
    }
  }
);

export const checkKeywordPriceAlerts = onSchedule(
  {
    schedule: "every 6 hours",
    timeZone: "Asia/Seoul",
    region: "asia-northeast3",
    timeoutSeconds: 300,
    secrets: ["NAVER_CLIENT_ID", "NAVER_CLIENT_SECRET", ADMIN_SA_KEY],
  },
  async () => {
    initAdmin();
    await checkKeywordPriceAlertsImpl();
  }
);

export const cleanupStaleProfiles = onSchedule(
  {
    schedule: "0 4 * * 0",
    timeZone: "Asia/Seoul",
    region: "asia-northeast3",
  },
  async () => {
    const db = admin.firestore();
    const cutoff = new Date();
    cutoff.setDate(cutoff.getDate() - 30);

    const staleSnap = await db
      .collection("device_profiles")
      .where("lastSyncedAt", "<", cutoff)
      .limit(200)
      .get();

    if (staleSnap.empty) {
      console.log("[cleanupStaleProfiles] no stale profiles");
      return;
    }

    const batch = db.batch();
    staleSnap.docs.forEach((d) => batch.delete(d.ref));
    await batch.commit();

    console.log(`[cleanupStaleProfiles] deleted ${staleSnap.size} stale profiles`);
  }
);

export const manualSync = onRequest(
  {
    region: "asia-northeast3",
    timeoutSeconds: 540,
    secrets: ["GEMINI_API_KEY", ADMIN_SA_KEY],
  },
  async (_req, res) => {
    initAdmin();
    const results: string[] = [];

    for (const task of SYNC_TASKS) {
      try {
        const items = await task.fn();
        if (task.keepCache) {
          await writeCache(task.key, items);
        }
        if (task.source) {
          await writeProducts(items as ProductJson[], task.source, { deleteStale: true });
        }
        results.push(`${task.name}: ${items.length}`);
      } catch (e) {
        results.push(`${task.name}: ERROR ${e}`);
      }
    }

    for (const categoryId of BEST100_CATEGORIES) {
      try {
        const catName = CATEGORY_NAME_MAP[categoryId];
        const products = await fetchBest100("PRODUCT_CLICK", categoryId, catName);
        await writeProducts(products, "best100");
        results.push(`best100_${categoryId}: ${products.length}`);
      } catch (e) {
        results.push(`best100_${categoryId}: ERROR ${e}`);
      }
      await sleep(DELAYS.BEST100_BETWEEN);
    }

    for (const [name, id] of Object.entries(CATEGORY_MAP)) {
      try {
        const keywords = await fetchPopularKeywords(id, name);
        await writeCache(`popularKeywords_${id}`, keywords);
        results.push(`popularKeywords_${name}: ${keywords.length}`);
      } catch (e) {
        results.push(`popularKeywords_${name}: ERROR ${e}`);
      }
      await sleep(DELAYS.FETCH_BETWEEN);
    }

    try {
      const backfilled = await backfillSubCategories();
      results.push(`backfill: ${backfilled}`);
    } catch (e) {
      results.push(`backfill: ERROR ${e}`);
    }

    try {
      const kwBackfilled = await backfillSearchKeywords();
      results.push(`backfillKeywords: ${kwBackfilled}`);
    } catch (e) {
      results.push(`backfillKeywords: ERROR ${e}`);
    }

    // sectionSeq 탐색 (G마켓: 1-20, 옥션: 1030-1050)
    try {
      const gmktSections = await probeGianexSections(1, 20);
      results.push(`probeGmarket: ${gmktSections.map((s) => `${s.seq}(${s.count})`).join(", ") || "none"}`);
      const auctionSections = await probeGianexSections(1030, 1050);
      results.push(`probeAuction: ${auctionSections.map((s) => `${s.seq}(${s.count})`).join(", ") || "none"}`);
    } catch (e) {
      results.push(`probeGianex: ERROR ${e}`);
    }

    try {
      await refreshFeedData();
      results.push("refreshFeed: OK");
    } catch (e) {
      results.push(`refreshFeed: ERROR ${e}`);
    }

    res.json({ ok: true, results });
  }
);

// FCM 테스트 엔드포인트 — 배포 후 알림 동작 확인용
export const testFcm = onRequest(
  {
    region: "asia-northeast3",
    secrets: [ADMIN_SA_KEY],
  },
  async (_req, res) => {
    initAdmin();
    const results: string[] = [];

    // 1. Check admin credential status
    try {
      const app = admin.app();
      results.push(`Admin app name: ${app.name}`);
      results.push(`Admin app projectId: ${app.options.projectId || "auto"}`);
    } catch (e) {
      results.push(`Admin app error: ${e}`);
    }

    // 2. Test Firestore (should work)
    try {
      const snap = await admin.firestore().collection("device_profiles").limit(1).get();
      results.push(`Firestore OK: ${snap.size} profile(s) found`);
      if (!snap.empty) {
        const profile = snap.docs[0].data();
        results.push(`  Token hash: ${(profile.tokenHash as string || "").substring(0, 8)}...`);
        results.push(`  Has FCM token: ${!!profile.fcmToken}`);
      }
    } catch (e) {
      results.push(`Firestore ERROR: ${e}`);
    }

    // 3. Test FCM topic send
    try {
      await admin.messaging().send({
        topic: "test_fcm_check",
        notification: { title: "FCM Test", body: "Test from testFcm endpoint" },
      }, true); // dryRun = true
      results.push("FCM dryRun OK: messaging auth works!");
    } catch (e: any) {
      results.push(`FCM dryRun ERROR: ${e?.message || e}`);
      results.push(`  Error code: ${e?.code || e?.errorInfo?.code || "?"}`);
    }

    res.json({ ok: true, results });
  }
);

export const productPage = onRequest(
  {
    region: "asia-northeast3",
    cors: true,
  },
  async (req, res) => {
    const pathParts = req.path.split("/").filter(Boolean);
    // /product/{encodedId} or just /{encodedId}
    const rawSegment = pathParts[pathParts.length - 1] || "";
    const originalId = decodeURIComponent(rawSegment);
    // Firestore doc ID는 extractRawId + sanitizeDocId로 변환됨
    const rawId = extractRawId(originalId);
    const productId = sanitizeDocId(rawId ?? originalId);

    let title = "굿딜 - 최저가 쇼핑";
    let description = "최저가 쇼핑 가격 추적 앱에서 이 상품을 확인해보세요!";
    let imageUrl = "https://gooddeal-app.web.app/og-default.png";
    let price = "";

    if (productId) {
      try {
        const doc = await admin.firestore().collection("products").doc(productId).get();
        if (doc.exists) {
          const data = doc.data()!;
          title = (data.title as string) || title;
          if (data.imageUrl) imageUrl = data.imageUrl as string;
          if (data.currentPrice) {
            price = `${Number(data.currentPrice).toLocaleString()}원`;
            description = `${price} - 굿딜에서 최저가 확인`;
          }
          if (data.dropRate && Number(data.dropRate) > 0) {
            description = `${Math.round(Number(data.dropRate))}% 할인 ${price} - 굿딜에서 최저가 확인`;
          }
        }
      } catch (e) {
        console.error("[productPage] Firestore error:", e);
      }
    }

    const esc = (s: string) => s.replace(/&/g, "&amp;").replace(/"/g, "&quot;").replace(/</g, "&lt;").replace(/>/g, "&gt;");

    const html = `<!DOCTYPE html>
<html lang="ko">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width,initial-scale=1.0">
  <title>${esc(title)} - 굿딜</title>
  <meta property="og:title" content="${esc(title)}" />
  <meta property="og:description" content="${esc(description)}" />
  <meta property="og:image" content="${esc(imageUrl)}" />
  <meta property="og:type" content="product" />
  <meta property="og:site_name" content="굿딜" />
  <meta name="twitter:card" content="summary_large_image" />
  <meta name="twitter:title" content="${esc(title)}" />
  <meta name="twitter:description" content="${esc(description)}" />
  <meta name="twitter:image" content="${esc(imageUrl)}" />
  <style>
    *{margin:0;padding:0;box-sizing:border-box}
    body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;background:#f5f5f5;display:flex;justify-content:center;align-items:center;min-height:100vh}
    .card{background:#fff;border-radius:16px;padding:40px 32px;max-width:360px;width:90%;text-align:center;box-shadow:0 4px 24px rgba(0,0,0,0.08)}
    .icon{font-size:48px;margin-bottom:16px}
    h1{font-size:20px;color:#222;margin-bottom:6px;line-height:1.4}
    .price{font-size:18px;color:#FF3B30;font-weight:700;margin-bottom:16px}
    p{font-size:14px;color:#888;margin-bottom:24px;line-height:1.5}
    .btn{display:inline-block;padding:14px 32px;border-radius:12px;background:#FF3B30;color:#fff;text-decoration:none;font-size:16px;font-weight:600}
    .btn:hover{background:#E0342A}
    .sub{font-size:12px;color:#aaa;margin-top:16px}
  </style>
  <script>
    var ua=navigator.userAgent.toLowerCase();
    var isIOS=/iphone|ipad|ipod/.test(ua);
    var isAndroid=/android/.test(ua);
    var storeUrl=isIOS?'https://apps.apple.com/kr/app/id6759038924':'https://play.google.com/store/apps/details?id=com.goooood.app';
    var isInApp=/kakaotalk|naver|line|instagram|fbav|twitter|wv\)/.test(ua);

    // 이 페이지가 로딩되었다는 것은 Universal Link/App Link로 앱이 열리지 않았다는 뜻.
    // → 앱 미설치이므로 스토어로 안내.
    window.onload=function(){
      var b=document.getElementById('store-btn');
      if(b)b.href=storeUrl;

      if(isInApp&&isAndroid){
        // Android 인앱 브라우저: intent로 외부 브라우저 시도 + 스토어 폴백
        location.href='intent://gooddeal-app.web.app'+location.pathname+'#Intent;scheme=https;package=com.goooood.app;S.browser_fallback_url='+encodeURIComponent(storeUrl)+';end';
      }
      // iOS/Android 모두: 1.5초 후 스토어로 리다이렉트
      if(isIOS||isAndroid){
        setTimeout(function(){location.href=storeUrl},1500);
      }
    };
  </script>
</head>
<body>
  <div class="card">
    <div class="icon">🛍️</div>
    <h1>${esc(title)}</h1>
    ${price ? `<div class="price">${esc(price)}</div>` : ""}
    <p>굿딜 앱에서 확인해보세요!</p>
    <a id="store-btn" class="btn" href="https://apps.apple.com/kr/app/id6759038924">앱에서 보기</a>
    <p class="sub">앱이 설치되어 있다면 자동으로 열립니다</p>
  </div>
</body>
</html>`;

    res.set("Cache-Control", "public, max-age=300");
    res.status(200).send(html);
  }
);

export const naverProxy = onRequest(
  {
    region: "asia-northeast3",
    cors: true,
    secrets: ["NAVER_CLIENT_ID", "NAVER_CLIENT_SECRET"],
  },
  async (req, res) => {
    const action = (req.query.action || req.body?.action) as string | undefined;
    const naverHeaders: Record<string, string> = {
      "X-Naver-Client-Id": NAVER_CLIENT_ID,
      "X-Naver-Client-Secret": NAVER_CLIENT_SECRET,
    };

    if (action === "search") {
      const { query, display, start, sort } = req.query as Record<string, string>;
      if (!query) {
        res.status(400).json({ error: "missing query parameter" });
        return;
      }
      const params = new URLSearchParams({ query, display: display || "20", start: start || "1", sort: sort || "sim" });
      const url = `${NAVER_SHOP_URL}?${params}`;
      const resp = await fetch(url, { headers: naverHeaders });
      const data = await resp.json();
      res.status(resp.status).json(data);
    } else if (action === "trend") {
      const payload = req.body?.payload;
      if (!payload) {
        res.status(400).json({ error: "missing payload in body" });
        return;
      }
      const resp = await fetch("https://openapi.naver.com/v1/datalab/search", {
        method: "POST",
        headers: { ...naverHeaders, "Content-Type": "application/json" },
        body: JSON.stringify(payload),
      });
      const data = await resp.json();
      res.status(resp.status).json(data);
    } else {
      res.status(400).json({ error: "invalid action: use 'search' or 'trend'" });
    }
  }
);

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
