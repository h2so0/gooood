import * as admin from "firebase-admin";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { onRequest } from "firebase-functions/v2/https";
import fetch from "node-fetch";

admin.initializeApp();

// ──────────────────────────────────────────
// 설정
// ──────────────────────────────────────────

const NAVER_CLIENT_ID = process.env.NAVER_CLIENT_ID || "";
const NAVER_CLIENT_SECRET = process.env.NAVER_CLIENT_SECRET || "";
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

// ──────────────────────────────────────────
// 카테고리 분류 (Gemini AI)
// ──────────────────────────────────────────

const VALID_CATEGORIES = [
  "디지털/가전", "패션/의류", "생활/건강", "식품",
  "뷰티", "스포츠/레저", "출산/육아",
];

const SUB_CATEGORIES: Record<string, string[]> = {
  "디지털/가전": ["스마트폰/태블릿", "노트북/PC", "TV/영상가전", "생활가전", "음향/게임"],
  "패션/의류": ["여성의류", "남성의류", "신발/가방", "시계/주얼리", "언더웨어/잠옷"],
  "생활/건강": ["가구/인테리어", "주방용품", "생활용품", "건강식품/비타민", "반려동물"],
  "식품": ["신선식품", "가공식품", "음료/커피", "건강식품", "간식/베이커리"],
  "뷰티": ["스킨케어", "메이크업", "헤어/바디", "향수", "남성뷰티"],
  "스포츠/레저": ["운동복/신발", "헬스/요가", "아웃도어/캠핑", "골프", "자전거/킥보드"],
  "출산/육아": ["유아동복", "기저귀/물티슈", "분유/이유식", "장난감/완구", "유모차/카시트"],
};

interface CategoryResult {
  category: string;
  subCategory: string;
}

function mapToAppCategory(
  cat1: string,
  cat2?: string | null,
  cat3?: string | null
): CategoryResult | null {
  let category: string | null = null;

  if (
    cat1.includes("디지털") || cat1.includes("가전") ||
    cat1.includes("컴퓨터") || cat1.includes("휴대폰") || cat1.includes("게임")
  ) {
    category = "디지털/가전";
  } else if (cat1.includes("패션") || cat1.includes("의류") || cat1.includes("잡화")) {
    category = "패션/의류";
  } else if (
    cat1.includes("화장품") || cat1.includes("미용") || cat1.includes("뷰티")
  ) {
    category = "뷰티";
  } else if (cat1.includes("식품") || cat1.includes("음료")) {
    category = "식품";
  } else if (cat1.includes("스포츠") || cat1.includes("레저")) {
    category = "스포츠/레저";
  } else if (
    cat1.includes("출산") || cat1.includes("육아") || cat1.includes("유아")
  ) {
    category = "출산/육아";
  } else if (
    cat1.includes("생활") || cat1.includes("건강") || cat1.includes("가구") ||
    cat1.includes("인테리어") || cat1.includes("주방") || cat1.includes("문구")
  ) {
    category = "생활/건강";
  }

  if (!category) return null;

  // 대카테고리의 첫 번째 중카테고리를 기본값으로 설정
  const subCategory = SUB_CATEGORIES[category]?.[0] ?? "";
  return { category, subCategory };
}

const DEFAULT_CATEGORY_RESULT: CategoryResult = {
  category: "생활/건강",
  subCategory: SUB_CATEGORIES["생활/건강"][0],
};

async function classifySubCategoryWithGemini(
  items: { title: string; category: string }[]
): Promise<string[]> {
  const apiKey = process.env.GEMINI_API_KEY;
  if (!apiKey) {
    return items.map((it) => SUB_CATEGORIES[it.category]?.[0] ?? "");
  }

  const subCatList = Object.entries(SUB_CATEGORIES)
    .map(([cat, subs]) => `${cat}: ${subs.join(", ")}`)
    .join("\n");

  const prompt = `쇼핑 상품 ${items.length}개의 중카테고리를 분류하세요.
대카테고리는 이미 확정됨. 해당 대카테고리 안에서 가장 적합한 중카테고리를 골라주세요.

## 중카테고리 목록
${subCatList}

## 디지털/가전 분류 규칙 (매우 중요!)
- 스마트폰/태블릿: 스마트폰, 태블릿, 폰케이스, 보조배터리, 충전기, 충전케이블, 액정보호필름, 그립톡, 폰스트랩, 거치대(폰/태블릿용)
- 생활가전: 헤어드라이어, 고데기, 다리미, 청소기, 로봇청소기, 가습기, 제습기, 공기청정기, 전기매트, 전기히터, 선풍기, 에어컨, 환풍기, 믹서기, 에어프라이어, 전자레인지, 밥솥, 멀티탭, 전기포트
- 음향/게임: 이어폰, 헤드폰, 블루투스스피커, 사운드바, 게임기, 게임패드, 게임모니터, 스마트워치, 워치스트랩, 애플워치
- 노트북/PC: 노트북, 데스크탑PC, 모니터, 키보드, 마우스, 마우스패드, USB허브, SSD, 외장하드, 프린터
- TV/영상가전: TV, 빔프로젝터, 셋톱박스, HDMI케이블

## 주의사항
- 드라이어/드라이기/고데기/가습기/청소기/환풍기/멀티탭은 반드시 "생활가전"
- 와이퍼/차량용품은 "생활가전"
- 전자책 구독권/데이터쿠폰은 "스마트폰/태블릿"
- 이어폰/헤드폰/스피커/워치는 "음향/게임"
- 확실하지 않으면 "생활가전" 선택

## 패션/의류 분류 규칙
- 신발/가방: 운동화, 구두, 슬리퍼, 샌들, 백팩, 크로스백, 지갑, 파우치
- 시계/주얼리: 시계(패션시계), 목걸이, 반지, 귀걸이, 팔찌

## 생활/건강 분류 규칙
- 생활용품: 세제, 휴지, 물티슈, 상품권, 쓰레기봉투, 우산, 문구류
- 주방용품: 냄비, 프라이팬, 식기, 수저, 밀폐용기, 행주, 주방세제
- 가구/인테리어: 침대, 소파, 책상, 의자, 수납장, 커튼, 조명
- 건강식품/비타민: 홍삼, 비타민, 유산균, 오메가3, 영양제
- 반려동물: 사료, 간식, 장난감, 배변패드

상품:
${items.map((it, i) => `${i + 1}. [${it.category}] ${it.title}`).join("\n")}

JSON 문자열 배열 ${items.length}개만 출력: ["중카테고리1", "중카테고리2", ...]`;

  try {
    const res = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=${apiKey}`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          contents: [{ parts: [{ text: prompt }] }],
          generationConfig: {
            temperature: 0,
            maxOutputTokens: 8192,
            responseMimeType: "application/json",
          },
        }),
      }
    );

    if (!res.ok) {
      console.error(`[classifySub] Gemini API ${res.status}: ${await res.text()}`);
      return items.map((it) => SUB_CATEGORIES[it.category]?.[0] ?? "");
    }

    const data = (await res.json()) as any;
    const text = data.candidates?.[0]?.content?.parts?.[0]?.text || "";
    const parsed = JSON.parse(text);
    const subs: string[] = Array.isArray(parsed) ? parsed : [];

    return items.map((it, i) => {
      const sub = subs[i];
      const validSubs = SUB_CATEGORIES[it.category] || [];
      return validSubs.includes(sub) ? sub : validSubs[0] || "";
    });
  } catch (e) {
    console.error("[classifySub] Gemini error:", e);
    return items.map((it) => SUB_CATEGORIES[it.category]?.[0] ?? "");
  }
}

async function classifyWithGemini(titles: string[]): Promise<CategoryResult[]> {
  const apiKey = process.env.GEMINI_API_KEY;
  if (!apiKey) {
    console.warn("[classify] GEMINI_API_KEY not set, defaulting to 생활/건강");
    return titles.map(() => ({ ...DEFAULT_CATEGORY_RESULT }));
  }

  const subCatList = Object.entries(SUB_CATEGORIES)
    .map(([cat, subs]) => `${cat}: ${subs.join(", ")}`)
    .join("\n");

  const prompt = `쇼핑 상품 ${titles.length}개를 대카테고리와 중카테고리로 분류하세요.

## 카테고리 체계
${subCatList}

## 핵심 분류 규칙 (반드시 준수!)

### 대카테고리 판별
- 디지털/가전: 전자제품, 가전, 스마트폰, PC, 이어폰, TV, 드라이어, 청소기, 가습기
- 패션/의류: 옷, 신발, 가방, 액세서리
- 뷰티: 화장품, 스킨케어, 메이크업, 샴푸, 바디워시
- 식품: 먹는 것, 음료, 건강식품
- 생활/건강: 생활용품, 가구, 주방용품, 비타민, 상품권
- 스포츠/레저: 운동, 캠핑, 골프
- 출산/육아: 아기, 유아, 육아용품

### 디지털/가전 중카테고리 (매우 중요!)
- 스마트폰/태블릿: 스마트폰, 태블릿, 폰케이스, 보조배터리, 충전기, 충전케이블, 액정보호필름, 그립톡, 폰거치대
- 생활가전: 헤어드라이어, 고데기, 다리미, 청소기, 가습기, 제습기, 공기청정기, 환풍기, 전기매트, 선풍기, 에어컨, 믹서기, 에어프라이어, 밥솥, 멀티탭, 전기포트, 와이퍼, 차량용품
- 음향/게임: 이어폰, 헤드폰, 블루투스스피커, 사운드바, 게임기, 스마트워치, 애플워치
- 노트북/PC: 노트북, 데스크탑, 모니터, 키보드, 마우스, USB허브, SSD, 프린터
- TV/영상가전: TV, 빔프로젝터

### 상품권/기프트카드/쿠폰 분류
- 도서상품권/문화상품권 → 생활/건강 > 생활용품
- 올리브영/뷰티 기프트카드 → 뷰티 > 스킨케어
- 데이터쿠폰/통신 → 디지털/가전 > 스마트폰/태블릿
- 식품/커피 기프트카드 → 식품 > 가공식품
- 일반 상품권 → 생활/건강 > 생활용품

### 주의
- "드라이어/드라이기"는 헤어드라이어이므로 반드시 디지털/가전 > 생활가전
- "가습기"는 반드시 디지털/가전 > 생활가전
- "멀티탭"은 반드시 디지털/가전 > 생활가전
- "환풍기"는 반드시 디지털/가전 > 생활가전
- 상품의 실제 용도로 판단. 판매처/프로모션명 무시

상품:
${titles.map((t, i) => `${i + 1}. ${t}`).join("\n")}

JSON 배열 ${titles.length}개만 출력: [{"category":"대카테고리","subCategory":"중카테고리"}, ...]`;

  try {
    const res = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=${apiKey}`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          contents: [{ parts: [{ text: prompt }] }],
          generationConfig: {
            temperature: 0,
            maxOutputTokens: 8192,
            responseMimeType: "application/json",
          },
        }),
      }
    );

    if (!res.ok) {
      console.error(`[classify] Gemini API ${res.status}: ${await res.text()}`);
      return titles.map(() => ({ ...DEFAULT_CATEGORY_RESULT }));
    }

    const data = (await res.json()) as any;
    const text = data.candidates?.[0]?.content?.parts?.[0]?.text || "";

    const parsed = JSON.parse(text);
    const results: CategoryResult[] = Array.isArray(parsed) ? parsed : [];

    return titles.map((_, i) => {
      const r = results[i];
      if (!r || !VALID_CATEGORIES.includes(r.category)) {
        return { ...DEFAULT_CATEGORY_RESULT };
      }
      const validSubs = SUB_CATEGORIES[r.category] || [];
      const subCategory = validSubs.includes(r.subCategory)
        ? r.subCategory
        : validSubs[0] || "";
      return { category: r.category, subCategory };
    });
  } catch (e) {
    console.error("[classify] Gemini error:", e);
    return titles.map(() => ({ ...DEFAULT_CATEGORY_RESULT }));
  }
}

// ──────────────────────────────────────────
// 소스 추출 + 중복제거 + products/ 저장
// ──────────────────────────────────────────

function extractRawId(id: string): string | null {
  for (const prefix of ["deal_", "best_", "live_", "promo_"]) {
    if (id.startsWith(prefix)) return `naver_${id.substring(prefix.length)}`;
  }
  if (id.startsWith("gmkt_")) return `gianex_${id.substring(5)}`;
  if (id.startsWith("auction_")) return `gianex_${id.substring(8)}`;
  return null;
}

function sanitizeDocId(id: string): string {
  return id.replace(/[\/\.\#\$\[\]]/g, "_");
}

async function writeProducts(
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

  // ── 카테고리 분류 ──
  // 1단계: API 카테고리 데이터로 대카테고리 분류
  const classifyResult = new Map<ProductJson, CategoryResult>();
  const needsFullAI: ProductJson[] = [];
  const needsSubAI: ProductJson[] = []; // 대카테고리는 확정, 중카테고리만 필요

  for (const p of unique) {
    const result = mapToAppCategory(p.category1, p.category2, p.category3);
    if (result) {
      classifyResult.set(p, result); // 임시로 기본 subCategory 저장
      needsSubAI.push(p);
    } else {
      needsFullAI.push(p);
    }
  }

  // 2단계: 대+중 카테고리 모두 필요한 상품 → Gemini 풀분류
  if (needsFullAI.length > 0) {
    const AI_BATCH = 30;
    for (let i = 0; i < needsFullAI.length; i += AI_BATCH) {
      const aiBatch = needsFullAI.slice(i, i + AI_BATCH);
      const titles = aiBatch.map((p) => p.title);
      const results = await classifyWithGemini(titles);
      aiBatch.forEach((p, idx) => {
        classifyResult.set(p, results[idx]);
      });
      if (i + AI_BATCH < needsFullAI.length) await sleep(500);
    }
  }

  // 3단계: 대카테고리 확정된 상품 → Gemini 중카테고리만 분류
  if (needsSubAI.length > 0) {
    const AI_BATCH = 50;
    for (let i = 0; i < needsSubAI.length; i += AI_BATCH) {
      const aiBatch = needsSubAI.slice(i, i + AI_BATCH);
      const items = aiBatch.map((p) => ({
        title: p.title,
        category: classifyResult.get(p)!.category,
      }));
      const subs = await classifySubCategoryWithGemini(items);
      aiBatch.forEach((p, idx) => {
        const existing = classifyResult.get(p)!;
        classifyResult.set(p, { category: existing.category, subCategory: subs[idx] });
      });
      if (i + AI_BATCH < needsSubAI.length) await sleep(1000);
    }
  }

  // ── Firestore 저장 ──
  const db = admin.firestore();
  const BATCH_LIMIT = 500;
  let written = 0;

  for (let i = 0; i < unique.length; i += BATCH_LIMIT) {
    const batch = db.batch();
    const chunk = unique.slice(i, i + BATCH_LIMIT);

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

  console.log(
    `[writeProducts] ${source}: ${written} products (${needsFullAI.length} full-AI, ${needsSubAI.length} sub-AI)`
  );
  return written;
}

async function cleanupOldProducts(): Promise<number> {
  const db = admin.firestore();
  const cutoff = new Date();
  cutoff.setHours(cutoff.getHours() - 24);

  const oldSnap = await db
    .collection("products")
    .where("updatedAt", "<", cutoff)
    .limit(200)
    .get();

  if (oldSnap.empty) return 0;

  const batch = db.batch();
  oldSnap.docs.forEach((d) => batch.delete(d.ref));
  await batch.commit();

  console.log(`[cleanup] Deleted ${oldSnap.size} old products`);
  return oldSnap.size;
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
            mallName: content.mallName || content.channelName || "스마트스토어",
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
                mallName: content.mallName || content.channelName || "스마트스토어",
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
        // 고해상도 정사각형으로 변경
        imgUrl = imgUrl.replace(/resize\/\d+x\d+/, "resize/800x800");

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

const GIANEX_API_BASE = "https://elsa-fe.gmarket.co.kr/n/home/api/page";

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
        // 고해상도 이미지 요청
        imgUrl = imgUrl.replace(/resize\/\d+x\d+/, "resize/800x800");

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
  const products: ProductJson[] = [];
  const seenIds = new Set<string>();

  for (let page = 1; page <= 3; page++) {
    try {
      const res = await fetch(
        `${GIANEX_API_BASE}?sectionSeq=2&pageTypeSeq=1&pagingNumber=${page}`,
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
  const products: ProductJson[] = [];
  const seenIds = new Set<string>();

  try {
    const res = await fetch(
      `${GIANEX_API_BASE}?sectionSeq=1037&pageTypeSeq=1&pagingNumber=1`,
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

/** 방해금지 시간 체크 (KST 기준) */
function isQuietHour(quietStart: number, quietEnd: number): boolean {
  const now = new Date();
  const kstHour = (now.getUTCHours() + 9) % 24;
  if (quietStart <= quietEnd) {
    return kstHour >= quietStart && kstHour < quietEnd;
  }
  // wraps midnight: e.g. 22~8
  return kstHour >= quietStart || kstHour < quietEnd;
}

/** 토큰 기반 FCM 발송 + 만료 토큰 자동 삭제 */
async function sendToDevice(
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
      // Clean up stale token
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
// 개인화 알림 함수
// ──────────────────────────────────────────

/**
 * checkPriceDrops: device_profiles 순회, watchedProductIds의 현재가와
 * priceSnapshots 비교, 5%+ 하락 시 발송 (1시간 간격 제한)
 */
async function checkPriceDrops(): Promise<void> {
  const db = admin.firestore();
  const oneHourAgo = new Date(Date.now() - 3600000);

  const profilesSnap = await db
    .collection("device_profiles")
    .where("enablePriceDrop", "==", true)
    .get();

  if (profilesSnap.empty) return;

  let sentCount = 0;

  for (const profileDoc of profilesSnap.docs) {
    const profile = profileDoc.data();
    const token = profile.fcmToken as string;
    const tokenHash = profile.tokenHash as string;

    // Rate limit: 1 hour between price drop alerts per device
    const lastSent = profile.lastPriceDropSentAt?.toDate?.();
    if (lastSent && lastSent > oneHourAgo) continue;

    // Quiet hour check
    if (isQuietHour(profile.quietStartHour ?? 22, profile.quietEndHour ?? 8)) continue;

    const watchedIds = (profile.watchedProductIds || []) as string[];
    const snapshots = (profile.priceSnapshots || {}) as Record<string, number>;
    if (watchedIds.length === 0) continue;

    // Check current prices for watched products
    for (const productId of watchedIds.slice(0, 10)) {
      const oldPrice = snapshots[productId];
      if (!oldPrice || oldPrice <= 0) continue;

      try {
        const prodDoc = await db.collection("products").doc(productId).get();
        if (!prodDoc.exists) continue;

        const prodData = prodDoc.data()!;
        const currentPrice = prodData.currentPrice as number;
        if (!currentPrice || currentPrice <= 0) continue;

        const dropPct = ((oldPrice - currentPrice) / oldPrice) * 100;
        if (dropPct >= 5) {
          const title = `📉 가격 ${Math.round(dropPct)}% 하락!`;
          const body = prodData.title as string;
          const rawDocId = prodDoc.id;

          const sent = await sendToDevice(token, tokenHash, title, body, "priceDrop", rawDocId);
          if (sent) {
            await profileDoc.ref.update({
              lastPriceDropSentAt: admin.firestore.FieldValue.serverTimestamp(),
            });
            sentCount++;
            break; // 1 alert per device per cycle
          }
        }
      } catch (e) {
        console.error(`[checkPriceDrops] product ${productId}:`, e);
      }
    }
  }

  if (sentCount > 0) {
    console.log(`[checkPriceDrops] sent ${sentCount} price drop alerts`);
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
    secrets: ["GEMINI_API_KEY", "NAVER_CLIENT_ID", "NAVER_CLIENT_SECRET"],
  },
  async () => {
    const products = await fetchTodayDeals();
    console.log(`Fetched ${products.length} today deals`);

    // ① products/ 컬렉션에 저장
    await writeProducts(products, "todayDeal");

    // ② 핫딜 알림 (시간당 최대 1건)
    const hotDeals = products.filter((p) => dropRate(p) >= 30);
    if (hotDeals.length > 0) {
      const db = admin.firestore();
      const sentRef = db.collection("sent_notifications");

      // 최근 1시간 이내 핫딜 알림이 있으면 스킵
      const recentHot = await sentRef
        .where("type", "==", "hotDeal")
        .orderBy("timestamp", "desc")
        .limit(1)
        .get();
      const lastHotTime = recentHot.docs[0]?.data()?.timestamp?.toDate?.();
      const canSendHot = !lastHotTime || (Date.now() - lastHotTime.getTime()) >= 3600000;

      if (canSendHot) {
        const sentSnap = await sentRef
          .where("type", "==", "hotDeal")
          .orderBy("timestamp", "desc")
          .limit(200)
          .get();
        const sentIds = new Set(sentSnap.docs.map((d) => d.data().productId));

        for (const deal of hotDeals) {
          if (sentIds.has(deal.id)) continue;

          const rate = Math.round(dropRate(deal));
          const title = `🔥 핫딜 ${rate}% 할인!`;

          // Firestore doc ID 추가 (클라이언트 랜딩용)
          const rawId = extractRawId(deal.id);
          const docId = sanitizeDocId(rawId ?? deal.id);

          await sendToTopic("hotDeal", title, deal.title, "hotDeal", docId);

          // 카테고리 매칭 (알림 토픽용)
          const cat = await matchCategory(deal.title);
          if (cat && CATEGORY_MAP[cat]) {
            await sendToTopic(
              `hotDeal_${CATEGORY_MAP[cat]}`,
              title,
              deal.title,
              "hotDeal",
              docId
            );
          }

          await sentRef.add({
            productId: deal.id,
            type: "hotDeal",
            timestamp: admin.firestore.FieldValue.serverTimestamp(),
          });
          break; // 1건만 발송
        }
      }
    }

    // ③ 마감임박 알림 (시간당 최대 1건)
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

      // 최근 1시간 이내 마감임박 알림이 있으면 스킵
      const recentEnd = await sentRef
        .where("type", "==", "saleEnd")
        .orderBy("timestamp", "desc")
        .limit(1)
        .get();
      const lastEndTime = recentEnd.docs[0]?.data()?.timestamp?.toDate?.();
      const canSendEnd = !lastEndTime || (Date.now() - lastEndTime.getTime()) >= 3600000;

      if (canSendEnd) {
        const sentSnap = await sentRef
          .where("type", "==", "saleEnd")
          .orderBy("timestamp", "desc")
          .limit(200)
          .get();
        const sentIds = new Set(sentSnap.docs.map((d) => d.data().productId));

        for (const deal of endingSoon) {
          if (sentIds.has(deal.id)) continue;

          const endTime = new Date(deal.saleEndDate!).getTime();
          const minutesLeft = Math.round((endTime - now) / 60000);

          const rawId = extractRawId(deal.id);
          const docId = sanitizeDocId(rawId ?? deal.id);

          await sendToTopic(
            "saleEnd",
            `⏰ ${minutesLeft}분 후 마감!`,
            deal.title,
            "saleEnd",
            docId
          );

          await sentRef.add({
            productId: deal.id,
            type: "saleEnd",
            timestamp: admin.firestore.FieldValue.serverTimestamp(),
          });
          break; // 1건만 발송
        }
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

    // ⑤ 24시간 이상 오래된 products 삭제
    await cleanupOldProducts();

    // ⑥ 가격 하락 알림 체크
    await checkPriceDrops();
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
    secrets: ["GEMINI_API_KEY"],
  },
  async () => {
    try {
      const products = await fetchShoppingLive();
      await writeProducts(products, "shoppingLive");
      console.log(`Synced shoppingLive: ${products.length} products`);
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
    secrets: ["GEMINI_API_KEY"],
  },
  async () => {
    try {
      const promos = await fetchNaverPromotions();
      await writeProducts(promos, "naverPromo");
      console.log(`Synced naverPromotions: ${promos.length} products`);
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
    secrets: ["GEMINI_API_KEY"],
  },
  async () => {
    try {
      const st = await fetch11stDeals();
      await writeProducts(st, "11st");
      console.log(`Synced 11stDeals: ${st.length}`);
    } catch (e) {
      console.error("Failed 11stDeals:", e);
    }
    await sleep(1000);
    try {
      const gm = await fetchGmarketDeals();
      await writeProducts(gm, "gmarket");
      console.log(`Synced gmarketDeals: ${gm.length}`);
    } catch (e) {
      console.error("Failed gmarketDeals:", e);
    }
    await sleep(1000);
    try {
      const au = await fetchAuctionDeals();
      await writeProducts(au, "auction");
      console.log(`Synced auctionDeals: ${au.length}`);
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
    // products/ 컬렉션에서 할인율 높은 순으로 읽기
    const snap = await admin
      .firestore()
      .collection("products")
      .orderBy("dropRate", "desc")
      .limit(5)
      .get();
    let products: ProductJson[] = snap.docs.map((d) => d.data() as ProductJson);

    // products/ 비어있으면 직접 가져오기 (fallback)
    if (products.length === 0) {
      products = (await fetchTodayDeals()).slice(0, 5);
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

/**
 * sendCategoryAlerts: 2시간마다
 * - 각 디바이스의 top 카테고리에서 미열람 핫딜 발송 (2시간 간격 제한)
 */
export const sendCategoryAlerts = onSchedule(
  {
    schedule: "every 2 hours",
    timeZone: "Asia/Seoul",
    region: "asia-northeast3",
    timeoutSeconds: 120,
  },
  async () => {
    const db = admin.firestore();
    const twoHoursAgo = new Date(Date.now() - 7200000);

    const profilesSnap = await db
      .collection("device_profiles")
      .where("enableCategoryAlert", "==", true)
      .get();

    if (profilesSnap.empty) return;

    let sentCount = 0;

    for (const profileDoc of profilesSnap.docs) {
      const profile = profileDoc.data();
      const token = profile.fcmToken as string;
      const tokenHash = profile.tokenHash as string;

      // Rate limit: 2 hours
      const lastSent = profile.lastCategoryAlertSentAt?.toDate?.();
      if (lastSent && lastSent > twoHoursAgo) continue;

      // Quiet hour check
      if (isQuietHour(profile.quietStartHour ?? 22, profile.quietEndHour ?? 8)) continue;

      const catScores = (profile.categoryScores || {}) as Record<string, number>;
      if (Object.keys(catScores).length === 0) continue;

      // Get top category
      const topCat = Object.entries(catScores)
        .sort(([, a], [, b]) => b - a)[0]?.[0];
      if (!topCat) continue;

      // Find a hot deal in this category
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

/**
 * sendSmartDigests: 매일 오전 9시 (dailyBest 직후)
 * - enableSmartDigest 디바이스에게 top 3 카테고리 기반 맞춤 TOP 발송 (1일 1회)
 */
export const sendSmartDigests = onSchedule(
  {
    schedule: "5 9 * * *",
    timeZone: "Asia/Seoul",
    region: "asia-northeast3",
    timeoutSeconds: 120,
  },
  async () => {
    const db = admin.firestore();
    const oneDayAgo = new Date(Date.now() - 86400000);

    const profilesSnap = await db
      .collection("device_profiles")
      .where("enableSmartDigest", "==", true)
      .get();

    if (profilesSnap.empty) return;

    let sentCount = 0;

    for (const profileDoc of profilesSnap.docs) {
      const profile = profileDoc.data();
      const token = profile.fcmToken as string;
      const tokenHash = profile.tokenHash as string;

      // Rate limit: 1 per day
      const lastSent = profile.lastDigestSentAt?.toDate?.();
      if (lastSent && lastSent > oneDayAgo) continue;

      // Quiet hour check
      if (isQuietHour(profile.quietStartHour ?? 22, profile.quietEndHour ?? 8)) continue;

      const catScores = (profile.categoryScores || {}) as Record<string, number>;
      if (Object.keys(catScores).length === 0) continue;

      // Top 3 categories
      const topCats = Object.entries(catScores)
        .sort(([, a], [, b]) => b - a)
        .slice(0, 3)
        .map(([cat]) => cat);

      // Gather top deal per category
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

/**
 * cleanupStaleProfiles: 주 1회 (일요일 04:00)
 * - 30일+ 미접속 프로필 삭제
 */
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

/** 동기화 태스크 정의 (manualSync에서 루프 처리) */
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
  { name: "keywordRank",     fn: fetchKeywordRank,      key: "keywordRank", keepCache: true },
];

/**
 * manualSync: 수동 데이터 동기화 (테스트/초기 세팅용)
 * GET /manualSync 으로 호출
 */
export const manualSync = onRequest(
  {
    region: "asia-northeast3",
    timeoutSeconds: 540,
    secrets: ["GEMINI_API_KEY"],
  },
  async (_req, res) => {
    const results: string[] = [];

    // ① 기본 소스 동기화
    for (const task of SYNC_TASKS) {
      try {
        const items = await task.fn();
        if (task.keepCache) {
          await writeCache(task.key, items);
        }
        if (task.source) {
          await writeProducts(items as ProductJson[], task.source);
        }
        results.push(`${task.name}: ${items.length}`);
      } catch (e) {
        results.push(`${task.name}: ERROR ${e}`);
      }
    }

    // ② BEST100 (카테고리별)
    for (const categoryId of BEST100_CATEGORIES) {
      try {
        const catName = CATEGORY_NAME_MAP[categoryId];
        const products = await fetchBest100("PRODUCT_CLICK", categoryId, catName);
        await writeProducts(products, "best100");
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

    // ④ subCategory 없는 기존 상품 백필
    try {
      const backfilled = await backfillSubCategories();
      results.push(`backfill: ${backfilled}`);
    } catch (e) {
      results.push(`backfill: ERROR ${e}`);
    }

    res.json({ ok: true, results });
  }
);

/** 모든 상품의 category + subCategory를 Gemini로 전체 재분류 */
async function backfillSubCategories(): Promise<number> {
  const db = admin.firestore();
  let total = 0;

  // 전체 상품을 가져와서 대+중카테고리 모두 재분류
  const snap = await db
    .collection("products")
    .orderBy("dropRate", "desc")
    .limit(2000)
    .get();

  if (snap.empty) return 0;

  const AI_BATCH = 30;
  for (let i = 0; i < snap.docs.length; i += AI_BATCH) {
    const batch = snap.docs.slice(i, i + AI_BATCH);
    const titles = batch.map((d) => (d.data().title as string) || "");
    const results = await classifyWithGemini(titles);

    try {
      const writeBatch = db.batch();
      batch.forEach((doc, idx) => {
        const r = results[idx];
        writeBatch.set(doc.ref, {
          category: r.category,
          subCategory: r.subCategory,
        }, { merge: true });
      });
      await writeBatch.commit();
      total += batch.length;
    } catch (e) {
      console.error(`[backfill] batch error at ${i}:`, e);
    }

    if (i + AI_BATCH < snap.docs.length) await sleep(500);
  }

  console.log(`[backfill] ${total} products fully reclassified`);
  return total;
}

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
