#!/usr/bin/env node
/**
 * Build a local review queue of real-photo candidates from Wikimedia Commons.
 *
 * Input JSON (kept private/local):
 * [
 *   {"challenge_id": 12, "answer": "Lisboa", "searchTerms": ["Lisbon city streets", "Lisbon viewpoint"]}
 * ]
 *
 * Run: node scripts/find-real-photo-candidates.mjs private-challenges.json
 * Output: photo-candidates-review.json (never commit this file; it contains answers).
 */
import fs from 'node:fs/promises';

const inputPath = process.argv[2];
if (!inputPath) {
  console.error('Usage: node scripts/find-real-photo-candidates.mjs <private-challenges.json>');
  process.exit(2);
}

const ALLOWED_LICENSES = new Set([
  'cc0', 'public domain', 'pd', 'cc by 4.0', 'cc by 3.0', 'cc by 2.0',
  'cc by-sa 4.0', 'cc by-sa 3.0', 'cc by-sa 2.0'
]);
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
const clean = value => String(value ?? '').replace(/<[^>]*>/g, ' ').replace(/&nbsp;/g, ' ').replace(/&amp;/g, '&').replace(/\\s+/g, ' ').trim();
const norm = value => clean(value).normalize('NFD').replace(/[\\u0300-\\u036f]/g, '').toLowerCase();
const metadata = (info, key) => clean(info.extmetadata?.[key]?.value);
const allowedLicense = (name) => {
  const n = norm(name).replace(/creative commons|licence|license/g, '').replace(/-/g, ' ').replace(/\\s+/g, ' ').trim();
  return ALLOWED_LICENSES.has(n) || /^cc0(?: 1\.0)?$/.test(n) || /^public domain/.test(n);
};

const input = JSON.parse(await fs.readFile(inputPath, 'utf8'));
if (!Array.isArray(input)) throw new Error('Input must be a JSON array.');
const output = [];

async function commonsSearch(query) {
  const params = new URLSearchParams({
    action: 'query', format: 'json', origin: '*', generator: 'search',
    gsrnamespace: '6', gsrlimit: '8', gsrsearch: query,
    prop: 'imageinfo', iiprop: 'url|mime|extmetadata', iiurlwidth: '1400'
  });
  const response = await fetch('https://commons.wikimedia.org/w/api.php?' + params, {
    headers: { 'User-Agent': 'ATINA-photo-research/1.0 (educational game; contact via GitHub)' }
  });
  if (!response.ok) throw new Error('Commons API returned HTTP ' + response.status);
  const data = await response.json();
  return Object.values(data.query?.pages ?? {}).map(page => ({ page, info: page.imageinfo?.[0] })).filter(x => x.info);
}

for (const challenge of input) {
  const answer = clean(challenge.answer);
  const terms = [answer, ...(challenge.searchTerms ?? [])].map(clean).filter(Boolean).slice(0, 5);
  const seen = new Set();
  const candidates = [];
  for (const term of terms) {
    try {
      for (const {page, info} of await commonsSearch(term)) {
        if (seen.has(page.pageid)) continue;
        seen.add(page.pageid);
        const title = clean(page.title.replace(/^File:/, '').replace(/\\.[^.]+$/, ''));
        const mime = info.mime ?? '';
        const license = metadata(info, 'LicenseShortName');
        const author = metadata(info, 'Artist');
        const licenseUrl = metadata(info, 'LicenseUrl');
        const description = metadata(info, 'ImageDescription');
        if (!/^image\\/(jpeg|png|webp)$/i.test(mime)) continue;
        if (!allowedLicense(license) || !author || !licenseUrl) continue;
        const haystack = norm(title + ' ' + description);
        const answerTokens = norm(answer).split(/[^a-z0-9]+/).filter(t => t.length > 2);
        const expandedTokens = terms.slice(1).flatMap(term => norm(term).split(/[^a-z0-9]+/).filter(t => t.length > 2));
        const matchedAnswer = answerTokens.filter(t => haystack.includes(t));
        const matchedContext = [...new Set(expandedTokens)].filter(t => haystack.includes(t));
        // Accept a clear match to the answer OR to its supplied contextual representation.
        // This allows fictional characters, actors, locations and concrete logic props.
        if (matchedAnswer.length === 0 && matchedContext.length === 0) continue;
        const relevance = matchedAnswer.length
          ? matchedAnswer.length / Math.max(1, answerTokens.length)
          : 0.65 * matchedContext.length / Math.max(1, new Set(expandedTokens).size);
        candidates.push({
          title, pageUrl: info.descriptionurl, originalUrl: info.url,
          mime, license, licenseUrl, author, description,
          relevance,
          matchedAnswerTerms: matchedAnswer,
          matchedContextTerms: matchedContext
        });
      }
    } catch (error) {
      console.error('Search failed for challenge', challenge.challenge_id, term, error.message);
    }
    await sleep(350);
  }
  candidates.sort((a,b) => b.relevance - a.relevance);
  output.push({
    challenge_id: challenge.challenge_id,
    answer,
    status: candidates.length ? 'REVIEW_REQUIRED' : 'NO_VERIFIED_CANDIDATE',
    candidates: candidates.slice(0, 8)
  });
  console.log('Challenge', challenge.challenge_id, ':', candidates.length, 'candidate(s)');
  await sleep(500);
}

await fs.writeFile('photo-candidates-review.json', JSON.stringify(output, null, 2) + '\\n');
console.log('Wrote photo-candidates-review.json. Review each photo visually before use; do not auto-publish.');
