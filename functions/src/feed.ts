import * as admin from "firebase-admin";
import { VALID_CATEGORIES } from "./types";
import { FIRESTORE_BATCH_LIMIT } from "./config";

// ──────────────────────────────────────────
// balancedShuffle: 소스별 균등 배분 + Fisher-Yates 셔플
// ──────────────────────────────────────────

interface HasSource {
  source?: string;
  [key: string]: unknown;
}

function fisherYatesShuffle<T>(arr: T[]): T[] {
  const a = [...arr];
  for (let i = a.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [a[i], a[j]] = [a[j], a[i]];
  }
  return a;
}

function balancedShuffle<T extends HasSource>(items: T[]): T[] {
  // 1) 소스별 그룹핑
  const groups = new Map<string, T[]>();
  for (const item of items) {
    const src = item.source || "other";
    if (!groups.has(src)) groups.set(src, []);
    groups.get(src)!.push(item);
  }

  // 2) 각 소스 내부 셔플
  for (const list of groups.values()) {
    const shuffled = fisherYatesShuffle(list);
    list.length = 0;
    list.push(...shuffled);
  }

  // 3) 라운드로빈으로 판매처 균등 배분
  const result: T[] = [];
  const sources = fisherYatesShuffle(
    [...groups.values()].filter((l) => l.length > 0)
  );

  const maxLen = Math.max(...sources.map((l) => l.length));
  for (let i = 0; i < maxLen; i++) {
    for (const list of sources) {
      if (i < list.length) {
        result.push(list[i]);
      }
    }
  }

  return result;
}

// ──────────────────────────────────────────
// refreshFeedData: feedOrder / categoryFeedOrder 일괄 계산
// ──────────────────────────────────────────

export async function refreshFeedData(): Promise<void> {
  const db = admin.firestore();

  // 1) dropRate > 0 인 전체 상품 조회
  const snap = await db
    .collection("products")
    .where("dropRate", ">", 0)
    .get();

  if (snap.empty) {
    console.log("[refreshFeedData] no products with dropRate > 0");
    return;
  }

  interface ProductDoc {
    id: string;
    source?: string;
    category?: string;
    [key: string]: unknown;
  }

  const allDocs: { ref: admin.firestore.DocumentReference; data: ProductDoc }[] = [];
  snap.forEach((doc) => {
    allDocs.push({ ref: doc.ref, data: { id: doc.id, ...doc.data() } as ProductDoc });
  });

  console.log(`[refreshFeedData] loaded ${allDocs.length} products`);

  // 2) 글로벌 feedOrder: 전체 상품을 balancedShuffle 후 순번 할당
  const globalShuffled = balancedShuffle(allDocs.map((d) => d.data));
  const globalOrderMap = new Map<string, number>();
  globalShuffled.forEach((item, idx) => {
    globalOrderMap.set(item.id, idx);
  });

  // 3) 카테고리별 categoryFeedOrder
  const categoryOrderMap = new Map<string, number>();

  for (const cat of VALID_CATEGORIES) {
    const catDocs = allDocs
      .filter((d) => d.data.category === cat)
      .map((d) => d.data);

    if (catDocs.length === 0) continue;

    const catShuffled = balancedShuffle(catDocs);
    catShuffled.forEach((item, idx) => {
      categoryOrderMap.set(item.id, idx);
    });
  }

  // 4) 500개 단위 batch update
  const chunks: typeof allDocs[] = [];
  for (let i = 0; i < allDocs.length; i += FIRESTORE_BATCH_LIMIT) {
    chunks.push(allDocs.slice(i, i + FIRESTORE_BATCH_LIMIT));
  }

  let updated = 0;
  for (const chunk of chunks) {
    const batch = db.batch();
    for (const { ref, data } of chunk) {
      const feedOrder = globalOrderMap.get(data.id) ?? -1;
      const categoryFeedOrder = categoryOrderMap.get(data.id) ?? -1;
      batch.update(ref, { feedOrder, categoryFeedOrder });
    }
    await batch.commit();
    updated += chunk.length;
  }

  console.log(`[refreshFeedData] updated ${updated} products with feedOrder`);
}
