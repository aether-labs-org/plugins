# kh, the keel harness CLI. `make build` -> dist/kh + dist/SHA256SUMS for this machine; `make dist` -> every platform.
VERSION   := 0.1.0
export GOTOOLCHAIN := go1.27.3
PLATFORMS := linux-amd64 linux-arm64 darwin-amd64 darwin-arm64
GOFLAGS   := -trimpath -buildvcs=false
LDFLAGS   := -s -w -buildid= -X main.version=$(VERSION)
HOST      := $(shell go env GOOS)-$(shell go env GOARCH)

.PHONY: build dist test
build:
	CGO_ENABLED=0 go build $(GOFLAGS) -ldflags '$(LDFLAGS)' -o dist/kh .
	mkdir -p dist/$(HOST) && cp dist/kh dist/$(HOST)/kh
	cd dist && sha256sum $(HOST)/kh > SHA256SUMS

dist:
	rm -rf dist/engine && mkdir -p dist/engine
	for p in $(PLATFORMS); do \
	  CGO_ENABLED=0 GOOS=$${p%-*} GOARCH=$${p#*-} go build $(GOFLAGS) -ldflags '$(LDFLAGS)' -o dist/engine/$$p/kh . || exit 1; \
	done
	cd dist/engine && sha256sum */kh > SHA256SUMS

test:
	test -z "$$(gofmt -l .)" || { gofmt -l .; echo "gofmt: format the files above"; exit 1; }
	go vet ./...
	go test ./...
