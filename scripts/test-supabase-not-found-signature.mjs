import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

function classify(entry) {
  if (entry.http_status !== 404) return "not_404";
  if (entry.sb_error_code === "NOT_FOUND" && entry.execution_id === "") {
    return "pre_execution_not_found";
  }
  return "other_404";
}

const fixture = JSON.parse(await readFile(new URL("../tests/fixtures/supabase-not-found-signature.json", import.meta.url), "utf8"));
for (const item of fixture.cases) {
  assert.equal(classify(item), item.expected, item.name);
}
console.log(`PASS: ${fixture.cases.length} synthetic platform-log signature cases`);
