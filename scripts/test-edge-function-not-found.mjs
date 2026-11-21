#!/usr/bin/env node
// Isolated regression test: recognizes platform NOT_FOUND responses before Edge Function execution.
// No network calls, Supabase credentials, or production resources are used.
import assert from "node:assert/strict";

const targetPath = "/functions/v1/atina-error-reports-admin";
function classify(entry) {
  const path = entry?.request?.path ?? entry?.path ?? entry?.request_path ?? "";
  const status = entry?.status ?? entry?.response?.status ?? entry?.["http-status"];
  const code = entry?.["sb-error-code"] ?? entry?.error_code ?? entry?.error?.code ?? "";
  const executionId = entry?.execution_id ?? entry?.executionId ?? null;
  const normalizedPath = String(path).split("?")[0];
  return {
    preExecutionNotFound:
      normalizedPath.endsWith(targetPath) &&
      Number(status) === 404 &&
      String(code).toUpperCase() === "NOT_FOUND" &&
      (executionId === "" || executionId === null),
    path: normalizedPath,
    status: Number(status),
    code: String(code),
    executionId,
  };
}

// Positive fixture: platform 404 with empty execution ID means function did not execute.
const platformNotFound = {
  request: { path: targetPath },
  status: 404,
  "sb-error-code": "NOT_FOUND",
  execution_id: "",
};
assert.equal(classify(platformNotFound).preExecutionNotFound, true,
  "must detect NOT_FOUND before function execution");

// Negative fixtures: don't misclassify function-level errors or other paths.
assert.equal(classify({
  request: { path: targetPath }, status: 500,
  "sb-error-code": "INTERNAL_SERVER_ERROR", execution_id: "abc123",
}).preExecutionNotFound, false, "function/runtime errors must not be classified as pre-execution NOT_FOUND");

assert.equal(classify({
  request: { path: "/functions/v1/another-function" }, status: 404,
  "sb-error-code": "NOT_FOUND", execution_id: "",
}).preExecutionNotFound, false, "other function paths must not match");

assert.equal(classify({
  request: { path: targetPath }, status: 404,
  "sb-error-code": "NOT_FOUND", execution_id: "exec-123",
}).preExecutionNotFound, false, "non-empty execution ID must not match pre-execution signature");

console.log("PASS: pre-execution NOT_FOUND signature detected; negative cases excluded.");
