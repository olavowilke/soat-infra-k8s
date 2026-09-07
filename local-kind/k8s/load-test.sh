#!/usr/bin/env bash
# Roteiro de teste de carga para demonstrar o autoscaling (HPA).
# Gera requisições contra a API até o consumo de CPU disparar o scale-up.
#
# Pré-requisitos: cluster no ar, app deployada, metrics-server ativo.
# Uso:
#   ./load-test.sh [BASE_URL] [DURACAO] [CONCORRENCIA]
# Exemplo (NodePort local do kind):
#   ./load-test.sh http://localhost:30080 60s 50
set -euo pipefail

BASE_URL="${1:-http://localhost:30080}"
DURACAO="${2:-60s}"
CONCORRENCIA="${3:-50}"
# Endpoint público (não exige auth) — bom alvo para gerar carga de CPU.
ALVO="${BASE_URL}/api/actuator/health"

echo "== Teste de carga contra ${ALVO} (duração=${DURACAO}, concorrência=${CONCORRENCIA}) =="
echo "Acompanhe o autoscaling em outro terminal com:"
echo "  kubectl get hpa,pods -n oficina -w"
echo

if command -v hey >/dev/null 2>&1; then
  hey -z "${DURACAO}" -c "${CONCORRENCIA}" "${ALVO}"
elif command -v ab >/dev/null 2>&1; then
  ab -t "${DURACAO%s}" -c "${CONCORRENCIA}" "${ALVO}"
else
  echo "'hey' e 'ab' não encontrados — usando loop curl (menos intenso)."
  echo "Instale: go install github.com/rakyll/hey@latest"
  END=$(( SECONDS + ${DURACAO%s} ))
  while [ $SECONDS -lt $END ]; do
    for _ in $(seq 1 "${CONCORRENCIA}"); do curl -s -o /dev/null "${ALVO}" & done
    wait
  done
fi

echo
echo "== Concluído. Verifique se o HPA escalou os pods e depois recuou: =="
echo "  kubectl get hpa oficina-api -n oficina"
echo "  kubectl get pods -n oficina"
