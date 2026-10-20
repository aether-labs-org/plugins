#!/usr/bin/env bash
# The build-typescript repository plus the harness from the bundled assets, with planted state:
# 3 of 8 source files are 400-700 lines, src/domain/a.ts imports ../infra/db, one file has Portuguese
# identifiers, and src/domain/b.ts has no test. Needs npm and network (the base scaffold installs).
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bash "$here/../build-typescript/scaffold.sh"
# shellcheck disable=SC1091
. "$here/harness.sh"
install_harness --typescript

mkdir -p src/domain src/infra src/app
cat > src/infra/db.ts <<'TS'
export const db = { query: (sql: string): string[] => [sql] };
TS
cat > src/domain/a.ts <<'TS'
import { db } from "../infra/db";
export function load(id: string): string[] { return db.query(`select * from t where id = '${id}'`); }
TS
cat > src/domain/b.ts <<'TS'
export function double(n: number): number { return n * 2; }
TS
gen() { # gen <file> <lines> <prefix>
  : > "$1"
  for i in $(seq 1 "$2"); do printf 'export const %s%d = (n: number): number => n + %d;\n' "$3" "$i" "$i" >> "$1"; done
}
gen src/app/big1.ts 450 alpha
gen src/app/big2.ts 520 beta
gen src/app/big3.ts 700 gamma
cat > src/app/relatorio.ts <<'TS'
// calcula o valor total do pedido do cliente
export function calcularValorTotal(listaPedidos: number[]): number {
  const valorTotal = listaPedidos.reduce((soma, valor) => soma + valor, 0);
  return valorTotal;
}
TS
git add -A && git -c user.email=eval@local -c user.name=eval commit -qm "harness and planted state"
