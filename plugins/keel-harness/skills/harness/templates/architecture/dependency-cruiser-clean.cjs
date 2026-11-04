// keel template: replace every <placeholder> with this repository's real path or package, then remove this line. Protect this file with config: in .agents/keel.yml.
// clean: frameworks -> adapters -> use cases (application) -> entities (domain); dependencies point inward.
/** @type {import('dependency-cruiser').IConfiguration} */
module.exports = {
  forbidden: [
    {
      name: "adapters-not-to-outer",
      comment: "Layer 'adapters' may not depend on an outer layer (frameworks).",
      severity: "error",
      from: { path: "^<adapters>/" },
      to: { path: "^(<frameworks>)/" }
    },
    {
      name: "application-not-to-outer",
      comment: "Layer 'application' may not depend on an outer layer (frameworks, adapters).",
      severity: "error",
      from: { path: "^<application>/" },
      to: { path: "^(<frameworks>|<adapters>)/" }
    },
    {
      name: "domain-not-to-outer",
      comment: "Layer 'domain' may not depend on an outer layer (frameworks, adapters, application).",
      severity: "error",
      from: { path: "^<domain>/" },
      to: { path: "^(<frameworks>|<adapters>|<application>)/" }
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
