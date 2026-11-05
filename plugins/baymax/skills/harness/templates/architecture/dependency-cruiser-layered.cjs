// Baymax template: replace every <placeholder> with this repository's real path or package, then remove this line. Protect this file with config: in .agents/bmax.yml.
// layered: web -> service -> repository; no upward calls.
/** @type {import('dependency-cruiser').IConfiguration} */
module.exports = {
  forbidden: [
    {
      name: "service-not-to-outer",
      comment: "Layer 'service' may not depend on an outer layer (web).",
      severity: "error",
      from: { path: "^<service>/" },
      to: { path: "^(<web>)/" }
    },
    {
      name: "repository-not-to-outer",
      comment: "Layer 'repository' may not depend on an outer layer (web, service).",
      severity: "error",
      from: { path: "^<repository>/" },
      to: { path: "^(<web>|<service>)/" }
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
