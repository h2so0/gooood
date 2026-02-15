// ──────────────────────────────────────────
// FCM notifications + personalized alerts
// ──────────────────────────────────────────

import * as admin from "firebase-admin";
import fetch from "node-fetch";
import { ProductJson } from "./types";
import {
  NAVER_CLIENT_ID,
  NAVER_CLIENT_SECRET,
  NAVER_SHOP_URL,
  CATEGORY_MAP,
} from "./config";
import { dropRate, extractRawId, sanitizeDocId } from "./utils";

// ── Quiet hour & FCM helpers ──

export function isQuietHour(quietStart: number, quietEnd: number): boolean {
  const now = new Date();
  const kstHour = (now.getUTCHours() + 9) % 24;
  if (quietStart <= quietEnd) {
    return kstHour >= quietStart && kstHour < quietEnd;
  }
  return kstHour >= quietStart || kstHour < quietEnd;
}

export async function sendToDevice(
  token: string,
  tokenHash: string,
  title: string,
  body: string,
  type: string,
  productId?: string
): Promise<boolean> {
  try {
    await admin.messaging().send({
      token,
      notification: { title, body },
      data: {
        type,
        ...(productId ? { productId } : {}),
      },
      android: {
        priority: "high",
        notification: { channelId: "personalized" },
      },
      apns: {
        payload: { aps: { sound: "default" } },
      },
    });
    return true;
  } catch (e: any) {
    const code = e?.code || e?.errorInfo?.code || "";
    if (
      code === "messaging/registration-token-not-registered" ||
      code === "messaging/invalid-registration-token"
    ) {
      try {
        await admin.firestore()
          .collection("device_profiles")
          .doc(tokenHash)
          .delete();
        console.log(`[sendToDevice] deleted stale profile: ${tokenHash.substring(0, 8)}...`);
      } catch (_) {}
    } else {
      console.error(`[sendToDevice] FCM error for ${tokenHash.substring(0, 8)}...:`, e);
    }
    return false;
  }
}

export async function sendToTopic(
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

// ── Profile loading helper ──

interface EligibleProfile {
  doc: FirebaseFirestore.QueryDocumentSnapshot;
  token: string;
  tokenHash: string;
  profile: FirebaseFirestore.DocumentData;
}

/**
 * Load device profiles matching a filter, applying rate limit and quiet hour checks.
 */
export async function loadEligibleProfiles(filter: {
  field: string;
  rateLimitField: string;
  rateLimitMs: number;
}): Promise<EligibleProfile[]> {
  const db = admin.firestore();
  const cutoff = new Date(Date.now() - filter.rateLimitMs);

  const profilesSnap = await db
    .collection("device_profiles")
    .where(filter.field, "==", true)
    .get();

  if (profilesSnap.empty) return [];

  const eligible: EligibleProfile[] = [];

  for (const profileDoc of profilesSnap.docs) {
    const profile = profileDoc.data();
    const token = profile.fcmToken as string;
    const tokenHash = profile.tokenHash as string;

    // Rate limit
    const lastSent = profile[filter.rateLimitField]?.toDate?.();
    if (lastSent && lastSent > cutoff) continue;

    // Quiet hour check
    if (isQuietHour(profile.quietStartHour ?? 22, profile.quietEndHour ?? 8)) continue;

    eligible.push({ doc: profileDoc, token, tokenHash, profile });
  }

  return eligible;
}

// ── Category matching (for notifications) ──

export async function matchCategory(title: string): Promise<string | null> {
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

// ── Price drop alerts ──

export async function checkPriceDrops(): Promise<void> {
  const db = admin.firestore();
  const oneHourAgo = new Date(Date.now() - 3600000);

  const profilesSnap = await db
    .collection("device_profiles")
    .where("enablePriceDrop", "==", true)
    .get();

  if (profilesSnap.empty) return;

  // 전체 디바이스의 watchedProductIds를 수집 → unique Set → 배치 조회
  const allProductIds = new Set<string>();
  for (const profileDoc of profilesSnap.docs) {
    const profile = profileDoc.data();
    const watchedIds = (profile.watchedProductIds || []) as string[];
    for (const id of watchedIds.slice(0, 10)) {
      allProductIds.add(id);
    }
  }

  // 배치 조회: db.getAll()로 1회에 모든 상품 조회
  const productCache = new Map<string, FirebaseFirestore.DocumentData>();
  if (allProductIds.size > 0) {
    const refs = [...allProductIds].map((id) => db.collection("products").doc(id));
    const docs = await db.getAll(...refs);
    for (const doc of docs) {
      if (doc.exists) {
        productCache.set(doc.id, doc.data()!);
      }
    }
  }

  let sentCount = 0;

  for (const profileDoc of profilesSnap.docs) {
    const profile = profileDoc.data();
    const token = profile.fcmToken as string;
    const tokenHash = profile.tokenHash as string;

    const lastSent = profile.lastPriceDropSentAt?.toDate?.();
    if (lastSent && lastSent > oneHourAgo) continue;

    if (isQuietHour(profile.quietStartHour ?? 22, profile.quietEndHour ?? 8)) continue;

    const watchedIds = (profile.watchedProductIds || []) as string[];
    const snapshots = (profile.priceSnapshots || {}) as Record<string, number>;
    if (watchedIds.length === 0) continue;

    for (const productId of watchedIds.slice(0, 10)) {
      const oldPrice = snapshots[productId];
      if (!oldPrice || oldPrice <= 0) continue;

      const prodData = productCache.get(productId);
      if (!prodData) continue;

      const currentPrice = prodData.currentPrice as number;
      if (!currentPrice || currentPrice <= 0) continue;

      const dropPct = ((oldPrice - currentPrice) / oldPrice) * 100;
      if (dropPct >= 5) {
        const title = `📉 가격 ${Math.round(dropPct)}% 하락!`;
        const body = prodData.title as string;

        const sent = await sendToDevice(token, tokenHash, title, body, "priceDrop", productId);
        if (sent) {
          await profileDoc.ref.update({
            lastPriceDropSentAt: admin.firestore.FieldValue.serverTimestamp(),
          });
          sentCount++;
          break;
        }
      }
    }
  }

  if (sentCount > 0) {
    console.log(`[checkPriceDrops] sent ${sentCount} price drop alerts`);
  }
}
