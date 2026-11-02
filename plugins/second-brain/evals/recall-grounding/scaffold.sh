#!/usr/bin/env bash
# Seeds the workspace with a clean pt-BR vault holding one short agent-written note.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
sb="$here/../../bin/sb"
"$sb" init --vault . --language pt-BR >/dev/null
mkdir -p wiki/Resources
cat > "wiki/Resources/Cardinalidade de Métricas.md" <<'NOTE'
---
title: Cardinalidade de Métricas
summary: Quantas séries distintas uma métrica gera, e por que labels com muitos valores encarecem tudo.
type: conceito
status: seed
origin: agent
created: 2026-08-03
source:
tags: [observabilidade, metricas]
aliases:
  - high cardinality
---
Cardinalidade é o número de séries temporais distintas que uma métrica gera, combinando os valores de todas as suas labels. Labels com valores ilimitados, como ID de usuário ou URL completa, multiplicam as séries e encarecem armazenamento e consultas. Prefira labels com poucos valores, como rota normalizada e código de status. Detalhes por requisição vão para logs ou traces.
NOTE

"$sb" index --write --vault . >/dev/null
