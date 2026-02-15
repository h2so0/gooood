// ──────────────────────────────────────────
// Shared utilities + Firestore write helpers
// ──────────────────────────────────────────

import * as admin from "firebase-admin";
import {
  ProductJson,
  CategoryResult,
  VALID_CATEGORIES,
  SUB_CATEGORIES,
  DEFAULT_CATEGORY_RESULT,
} from "./types";
import {
  AI_FULL_BATCH,
  AI_SUB_BATCH,
  FIRESTORE_BATCH_LIMIT,
  CLEANUP_BATCH_LIMIT,
  DELAYS,
} from "./config";
import {
  mapToAppCategory,
  classifyWithGemini,
  classifySubCategoryWithGemini,
} from "./classify";

// ── Pure utilities ──

export const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

export function dropRate(p: ProductJson): number {
  if (!p.previousPrice || p.previousPrice <= 0) return 0;
  return ((p.previousPrice - p.currentPrice) / p.previousPrice) * 100;
}

export function sortByDropRate(products: ProductJson[]): void {
  products.sort((a, b) => dropRate(b) - dropRate(a));
}

export function extractRawId(id: string): string | null {
  for (const prefix of ["deal_", "best_", "live_", "promo_"]) {
    if (id.startsWith(prefix)) return `naver_${id.substring(prefix.length)}`;
  }
  if (id.startsWith("gmkt_")) return `gianex_${id.substring(5)}`;
  if (id.startsWith("auction_")) return `gianex_${id.substring(8)}`;
  return null;
}

export function sanitizeDocId(id: string): string {
  return id.replace(/[\/\.\#\$\[\]]/g, "_");
}

/** Extract __NEXT_DATA__ JSON from an HTML page */
export function extractNextData(html: string): any | null {
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

export async function writeCache(docId: string, items: unknown[]): Promise<void> {
  await admin.firestore().collection("cache").doc(docId).set({
    items,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });
}

// ── Firestore product write + dedup + classify ──

export async function writeProducts(
  products: ProductJson[],
  source: string
): Promise<number> {
  if (products.length === 0) return 0;

  // rawId 기준 중복 제거 (높은 dropRate 우선)
  const bestByRawId = new Map<string, ProductJson>();
  const noRawId: ProductJson[] = [];

  for (const p of products) {
    const rawId = extractRawId(p.id);
    if (rawId) {
      const existing = bestByRawId.get(rawId);
      if (!existing || dropRate(p) > dropRate(existing)) {
        bestByRawId.set(rawId, p);
      }
    } else {
      noRawId.push(p);
    }
  }

  const unique = [...bestByRawId.values(), ...noRawId];

  // ── 기존 상품 Firestore 배치 조회 (AI 중복 호출 방지) ──
  const db = admin.firestore();
  const docIdMap = new Map<string, ProductJson>();
  for (const p of unique) {
    const rawId = extractRawId(p.id);
    const docId = sanitizeDocId(rawId ?? p.id);
    docIdMap.set(docId, p);
  }

  const docRefs = [...docIdMap.keys()].map((id) =>
    db.collection("products").doc(id)
  );
  const existingDocs = docRefs.length > 0 ? await db.getAll(...docRefs) : [];
  const existingCategoryMap = new Map<string, CategoryResult>();
  for (const doc of existingDocs) {
    if (!doc.exists) continue;
    const data = doc.data()!;
    const cat = data.category as string | undefined;
    const sub = data.subCategory as string | undefined;
    if (cat && sub && VALID_CATEGORIES.includes(cat)) {
      const validSubs = SUB_CATEGORIES[cat] || [];
      if (validSubs.includes(sub)) {
        existingCategoryMap.set(doc.id, { category: cat, subCategory: sub });
      }
    }
  }

  // ── 카테고리 분류 ──
  const classifyResult = new Map<ProductJson, CategoryResult>();
  const needsFullAI: ProductJson[] = [];
  const needsSubAI: ProductJson[] = [];

  for (const p of unique) {
    const rawId = extractRawId(p.id);
    const docId = sanitizeDocId(rawId ?? p.id);

    const cached = existingCategoryMap.get(docId);
    if (cached) {
      classifyResult.set(p, cached);
      continue;
    }

    const result = mapToAppCategory(p.category1, p.category2, p.category3);
    if (result) {
      classifyResult.set(p, result);
      needsSubAI.push(p);
    } else {
      needsFullAI.push(p);
    }
  }

  // 2단계: 대+중 카테고리 모두 필요한 상품 → Gemini 풀분류
  if (needsFullAI.length > 0) {
    for (let i = 0; i < needsFullAI.length; i += AI_FULL_BATCH) {
      const aiBatch = needsFullAI.slice(i, i + AI_FULL_BATCH);
      const titles = aiBatch.map((p) => p.title);
      const results = await classifyWithGemini(titles);
      aiBatch.forEach((p, idx) => {
        classifyResult.set(p, results[idx]);
      });
      if (i + AI_FULL_BATCH < needsFullAI.length) await sleep(DELAYS.AI_BATCH);
    }
  }

  // 3단계: 대카테고리 확정된 상품 → Gemini 중카테고리만 분류
  if (needsSubAI.length > 0) {
    for (let i = 0; i < needsSubAI.length; i += AI_SUB_BATCH) {
      const aiBatch = needsSubAI.slice(i, i + AI_SUB_BATCH);
      const items = aiBatch.map((p) => ({
        title: p.title,
        category: classifyResult.get(p)!.category,
      }));
      const subs = await classifySubCategoryWithGemini(items);
      aiBatch.forEach((p, idx) => {
        const existing = classifyResult.get(p)!;
        classifyResult.set(p, { category: existing.category, subCategory: subs[idx] });
      });
      if (i + AI_SUB_BATCH < needsSubAI.length) await sleep(DELAYS.AI_SUB_BATCH);
    }
  }

  // ── Firestore 저장 ──
  let written = 0;

  for (let i = 0; i < unique.length; i += FIRESTORE_BATCH_LIMIT) {
    const batch = db.batch();
    const chunk = unique.slice(i, i + FIRESTORE_BATCH_LIMIT);

    for (const p of chunk) {
      const rawId = extractRawId(p.id);
      const docId = sanitizeDocId(rawId ?? p.id);
      const ref = db.collection("products").doc(docId);
      const cr = classifyResult.get(p) || DEFAULT_CATEGORY_RESULT;

      batch.set(ref, {
        ...p,
        category: cr.category,
        subCategory: cr.subCategory,
        dropRate: dropRate(p),
        source,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }

    await batch.commit();
    written += chunk.length;
  }

  const skipped = unique.length - needsFullAI.length - needsSubAI.length;
  console.log(
    `[writeProducts] ${source}: ${written} products (${needsFullAI.length} full-AI, ${needsSubAI.length} sub-AI, ${skipped} cached)`
  );
  return written;
}

export async function cleanupOldProducts(): Promise<number> {
  const db = admin.firestore();
  const cutoff = new Date();
  cutoff.setHours(cutoff.getHours() - 24);

  let totalDeleted = 0;
  const MAX_ROUNDS = 5;

  for (let round = 0; round < MAX_ROUNDS; round++) {
    const oldSnap = await db
      .collection("products")
      .where("updatedAt", "<", cutoff)
      .limit(CLEANUP_BATCH_LIMIT)
      .get();

    if (oldSnap.empty) break;

    const batch = db.batch();
    oldSnap.docs.forEach((d) => batch.delete(d.ref));
    await batch.commit();
    totalDeleted += oldSnap.size;

    if (oldSnap.size < CLEANUP_BATCH_LIMIT) break;
  }

  if (totalDeleted > 0) {
    console.log(`[cleanup] Deleted ${totalDeleted} old products`);
  }
  return totalDeleted;
}
