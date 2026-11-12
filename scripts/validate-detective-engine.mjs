import assert from "node:assert/strict";
import {
  buildAdjunctAnalysis,
  buildNpcReply,
  chooseDetective,
  validateHumanPlayerCount,
} from "../supabase/functions/_shared/detective-engine.mjs";

assert.equal(validateHumanPlayerCount(8), 8);
assert.throws(() => validateHumanPlayerCount(9));
assert.throws(() => validateHumanPlayerCount(0));

const players = [{ id: "p1" }, { id: "p2" }];
assert.equal(chooseDetective(players, { requestedPlayerId: "p2" }), "p2");
assert.equal(chooseDetective(players, { random: () => 0.75 }), "p2");
assert.throws(() => chooseDetective(players, { requestedPlayerId: "p3" }));

const culprit = {
  hiddenRole: "culprit",
  statements: { general: "Não sei de nada." },
  lies: { whereabouts: "Estive na biblioteca durante toda a noite." },
  pressureRules: [{
    requiresEvidence: ["clock", "mud"],
    responses: { whereabouts: "Saí por alguns minutos, mas não entrei no jardim." },
  }],
  evidenceResponses: { letter: "Reconheço a letra, mas não escrevi a carta." },
};
assert.equal(
  buildNpcReply({ persona: culprit, topic: "whereabouts" }).text,
  "Estive na biblioteca durante toda a noite.",
);
assert.equal(
  buildNpcReply({
    persona: culprit,
    topic: "whereabouts",
    discoveredEvidenceIds: ["clock", "mud"],
  }).reaction,
  "pressured",
);
assert.equal(
  buildNpcReply({
    persona: culprit,
    topic: "general",
    discoveredEvidenceIds: ["letter"],
    presentedEvidenceId: "not-discovered",
  }).reaction,
  "guarded",
);
assert.equal(
  buildNpcReply({
    persona: culprit,
    topic: "general",
    discoveredEvidenceIds: ["letter"],
    presentedEvidenceId: "letter",
  }).text,
  "Reconheço a letra, mas não escrevi a carta.",
);

const analysis = buildAdjunctAnalysis([
  { id: "clock", discovered: true, label: "Relógio parado às 22:10", contradicts: ["alibi"], suggestedQuestion: "Quem viu o relógio?" },
  { id: "alibi", discovered: true, label: "Álibi situa a pessoa às 22:30", contradicts: ["clock"] },
  { id: "secret", discovered: false, label: "SEGREDO NÃO DESCOBERTO", contradicts: ["clock"] },
]);
assert.equal(analysis.factsReviewed, 2);
assert.equal(analysis.contradictions.length, 1);
assert.deepEqual(analysis.suggestions, ["Quem viu o relógio?"]);
assert.equal(JSON.stringify(analysis).includes("SEGREDO NÃO DESCOBERTO"), false);

console.log("Motor de regras Detetive: testes concluídos com sucesso.");
