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
  generateSearchKeywords,
} from "./classify";

// ── Pure utilities ──

export const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

export function chunkArray<T>(arr: T[], size: number): T[][] {
  const chunks: T[][] = [];
  for (let i = 0; i < arr.length; i += size) {
    chunks.push(arr.slice(i, i + size));
  }
  return chunks;
}

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

function getDocId(p: ProductJson): string {
  const rawId = extractRawId(p.id);
  return sanitizeDocId(rawId ?? p.id);
}

function deduplicateAndFilter(
  products: ProductJson[],
  source: string
): ProductJson[] {
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

  const now = Date.now();
  const deduped = [...bestByRawId.values(), ...noRawId];
  const unique = deduped.filter((p) => {
    if (!p.saleEndDate) return true;
    try { return new Date(p.saleEndDate).getTime() >= now; }
    catch { return true; }
  });
  const expiredSkipped = deduped.length - unique.length;
  if (expiredSkipped > 0) {
    console.log(`[writeProducts] ${source}: skipped ${expiredSkipped} expired products`);
  }
  return unique;
}

async function loadExistingData(
  unique: ProductJson[],
  db: FirebaseFirestore.Firestore
): Promise<{
  existingCategoryMap: Map<string, CategoryResult>;
  existingKeywordsMap: Map<string, string[]>;
}> {
  const docIds = unique.map((p) => getDocId(p));
  const docRefs = docIds.map((id) => db.collection("products").doc(id));
  const existingDocs = docRefs.length > 0 ? await db.getAll(...docRefs) : [];

  const existingCategoryMap = new Map<string, CategoryResult>();
  const existingKeywordsMap = new Map<string, string[]>();

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
    const kws = data.searchKeywords;
    if (Array.isArray(kws) && kws.length > 0) {
      existingKeywordsMap.set(doc.id, kws);
    }
  }

  return { existingCategoryMap, existingKeywordsMap };
}

async function classifyAll(
  unique: ProductJson[],
  existingCategoryMap: Map<string, CategoryResult>
): Promise<Map<ProductJson, CategoryResult>> {
  const classifyResult = new Map<ProductJson, CategoryResult>();
  const needsFullAI: ProductJson[] = [];
  const needsSubAI: ProductJson[] = [];

  for (const p of unique) {
    const cached = existingCategoryMap.get(getDocId(p));
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

  if (needsFullAI.length > 0) {
    for (let i = 0; i < needsFullAI.length; i += AI_FULL_BATCH) {
      const aiBatch = needsFullAI.slice(i, i + AI_FULL_BATCH);
      const titles = aiBatch.map((p) => p.title);
      const results = await classifyWithGemini(titles);
      aiBatch.forEach((p, idx) => classifyResult.set(p, results[idx]));
      if (i + AI_FULL_BATCH < needsFullAI.length) await sleep(DELAYS.AI_BATCH);
    }
  }

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

  return classifyResult;
}

async function generateAllKeywords(
  unique: ProductJson[],
  existingKeywordsMap: Map<string, string[]>
): Promise<Map<ProductJson, string[]>> {
  const keywordsResult = new Map<ProductJson, string[]>();
  const needsKeywords: ProductJson[] = [];

  for (const p of unique) {
    const cached = existingKeywordsMap.get(getDocId(p));
    if (cached) {
      keywordsResult.set(p, cached);
    } else {
      needsKeywords.push(p);
    }
  }

  if (needsKeywords.length > 0) {
    for (let i = 0; i < needsKeywords.length; i += AI_SUB_BATCH) {
      const kwBatch = needsKeywords.slice(i, i + AI_SUB_BATCH);
      const items = kwBatch.map((p) => ({
        title: p.title,
        brand: p.brand,
        category1: p.category1,
        category2: p.category2,
        category3: p.category3,
      }));
      const kws = await generateSearchKeywords(items);
      kwBatch.forEach((p, idx) => keywordsResult.set(p, kws[idx]));
      if (i + AI_SUB_BATCH < needsKeywords.length) await sleep(DELAYS.AI_SUB_BATCH);
    }
  }

  return keywordsResult;
}

export async function writeProducts(
  products: ProductJson[],
  source: string
): Promise<number> {
  if (products.length === 0) return 0;

  const unique = deduplicateAndFilter(products, source);
  const db = admin.firestore();

  const { existingCategoryMap, existingKeywordsMap } = await loadExistingData(unique, db);
  const classifyResult = await classifyAll(unique, existingCategoryMap);
  const keywordsResult = await generateAllKeywords(unique, existingKeywordsMap);

  // ── Firestore 저장 ──
  let written = 0;

  for (const chunk of chunkArray(unique, FIRESTORE_BATCH_LIMIT)) {
    const batch = db.batch();

    for (const p of chunk) {
      const docId = getDocId(p);
      const ref = db.collection("products").doc(docId);
      const cr = classifyResult.get(p) || DEFAULT_CATEGORY_RESULT;
      const kws = keywordsResult.get(p) || [];

      batch.set(ref, {
        ...p,
        category: cr.category,
        subCategory: cr.subCategory,
        ...(kws.length > 0 ? { searchKeywords: kws } : {}),
        dropRate: dropRate(p),
        source,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }

    await batch.commit();
    written += chunk.length;
  }

  const needsFullAI = unique.filter((p) => !existingCategoryMap.has(getDocId(p)) && !mapToAppCategory(p.category1, p.category2, p.category3));
  const needsSubAI = unique.filter((p) => !existingCategoryMap.has(getDocId(p)) && mapToAppCategory(p.category1, p.category2, p.category3));
  const needsKeywords = unique.filter((p) => !existingKeywordsMap.has(getDocId(p)));
  const skipped = unique.length - needsFullAI.length - needsSubAI.length;
  console.log(
    `[writeProducts] ${source}: ${written} products (${needsFullAI.length} full-AI, ${needsSubAI.length} sub-AI, ${skipped} cached, ${needsKeywords.length} keywords-gen)`
  );
  return written;
}

export async function cleanupOldNotificationRecords(): Promise<void> {
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

export async function cleanupOldProducts(): Promise<number> {
  const db = admin.firestore();
  const cutoff = new Date();
  cutoff.setHours(cutoff.getHours() - 24);

  let totalDeleted = 0;
  const MAX_ROUNDS = 5;

  // 1) updatedAt 기준 24시간 지난 상품 삭제
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

  // 2) saleEndDate가 지난 상품 삭제
  //    saleEndDate는 ISO 문자열. 범위 쿼리로 null은 자동 제외됨.
  const nowIso = new Date().toISOString();
  let expiredDeleted = 0;

  for (let round = 0; round < MAX_ROUNDS; round++) {
    const expiredSnap = await db
      .collection("products")
      .where("saleEndDate", ">", "")
      .where("saleEndDate", "<", nowIso)
      .limit(CLEANUP_BATCH_LIMIT)
      .get();

    if (expiredSnap.empty) break;

    const batch = db.batch();
    expiredSnap.docs.forEach((d) => batch.delete(d.ref));
    await batch.commit();
    expiredDeleted += expiredSnap.size;

    if (expiredSnap.size < CLEANUP_BATCH_LIMIT) break;
  }

  totalDeleted += expiredDeleted;

  if (totalDeleted > 0) {
    console.log(`[cleanup] Deleted ${totalDeleted} products (${expiredDeleted} expired by saleEndDate)`);
  }
  return totalDeleted;
}
