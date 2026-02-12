const https = require('https');

const PROJECT_ID = 'gooddeal-app';
const BASE = `https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases/(default)/documents`;

function firestoreGet(path) {
  return new Promise((resolve, reject) => {
    const url = `${BASE}/${path}?pageSize=1000`;
    https.get(url, res => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        try { resolve(JSON.parse(data)); }
        catch(e) { reject(e); }
      });
    }).on('error', reject);
  });
}

function extractValue(v) {
  if (v.stringValue !== undefined) return v.stringValue;
  if (v.integerValue !== undefined) return Number(v.integerValue);
  if (v.doubleValue !== undefined) return v.doubleValue;
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
        res.on('end', () => {
          try { resolve(JSON.parse(d)); }
          catch(e) { reject(e); }
        });
      }).on('error', reject);
    });

    if (data.documents) {
      allDocs = allDocs.concat(data.documents);
    }

    if (data.nextPageToken) {
      pageToken = data.nextPageToken;
    } else {
      break;
    }
  }

  return allDocs;
}

async function check() {
  console.log('Fetching products...');
  const docs = await fetchAll();
  console.log('Total fetched:', docs.length);

  const cats = {};
  for (const doc of docs) {
    const fields = doc.fields || {};
    const cat = fields.category ? extractValue(fields.category) : '(없음)';
    const title = fields.title ? extractValue(fields.title) : '(제목없음)';
    const source = fields.source ? extractValue(fields.source) : '?';

    if (!cats[cat]) cats[cat] = [];
    cats[cat].push({ title, source });
  }

  console.log('\n=== 카테고리별 분포 ===');
  for (const [cat, items] of Object.entries(cats).sort((a,b) => b[1].length - a[1].length)) {
    console.log(cat + ':', items.length, '(' + (items.length/docs.length*100).toFixed(1) + '%)');
  }

  console.log('\n=== 각 카테고리 샘플 (최대 8개) ===');
  for (const [cat, items] of Object.entries(cats).sort()) {
    console.log('\n[' + cat + '] (' + items.length + '개)');
    items.slice(0, 8).forEach(p => console.log('  - [' + p.source + '] ' + p.title));
  }
}

check().catch(console.error);
