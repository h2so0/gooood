import * as admin from "firebase-admin";

/**
 * Firestore 컬렉션들을 집계하여 cache/admin_stats 문서에 작성
 */
export async function aggregateAdminStats(): Promise<void> {
  const db = admin.firestore();
  const now = new Date();

  // ── 유저 통계 ──
  const profilesSnap = await db.collection("device_profiles").get();
  const totalUsers = profilesSnap.size;
  let iosCount = 0;
  let androidCount = 0;
  let activeToday = 0;
  let active7d = 0;
  let active30d = 0;
  let totalKeywordWishlistItems = 0;
  const keywordCounts: Record<string, number> = {};

  const todayCutoff = new Date(now);
  todayCutoff.setHours(0, 0, 0, 0);
  const day7Cutoff = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000);
  const day30Cutoff = new Date(now.getTime() - 30 * 24 * 60 * 60 * 1000);

  for (const doc of profilesSnap.docs) {
    const data = doc.data();

    // Platform
    if (data.platform === "ios") iosCount++;
    else androidCount++;

    // Active users by lastSyncedAt
    const lastSynced = data.lastSyncedAt?.toDate?.();
    if (lastSynced) {
      if (lastSynced >= todayCutoff) activeToday++;
      if (lastSynced >= day7Cutoff) active7d++;
      if (lastSynced >= day30Cutoff) active30d++;
    }

    // Keyword wishlist
    const wishlist = data.keywordWishlist;
    if (Array.isArray(wishlist)) {
      totalKeywordWishlistItems += wishlist.length;
      for (const item of wishlist) {
        const kw = item?.keyword;
        if (typeof kw === "string" && kw) {
          keywordCounts[kw] = (keywordCounts[kw] || 0) + 1;
        }
      }
    }
  }

  // Top 10 keywords
  const topKeywords = Object.entries(keywordCounts)
    .sort(([, a], [, b]) => b - a)
    .slice(0, 10)
    .map(([keyword, count]) => ({ keyword, count }));

  // ── 상품 통계 ──
  const productsSnap = await db.collection("products").get();
  const totalProducts = productsSnap.size;
  const sourceDist: Record<string, number> = {};
  const categoryDist: Record<string, number> = {};

  for (const doc of productsSnap.docs) {
    const data = doc.data();
    const source = (data.source as string) || "unknown";
    sourceDist[source] = (sourceDist[source] || 0) + 1;
    const cat = (data.category as string) || "기타";
    categoryDist[cat] = (categoryDist[cat] || 0) + 1;
  }

  // ── 알림 통계 ──
  const notif24hCutoff = new Date(now.getTime() - 24 * 60 * 60 * 1000);
  const notifSnap = await db
    .collection("sent_notifications")
    .where("timestamp", ">=", notif24hCutoff)
    .get();
  const notifTotal24h = notifSnap.size;
  const notifTypeDist: Record<string, number> = {};
  for (const doc of notifSnap.docs) {
    const type = (doc.data().type as string) || "unknown";
    notifTypeDist[type] = (notifTypeDist[type] || 0) + 1;
  }

  // ── 배너 클릭 ──
  let banners: Record<string, unknown> = {};
  try {
    const bannerDoc = await db.collection("cache").doc("banner_clicks").get();
    if (bannerDoc.exists) {
      banners = bannerDoc.data() || {};
    }
  } catch (_) {
    // banner_clicks may not exist yet
  }

  // ── 결과 작성 ──
  const stats = {
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    users: {
      total: totalUsers,
      ios: iosCount,
      android: androidCount,
      activeToday,
      active7d,
      active30d,
    },
    products: {
      total: totalProducts,
      bySource: sourceDist,
      byCategory: categoryDist,
    },
    notifications: {
      last24h: notifTotal24h,
      byType: notifTypeDist,
    },
    wishlist: {
      totalItems: totalKeywordWishlistItems,
      topKeywords,
    },
    banners,
  };

  await db.collection("cache").doc("admin_stats").set(stats);
  console.log("[aggregateAdminStats] done", {
    users: totalUsers,
    products: totalProducts,
    notif24h: notifTotal24h,
  });
}
