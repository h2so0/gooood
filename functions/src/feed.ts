import * as admin from "firebase-admin";
import { VALID_CATEGORIES } from "./types";
import {
  FIRESTORE_BATCH_LIMIT,
  SOURCE_QUOTA,
  NAVER_SOURCES,
  NAVER_MAX_TOTAL_RATIO,
  EXTERNAL_SOURCES_LIST,
  EXTERNAL_MIN_TOTAL_RATIO,
} from "./config";

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

  // 3) 비례 분산: 소수 소스도 전체 피드에 걸쳐 균등 배치
  const total = items.length;
  const positioned: { item: T; idx: number }[] = [];

  for (const list of groups.values()) {
    if (list.length === 0) continue;
    const step = total / list.length;
    for (let i = 0; i < list.length; i++) {
      positioned.push({ item: list[i], idx: i * step + Math.random() * step * 0.5 });
    }
  }

  positioned.sort((a, b) => a.idx - b.idx);
  return positioned.map((p) => p.item);
}

// ──────────────────────────────────────────
// balancedShuffleWithQuota: 소스별 최소/최대 쿼터 적용 + 라운드 로빈
// ──────────────────────────────────────────

function balancedShuffleWithQuota<T extends HasSource>(items: T[]): T[] {
  const total = items.length;
  if (total === 0) return [];

  // 1) 소스별 그룹핑 + 내부 셔플
  const groups = new Map<string, T[]>();
  for (const item of items) {
    const src = item.source || "other";
    if (!groups.has(src)) groups.set(src, []);
    groups.get(src)!.push(item);
  }

  for (const list of groups.values()) {
    const shuffled = fisherYatesShuffle(list);
    list.length = 0;
    list.push(...shuffled);
  }

  // 2) 소스별 할당량 계산
  const allocation = new Map<string, number>();

  // 2a) 최소 보장량 먼저 할당
  for (const [src, list] of groups) {
    const quota = SOURCE_QUOTA[src];
    if (quota) {
      const minCount = Math.min(Math.ceil(total * quota.minRatio), list.length);
      allocation.set(src, minCount);
    } else {
      allocation.set(src, 0);
    }
  }

  // 2b) 외부 소스 최소 합계 보장
  const externalAllocated = EXTERNAL_SOURCES_LIST.reduce(
    (sum, src) => sum + (allocation.get(src) || 0), 0
  );
  const externalMin = Math.ceil(total * EXTERNAL_MIN_TOTAL_RATIO);
  if (externalAllocated < externalMin) {
    const deficit = externalMin - externalAllocated;
    let remaining = deficit;
    for (const src of EXTERNAL_SOURCES_LIST) {
      if (remaining <= 0) break;
      const list = groups.get(src);
      if (!list) continue;
      const current = allocation.get(src) || 0;
      const canAdd = Math.min(remaining, list.length - current);
      if (canAdd > 0) {
        allocation.set(src, current + canAdd);
        remaining -= canAdd;
      }
    }
  }

  // 2c) 네이버 소스 최대 합계 제한
  const naverMax = Math.floor(total * NAVER_MAX_TOTAL_RATIO);
  let naverAllocated = NAVER_SOURCES.reduce(
    (sum, src) => sum + (allocation.get(src) || 0), 0
  );

  // 나머지 슬롯을 채움 (각 소스의 maxRatio 내에서)
  let usedSlots = Array.from(allocation.values()).reduce((a, b) => a + b, 0);
  let freeSlots = total - usedSlots;

  if (freeSlots > 0) {
    // 남은 상품이 많은 소스부터 배분
    const sortedSources = Array.from(groups.entries())
      .map(([src, list]) => ({ src, available: list.length - (allocation.get(src) || 0) }))
      .filter((s) => s.available > 0)
      .sort((a, b) => b.available - a.available);

    for (const { src, available } of sortedSources) {
      if (freeSlots <= 0) break;
      const quota = SOURCE_QUOTA[src];
      const maxCount = quota ? Math.floor(total * quota.maxRatio) : total;
      const current = allocation.get(src) || 0;
      const isNaver = NAVER_SOURCES.includes(src);

      let canAdd = Math.min(freeSlots, available, maxCount - current);
      if (isNaver) {
        canAdd = Math.min(canAdd, naverMax - naverAllocated);
      }

      if (canAdd > 0) {
        allocation.set(src, current + canAdd);
        freeSlots -= canAdd;
        if (isNaver) naverAllocated += canAdd;
      }
    }
  }

  // 만약 슬롯이 남아 있으면 제한 없이 나머지 소스에서 채움
  if (freeSlots > 0) {
    for (const [src, list] of groups) {
      if (freeSlots <= 0) break;
      const current = allocation.get(src) || 0;
      const canAdd = Math.min(freeSlots, list.length - current);
      if (canAdd > 0) {
        allocation.set(src, current + canAdd);
        freeSlots -= canAdd;
      }
    }
  }

  // 3) 할당량만큼 슬라이스
  const selected = new Map<string, T[]>();
  for (const [src, count] of allocation) {
    const list = groups.get(src);
    if (list && count > 0) {
      selected.set(src, list.slice(0, count));
    }
  }

  // 4) 라운드 로빈 삽입 (연속 동일 소스 방지)
  const result: T[] = [];
  const queues = new Map<string, T[]>();
  for (const [src, list] of selected) {
    queues.set(src, [...list]);
  }

  let lastSource = "";
  while (queues.size > 0) {
    // 마지막과 다른 소스 우선, 같은 소스는 후순위
    const candidates = Array.from(queues.entries())
      .filter(([src]) => src !== lastSource);

    let pick: [string, T[]] | undefined;
    if (candidates.length > 0) {
      // 남은 항목이 가장 많은 소스 선택 (균등 분산)
      pick = candidates.reduce((a, b) => a[1].length >= b[1].length ? a : b);
    } else {
      // 단일 소스만 남은 경우
      pick = Array.from(queues.entries())[0];
    }

    if (!pick) break;
    const [src, queue] = pick;
    result.push(queue.shift()!);
    lastSource = src;
    if (queue.length === 0) queues.delete(src);
  }

  return result;
}

// ──────────────────────────────────────────
// refreshFeedData: feedOrder / categoryFeedOrder 일괄 계산
// ──────────────────────────────────────────

export async function refreshFeedData(): Promise<void> {
  const db = admin.firestore();

  // 1) 전체 상품 조회 (dropRate 0 포함)
  const snap = await db
    .collection("products")
    .where("dropRate", ">=", 0)
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

  // 2) 글로벌 feedOrder: 소스 쿼터 적용 셔플 후 순번 할당
  const globalShuffled = balancedShuffleWithQuota(allDocs.map((d) => d.data));
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
