# keel CLI. `make build` -> dist/keel + dist/SHA256SUMS for this machine; `make dist` -> every platform.
VERSION   := 0.1.0
export GOTOOLCHAIN := go1.27.3
PLATFORMS := linux-amd64 linux-arm64 darwin-amd64 darwin-arm64
GOFLAGS   := -trimpath -buildvcs=false
LDFLAGS   := -s -w -buildid= -X main.version=$(VERSION)
HOST      := $(shell go env GOOS)-$(shell go env GOARCH)

.PHONY: build dist test
build:
	CGO_ENABLED=0 go build $(GOFLAGS) -ldflags '$(LDFLAGS)' -o dist/keel .
	mkdir -p dist/$(HOST) && cp dist/keel dist/$(HOST)/keel
	cd dist && sha256sum $(HOST)/keel > SHA256SUMS

dist:
	rm -rf dist/engine && mkdir -p dist/engine
	for p in $(PLATFORMS); do \
	  CGO_ENABLED=0 GOOS=$${p%-*} GOARCH=$${p#*-} go build $(GOFLAGS) -ldflags '$(LDFLAGS)' -o dist/engine/$$p/keel . || exit 1; \
	done
	cd dist/engine && sha256sum */keel > SHA256SUMS

test:
	go vet ./...
	go test ./...
