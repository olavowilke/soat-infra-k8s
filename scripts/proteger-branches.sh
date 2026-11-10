#!/usr/bin/env bash
# Uso: scripts/proteger-branches.sh <repo> <check> [<check>...]
# Cria ou atualiza o ruleset "protecao-main" do repo olavowilke/<repo>:
# PR obrigatorio (0 aprovacoes), checks obrigatorios e estritos, sem bypass.
set -euo pipefail

if [ "$#" -lt 2 ]; then
  echo "uso: $0 <repo> <check> [<check>...]" >&2
  exit 1
fi

REPO="$1"; shift
OWNER="olavowilke"
NOME="protecao-main"

CHECKS_JSON="$(printf '%s\n' "$@" | jq -R '{context: .}' | jq -s .)"

BODY="$(jq -n --arg nome "$NOME" --argjson checks "$CHECKS_JSON" '{
  name: $nome,
  target: "branch",
  enforcement: "active",
  conditions: { ref_name: { include: ["refs/heads/main"], exclude: [] } },
  bypass_actors: [],
  rules: [
    { type: "deletion" },
    { type: "non_fast_forward" },
    { type: "pull_request", parameters: {
        required_approving_review_count: 0,
        dismiss_stale_reviews_on_push: true,
        required_reviewers: [],
        require_code_owner_review: false,
        require_last_push_approval: false,
        required_review_thread_resolution: false,
        allowed_merge_methods: ["merge", "squash", "rebase"]
    } },
    { type: "required_status_checks", parameters: {
        strict_required_status_checks_policy: true,
        do_not_enforce_on_create: false,
        required_status_checks: $checks
    } }
  ]
}')"

ID="$(gh api "repos/${OWNER}/${REPO}/rulesets" --jq ".[] | select(.name==\"${NOME}\") | .id" | head -n1)"

if [ -n "${ID}" ]; then
  echo "Atualizando ruleset ${NOME} (${ID}) em ${REPO}"
  echo "${BODY}" | gh api -X PUT "repos/${OWNER}/${REPO}/rulesets/${ID}" --input - --jq '.id'
else
  echo "Criando ruleset ${NOME} em ${REPO}"
  echo "${BODY}" | gh api -X POST "repos/${OWNER}/${REPO}/rulesets" --input - --jq '.id'
fi
