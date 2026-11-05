// Command bmax is the Baymax deterministic execution engine.
package main

import (
	"os"

	"github.com/aether-labs-org/plugins/cli/bmax/internal/cli"
)

var version = "0.5.0-dev"

func main() {
	cli.Version = version
	os.Exit(cli.Run(os.Args[1:], os.Stdout, os.Stderr))
}
