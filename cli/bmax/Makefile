VERSION ?= 0.5.0-dev
DIST ?= dist
PLATFORMS := linux-amd64 linux-arm64 darwin-amd64 darwin-arm64
SHA256 := $(shell command -v sha256sum >/dev/null 2>&1 && echo sha256sum || echo "shasum -a 256")

.PHONY: build test dist lock

# A git hook exports GIT_DIR, GIT_INDEX_FILE ... and the tests run git in temporary directories: never pass them on.
unexport $(shell git rev-parse --local-env-vars 2>/dev/null) BMAX_ROOT

build:
	CGO_ENABLED=0 go build -trimpath -buildvcs=false -ldflags "-X main.version=$(VERSION)" -o dist/bmax .

test:
	@test -z "$$(gofmt -l .)" || { echo "gofmt needed:"; gofmt -l .; exit 1; }
	go vet ./...
	go test ./...

# dist: reproducible binaries for the four platforms and their SHA256SUMS.
# The same source, Go toolchain and VERSION give byte-identical files.
dist:
	mkdir -p $(DIST)
	rm -f $(DIST)/SHA256SUMS
	for p in $(PLATFORMS); do \
	  rm -f $(DIST)/bmax-$$p; \
	  GOOS=$${p%-*} GOARCH=$${p#*-} CGO_ENABLED=0 go build -trimpath -buildvcs=false \
	    -ldflags "-s -w -buildid= -X main.version=$(VERSION)" -o $(DIST)/bmax-$$p . || exit 1; \
	done
	cd $(DIST) && for p in $(PLATFORMS); do $(SHA256) bmax-$$p; done > SHA256SUMS

# lock: prints a bmax.lock for VERSION from $(DIST)/SHA256SUMS.
lock:
	@printf '# bmax.lock - bmax pin; written by Baymax, do not edit by hand\nversion=%s\n' "$(VERSION)"
	@awk '{ n = $$2; sub(/^bmax-/, "", n); print n "=" $$1 }' $(DIST)/SHA256SUMS
