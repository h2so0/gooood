const https = require('https');
const PROJECT_ID = 'gooddeal-app';
const BASE = `https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases/(default)/documents`;

function extractValue(v) {
  if (v.stringValue != null) return v.stringValue;
  if (v.integerValue != null) return Number(v.integerValue);
  if (v.doubleValue != null) return v.doubleValue;
  return '';
}

async function fetchAll() {
  let allDocs = [];
  let pageToken = null;
  while (true) {
    let url = `${BASE}/products?pageSize=300`;
    if (pageToken) url += `&pageToken=${pageToken}`;
    const data = await new Promise((resolve, reject) => {
      https.get(url, res => {
        let d = '';
        res.on('data', chunk => d += chunk);
        res.on('end', () => { try { resolve(JSON.parse(d)); } catch(e) { reject(e); } });
      }).on('error', reject);
    });
    if (data.documents) allDocs = allDocs.concat(data.documents);
    if (data.nextPageToken) pageToken = data.nextPageToken;
    else break;
  }
  return allDocs;
}

async function check() {
  const docs = await fetchAll();
  const byCategory = {};

  for (const doc of docs) {
    const f = doc.fields || {};
    const cat = f.category ? extractValue(f.category) : '(없음)';
    const title = f.title ? extractValue(f.title) : '';
    const source = f.source ? extractValue(f.source) : '';

    if (!byCategory[cat]) byCategory[cat] = [];
    byCategory[cat].push({ title, source });
  }

  // Show non-best100 items for each category to find misclassifications
  for (const cat of Object.keys(byCategory).sort()) {
    const nonBest = byCategory[cat].filter(p => p.source !== 'best100');
    if (nonBest.length === 0) continue;
    console.log(`\n=== [${cat}] keyword-classified (${nonBest.length}개) ===`);
    nonBest.forEach(p => console.log(`  [${p.source}] ${p.title}`));
  }
}
check().catch(console.error);
