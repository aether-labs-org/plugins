VERSION ?= 0.4.0-dev

.PHONY: build test

build:
	CGO_ENABLED=0 go build -trimpath -buildvcs=false -ldflags "-X main.version=$(VERSION)" -o dist/kh .

test:
	@test -z "$$(gofmt -l .)" || { echo "gofmt needed:"; gofmt -l .; exit 1; }
	go vet ./...
	go test ./...
