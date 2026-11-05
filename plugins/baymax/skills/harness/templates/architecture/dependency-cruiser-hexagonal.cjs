// Baymax template: replace every <placeholder> with this repository's real path or package, then remove this line. Protect this file with config: in .agents/bmax.yml.
// hexagonal: adapters -> application -> domain; the domain imports no framework.
/** @type {import('dependency-cruiser').IConfiguration} */
module.exports = {
  forbidden: [
    {
      name: "application-not-to-outer",
      comment: "Layer 'application' may not depend on an outer layer (adapters).",
      severity: "error",
      from: { path: "^<application>/" },
      to: { path: "^(<adapters>)/" }
    },
    {
      name: "domain-not-to-outer",
      comment: "Layer 'domain' may not depend on an outer layer (adapters, application).",
      severity: "error",
      from: { path: "^<domain>/" },
      to: { path: "^(<adapters>|<application>)/" }
    },
    {
      name: "no-framework-in-domain",
      comment: "The domain imports no framework.",
      severity: "error",
      from: { path: "^<domain>/" },
      to: { path: "(^|/)node_modules/(express|@nestjs|react|typeorm|prisma)(/|$)" }
    },
    {
      name: "no-circular",
      comment: "No dependency cycles.",
      severity: "error",
      from: {},
      to: { circular: true }
    }
  ],
  options: { tsPreCompilationDeps: true, doNotFollow: { path: "node_modules" }, tsConfig: { fileName: "tsconfig.json" } }
};
