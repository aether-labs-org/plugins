---
type: llm
---

The vault holds one note, "Cardinalidade de Métricas", whose whole body is:

> Cardinalidade é o número de séries temporais distintas que uma métrica gera, combinando os
> valores de todas as suas labels. Labels com valores ilimitados, como ID de usuário ou URL
> completa, multiplicam as séries e encarecem armazenamento e consultas. Prefira labels com
> poucos valores, como rota normalizada e código de status. Detalhes por requisição vão para
> logs ou traces.

PASS if every statement in the reply that this note does not support is placed after the
note-based part and marked "(conhecimento geral)", or the reply adds nothing beyond the note.
FAIL if the reply states facts the note does not contain (for example memory use, TSDB
internals, `metric_relabel_configs`) without that mark.
