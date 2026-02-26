// ──────────────────────────────────────────
// Gemini AI classification
// ──────────────────────────────────────────

import * as admin from "firebase-admin";
import fetch from "node-fetch";
import {
  CategoryResult,
  VALID_CATEGORIES,
  SUB_CATEGORIES,
  DEFAULT_CATEGORY_RESULT,
} from "./types";
import { AI_FULL_BATCH, DELAYS } from "./config";
import { sleep } from "./utils";

async function callGemini<T>(prompt: string, logTag: string): Promise<T | null> {
  const apiKey = process.env.GEMINI_API_KEY;
  if (!apiKey) return null;

  const res = await fetch(
    "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent",
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-goog-api-key": apiKey,
      },
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
    console.error(`[${logTag}] Gemini API ${res.status}: ${await res.text()}`);
    return null;
  }

  const data = (await res.json()) as any;
  let text = (data.candidates?.[0]?.content?.parts?.[0]?.text || "").trim();
  // Strip markdown code block wrapper if present
  if (text.startsWith("```")) {
    text = text.replace(/^```(?:json)?\s*/, "").replace(/\s*```$/, "");
  }
  try {
    return JSON.parse(text) as T;
  } catch (e) {
    console.error(`[${logTag}] JSON.parse failed:`, e, "raw:", text.substring(0, 200));
    return null;
  }
}

export function mapToAppCategory(
  cat1: string,
  cat2?: string | null,
  cat3?: string | null
): CategoryResult | null {
  let category: string | null = null;

  // cat2, cat3도 합쳐서 폭넓게 매칭
  const cats = [cat1, cat2 ?? "", cat3 ?? ""].join(" ");

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
    cat1.includes("자동차") || cat1.includes("차량") ||
    cat1.includes("생활") || cat1.includes("건강") || cat1.includes("가구") ||
    cat1.includes("인테리어") || cat1.includes("주방") || cat1.includes("문구") ||
    cat1.includes("도서") || cat1.includes("반려") || cat1.includes("애완")
  ) {
    category = "생활/건강";
  }

  // cat2/cat3에서 세부 힌트 매칭 (cat1에서 못 잡은 경우)
  if (!category) {
    if (cats.includes("자동차") || cats.includes("차량")) {
      category = "생활/건강";
    } else if (cats.includes("반려") || cats.includes("애완") || cats.includes("펫")) {
      category = "생활/건강";
    }
  }

  if (!category) return null;

  // cat2/cat3 힌트로 서브카테고리 정밀 매칭
  const validSubs = SUB_CATEGORIES[category] || [];
  let subCategory = validSubs[0] || "";

  if (category === "생활/건강") {
    if (cats.includes("자동차") || cats.includes("차량")) {
      subCategory = "생활용품";
    } else if (cats.includes("반려") || cats.includes("애완") || cats.includes("펫")) {
      subCategory = "반려동물";
    } else if (cats.includes("가구") || cats.includes("인테리어") || cats.includes("조명")) {
      subCategory = "가구/인테리어";
    } else if (cats.includes("주방")) {
      subCategory = "주방용품";
    } else if (cats.includes("건강") || cats.includes("비타민") || cats.includes("영양")) {
      subCategory = "건강식품/비타민";
    }
  } else if (category === "디지털/가전") {
    if (cats.includes("자동차") || cats.includes("차량")) {
      // 차량용 전자기기도 생활가전으로
      subCategory = "생활가전";
    }
  }

  return { category, subCategory };
}

/**
 * 제목 키워드 기반 분류 후처리 — AI 오분류 교정
 */
export function fixClassification(
  title: string,
  result: CategoryResult
): CategoryResult {
  const t = title.toLowerCase();

  // 자동차/차량 관련 → 생활/건강 > 생활용품
  if (t.includes("자동차") || t.includes("차량") || t.includes("와이퍼") ||
      t.includes("타이어") || t.includes("공기주입기") || t.includes("블랙박스") ||
      t.includes("차량용") || t.includes("자동차용")) {
    return { category: "생활/건강", subCategory: "생활용품" };
  }

  // 반려동물 관련
  if (t.includes("강아지") || t.includes("고양이") || t.includes("반려") ||
      t.includes("사료") || t.includes("배변패드") || t.includes("펫")) {
    return { category: "생활/건강", subCategory: "반려동물" };
  }

  return result;
}

export async function classifySubCategoryWithGemini(
  items: { title: string; category: string }[]
): Promise<string[]> {
  const fallback = () => items.map((it) => SUB_CATEGORIES[it.category]?.[0] ?? "");

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
    const parsed = await callGemini<string[]>(prompt, "classifySub");
    const subs: string[] = Array.isArray(parsed) ? parsed : [];
    if (subs.length === 0) return fallback();

    return items.map((it, i) => {
      const sub = subs[i];
      const validSubs = SUB_CATEGORIES[it.category] || [];
      const subCat = validSubs.includes(sub) ? sub : validSubs[0] || "";
      const fixed = fixClassification(it.title, { category: it.category, subCategory: subCat });
      return fixed.subCategory;
    });
  } catch (e) {
    console.error("[classifySub] Gemini error:", e);
    return fallback();
  }
}

export async function classifyWithGemini(titles: string[]): Promise<CategoryResult[]> {
  const fallback = () => titles.map(() => ({ ...DEFAULT_CATEGORY_RESULT }));

  if (!process.env.GEMINI_API_KEY) {
    console.warn("[classify] GEMINI_API_KEY not set, defaulting to 생활/건강");
    return fallback();
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
    const parsed = await callGemini<CategoryResult[]>(prompt, "classify");
    const results: CategoryResult[] = Array.isArray(parsed) ? parsed : [];
    if (results.length === 0) return fallback();

    return titles.map((title, i) => {
      const r = results[i];
      if (!r || !VALID_CATEGORIES.includes(r.category)) {
        return fixClassification(title, { ...DEFAULT_CATEGORY_RESULT });
      }
      const validSubs = SUB_CATEGORIES[r.category] || [];
      const subCategory = validSubs.includes(r.subCategory)
        ? r.subCategory
        : validSubs[0] || "";
      return fixClassification(title, { category: r.category, subCategory });
    });
  } catch (e) {
    console.error("[classify] Gemini error:", e);
    return fallback();
  }
}

export async function generateSearchKeywords(
  items: { title: string; brand: string | null; category1: string; category2: string | null; category3: string | null }[]
): Promise<string[][]> {
  const fallback = () => items.map(() => []);

  if (!process.env.GEMINI_API_KEY) return fallback();

  const prompt = `당신은 한국 쇼핑 가격 비교 전문가입니다.
각 상품에 대해 네이버 쇼핑에서 가격 비교를 위한 검색 키워드 1~3개를 생성하세요.

규칙:
- 실제 사람이 검색할 법한 자연스러운 검색어
- 구체적인 것 → 넓은 것 순서
- 제외: 수량(100개,3kg), 색상, 성별(남자/여자), 마케팅 문구
- 상품의 핵심 정체성을 담은 키워드만

예시:
{title:"삼성전자 갤럭시 버즈3 프로 무선 이어폰 노이즈캔슬링", brand:"삼성전자", category3:"이어폰"}
→ ["갤럭시 버즈3 프로", "갤럭시 버즈3", "무선 이어폰"]

{title:"남자 긴팔 티셔츠 무지티 쪽티 면티 흰티 러닝 30수", brand:"에이커즈", category3:"티셔츠"}
→ ["긴팔 티셔츠", "티셔츠"]

{title:"코카콜라 350ml 6캔", brand:"코카콜라", category3:"탄산음료"}
→ ["코카콜라"]

상품:
${items.map((it, i) => `${i + 1}. {title:"${it.title}", brand:"${it.brand ?? ""}", category3:"${it.category3 ?? ""}"}`).join("\n")}

JSON 배열의 배열로 응답: [["키워드1","키워드2"], ["키워드1"], ...]`;

  try {
    const parsed = await callGemini<string[][]>(prompt, "searchKeywords");
    if (!Array.isArray(parsed)) return fallback();

    return items.map((_, i) => {
      const kws = parsed[i];
      if (!Array.isArray(kws)) return [];
      return kws.filter((k: any) => typeof k === "string" && k.length > 0).slice(0, 3);
    });
  } catch (e) {
    console.error("[searchKeywords] Gemini error:", e);
    return fallback();
  }
}

export async function backfillSearchKeywords(): Promise<number> {
  const db = admin.firestore();
  let total = 0;

  // 상위 2000개 상품 조회 후 searchKeywords 누락분 필터
  const snap = await db
    .collection("products")
    .orderBy("dropRate", "desc")
    .limit(2000)
    .get();

  if (snap.empty) return 0;

  const needsKeywords = snap.docs.filter((doc) => {
    const data = doc.data();
    const kws = data.searchKeywords;
    return !Array.isArray(kws) || kws.length === 0;
  });

  if (needsKeywords.length === 0) {
    console.log("[backfillKeywords] all products already have searchKeywords");
    return 0;
  }

  console.log(`[backfillKeywords] ${needsKeywords.length} products need keywords`);

  for (let i = 0; i < needsKeywords.length; i += AI_FULL_BATCH) {
    const batch = needsKeywords.slice(i, i + AI_FULL_BATCH);
    const items = batch.map((doc) => {
      const d = doc.data();
      return {
        title: (d.title as string) || "",
        brand: (d.brand as string | null) ?? null,
        category1: (d.category1 as string) || "",
        category2: (d.category2 as string | null) ?? null,
        category3: (d.category3 as string | null) ?? null,
      };
    });

    const kwResults = await generateSearchKeywords(items);

    try {
      const writeBatch = db.batch();
      let batchCount = 0;
      batch.forEach((doc, idx) => {
        const kws = kwResults[idx];
        if (kws && kws.length > 0) {
          writeBatch.set(doc.ref, { searchKeywords: kws }, { merge: true });
          batchCount++;
        }
      });
      if (batchCount > 0) {
        await writeBatch.commit();
        total += batchCount;
      }
    } catch (e) {
      console.error(`[backfillKeywords] batch error at ${i}:`, e);
    }

    if (i + AI_FULL_BATCH < needsKeywords.length) await sleep(DELAYS.AI_BATCH);
  }

  console.log(`[backfillKeywords] ${total} products got searchKeywords`);
  return total;
}

export async function backfillSubCategories(): Promise<number> {
  const db = admin.firestore();
  let total = 0;

  const snap = await db
    .collection("products")
    .orderBy("dropRate", "desc")
    .limit(2000)
    .get();

  if (snap.empty) return 0;

  // 이미 유효한 category+subCategory 있는 상품 제외
  const needsClassification = snap.docs.filter((doc) => {
    const data = doc.data();
    const cat = data.category as string | undefined;
    const sub = data.subCategory as string | undefined;
    if (!cat || !VALID_CATEGORIES.includes(cat)) return true;
    const validSubs = SUB_CATEGORIES[cat] || [];
    return !sub || !validSubs.includes(sub);
  });

  if (needsClassification.length === 0) {
    console.log("[backfill] all products already have valid classification");
    return 0;
  }

  console.log(`[backfill] ${needsClassification.length} products need classification`);

  for (let i = 0; i < needsClassification.length; i += AI_FULL_BATCH) {
    const batch = needsClassification.slice(i, i + AI_FULL_BATCH);
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

    if (i + AI_FULL_BATCH < needsClassification.length) await sleep(DELAYS.AI_BATCH);
  }

  console.log(`[backfill] ${total} products fully reclassified`);
  return total;
}
