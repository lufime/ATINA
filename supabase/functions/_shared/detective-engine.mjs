// Server-only deterministic NPC and detective-assistant rules.
// Keep this module under supabase/functions; never import it into browser code.

export const DETECTIVE_MAX_HUMAN_PLAYERS = 8;

const ALLOWED_TOPICS = new Set([
  "whereabouts", "timeline", "relationships", "object", "motive", "general",
]);

function cleanText(value, max = 500) {
  return String(value ?? "").trim().slice(0, max);
}

export function validateHumanPlayerCount(count) {
  const value = Number(count);
  if (!Number.isInteger(value) || value < 1 || value > DETECTIVE_MAX_HUMAN_PLAYERS) {
    throw new Error("Uma partida Detetive aceita entre 1 e 8 participantes humanos.");
  }
  return value;
}

export function chooseDetective(players, { requestedPlayerId = null, random = Math.random } = {}) {
  if (!Array.isArray(players) || players.length < 1) {
    throw new Error("É necessário pelo menos um participante humano.");
  }
  validateHumanPlayerCount(players.length);
  if (requestedPlayerId) {
    const selected = players.find((player) => player.id === requestedPlayerId);
    if (!selected) throw new Error("O detetive escolhido não pertence à partida.");
    return selected.id;
  }
  const sample = Number(random());
  if (!Number.isFinite(sample) || sample < 0 || sample >= 1) {
    throw new Error("A fonte de sorteio devolveu um valor inválido.");
  }
  return players[Math.floor(sample * players.length)].id;
}

/**
 * Produces one NPC utterance. The persona is private server data and must
 * never be returned to the client. Evidence not discovered by this detective
 * is ignored, even if a caller attempts to present it.
 */
export function buildNpcReply({
  persona,
  topic,
  discoveredEvidenceIds = [],
  presentedEvidenceId = null,
  questionCount = 0,
}) {
  if (!persona || typeof persona !== "object") throw new Error("Personagem inválida.");
  if (!ALLOWED_TOPICS.has(topic)) throw new Error("Tema de interrogatório inválido.");

  const discovered = new Set(discoveredEvidenceIds.map(String));
  const presented = presentedEvidenceId == null ? null : String(presentedEvidenceId);
  const validPresented = presented && discovered.has(presented) ? presented : null;

  if (validPresented && persona.evidenceResponses?.[validPresented]) {
    return {
      text: cleanText(persona.evidenceResponses[validPresented]),
      reaction: "evidence",
      revealedEvidenceId: null,
    };
  }

  const pressureRule = (persona.pressureRules || []).find((rule) =>
    Array.isArray(rule.requiresEvidence) &&
    rule.requiresEvidence.every((id) => discovered.has(String(id)))
  );

  if (pressureRule) {
    return {
      text: cleanText(pressureRule.responses?.[topic] || pressureRule.fallback),
      reaction: "pressured",
      revealedEvidenceId: null,
    };
  }

  const isCulprit = persona.hiddenRole === "culprit";
  const responseSet = isCulprit ? persona.lies : persona.statements;
  const text = cleanText(
    responseSet?.[topic] ||
    persona.statements?.general ||
    "Não tenho mais nada a acrescentar neste momento."
  );

  const revealRule = (persona.revealRules || []).find((rule) =>
    Number(questionCount) >= Number(rule.afterQuestions || 0) &&
    Array.isArray(rule.requiresEvidence) &&
    rule.requiresEvidence.every((id) => discovered.has(String(id)))
  );

  return {
    text,
    reaction: isCulprit ? "guarded" : "cooperative",
    revealedEvidenceId: revealRule?.evidenceId &&
      !discovered.has(String(revealRule.evidenceId))
      ? String(revealRule.evidenceId)
      : null,
  };
}

/**
 * The assistant receives only facts already visible to the detective.
 * It does not accept or inspect culprit identity, private character state,
 * undiscovered evidence, or the full case solution.
 */
export function buildAdjunctAnalysis(discoveredFacts = []) {
  if (!Array.isArray(discoveredFacts)) throw new Error("Lista de factos inválida.");

  const facts = discoveredFacts
    .filter((fact) => fact && fact.discovered === true && fact.id != null)
    .map((fact) => ({
      id: String(fact.id),
      label: cleanText(fact.label, 180),
      contradicts: Array.isArray(fact.contradicts)
        ? fact.contradicts.map(String)
        : [],
      suggestedQuestion: cleanText(fact.suggestedQuestion, 180),
    }));

  const knownIds = new Set(facts.map((fact) => fact.id));
  const contradictions = [];
  const seenPairs = new Set();

  for (const fact of facts) {
    for (const otherId of fact.contradicts) {
      if (!knownIds.has(otherId) || otherId === fact.id) continue;
      const pair = [fact.id, otherId].sort().join("::");
      if (seenPairs.has(pair)) continue;
      seenPairs.add(pair);
      const other = facts.find((candidate) => candidate.id === otherId);
      contradictions.push({
        facts: [fact.id, otherId],
        summary: "Há informação incompatível entre: " +
          [fact.label, other?.label].filter(Boolean).join(" / "),
      });
    }
  }

  const suggestions = [...new Set(
    facts.map((fact) => fact.suggestedQuestion).filter(Boolean)
  )].slice(0, 5);

  return {
    factsReviewed: facts.length,
    contradictions,
    suggestions,
    note: "Análise limitada às provas já descobertas. Não é uma acusação nem uma confirmação de culpa.",
  };
}
