// Baymax template: replace every <placeholder> with this repository's real path or package, then remove this line. Protect this file with config: in .agents/bmax.yml.
// modular: modules depend only on each other's public API (index).
/** @type {import('dependency-cruiser').IConfiguration} */
module.exports = {
  forbidden: [
    {
      name: "module-public-api-only",
      comment: "A module imports another module only through its index.",
      severity: "error",
      from: { path: "^<modules>/([^/]+)/" },
      to: { path: "^<modules>/([^/]+)/(?!index)", pathNot: "^<modules>/$1/" }
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
