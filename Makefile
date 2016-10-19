# Set an output prefix, which is the local directory if not specified
PREFIX?=$(shell pwd -L)

# Used to populate version variable in main package.
VERSION=$(shell git describe --match 'v[0-9]*' --dirty='.m' --always)
REVISION=$(shell git rev-list -1 HEAD)

# Building VMWare Fusion VIX API
CGO_CFLAGS:=-I$(CURDIR)/vendor/libvix/include -Werror
CGO_LDFLAGS:=-L$(CURDIR)/vendor/libvix -lvixAllProducts -ldl -lpthread

DYLD_LIBRARY_PATH:=$(CURDIR)/vendor/libvix
LD_LIBRARY_PATH:=$(CURDIR)/vendor/libvix

# Disable dynamic pointer checks in cgo (newly introduced since 1.6)
# which will cause panic on some calls
# TODO - fix the hooklift VIX-c bindings
GODEBUG=cgocheck=0

export CGO_CFLAGS CGO_LDFLAGS DYLD_LIBRARY_PATH LD_LIBRARY_PATH GODEBUG


# Allow turning off function inlining and variable registerization
ifeq (${DISABLE_OPTIMIZATION},true)
	GO_GCFLAGS=-gcflags "-N -l"
	VERSION:="$(VERSION)-noopt"
endif

.PHONY: clean all fmt vet lint build test plugins
.DEFAULT: all
all: clean fmt vet lint build test vmx-alpine

ci: fmt vet lint plugins

AUTHORS: .mailmap .git/HEAD
	 git log --format='%aN <%aE>' | sort -fu > $@

# Package list
PKGS_AND_MOCKS := $(shell go list ./... | grep -v /vendor)
PKGS := $(shell echo $(PKGS_AND_MOCKS) | tr ' ' '\n' | grep -v /mock$)

check-govendor:
	$(if $(shell which govendor || echo ''), , \
		$(error Please install govendor: go get github.com/kardianos/govendor))

vendor-sync: check-govendor
	@echo "+ $@"
	@govendor sync

vet:
	@echo "+ $@"
	@go vet $(PKGS)

fmt:
	@echo "+ $@"
	@test -z "$$(gofmt -s -l . 2>&1 | grep -v ^vendor/ | tee /dev/stderr)" || \
		(echo >&2 "+ please format Go code with 'gofmt -s', or use 'make fmt-save'" && false)

fmt-save:
	@echo "+ $@"
	@gofmt -s -l . 2>&1 | grep -v ^vendor/ | xargs gofmt -s -l -w

lint:
	@echo "+ $@"
	$(if $(shell which golint || echo ''), , \
		$(error Please install golint: `go get -u github.com/golang/lint/golint`))
	@test -z "$$(golint ./... 2>&1 | grep -v ^vendor/ | grep -v mock/ | tee /dev/stderr)"

build: vendor-sync
	@echo "+ $@"
	@go build ${GO_LDFLAGS} $(PKGS)

clean:
	@echo "+ $@"
	-mkdir -p ./bin
	-rm -rf ./bin/*

install: vendor-sync
	@echo "+ $@"
	@go install ${GO_LDFLAGS} $(PKGS)

generate:
	@echo "+ $@"
	@go generate -x $(PKGS_AND_MOCKS)

test: vendor-sync
	@echo "+ $@"
	@go test -test.short -race -v $(PKGS)

test-full: vendor-sync
	@echo "+ $@"
	@go test -race $(PKGS)

plugins: vmware-fusion

vmware-fusion: vendor-sync vmx-alpine vmx-moby
	@echo "+ $@"
	go build -o build/infrakit-instance-vmware-fusion \
	-ldflags "-X main.Version=$(VERSION) -X main.Revision=$(REVISION)" \
	cmd/*.go

# VMX file uses absolute path to specify the iso image.  Added a target here
# to instead generate one from a template to use the iso in the iso/ directory.

vmx-alpine-get:
	@echo "+ $@"
	mkdir -p iso/
	cd iso/ && curl -O -sSL http://dl-cdn.alpinelinux.org/alpine/v3.4/releases/x86_64/alpine-3.4.4-x86_64.iso

ALPINE_ISO?=$(shell echo ${CURDIR}/iso/alpine-3.4.4-x86_64.iso | sed -e 's/\//\\\//g')
vmx-alpine: vmx-alpine-get
	@echo "+ $@"
	sed -e 's/@ALPINE_ISO@/${ALPINE_ISO}/g' vmx/alpine-3.4.4.vmwarevm/alpine-3.4.4.vmx.template > vmx/alpine-3.4.4.vmwarevm/alpine-3.4.4.vmx


vmx-moby-build:
	@echo "+ $@"
	mkdir -p iso/
	cd iso && git clone https://github.com/docker/moby.git
	cd iso/moby && make qemu-iso
	cp moby/alpine/mobylinux-bios.iso ./iso 


MOBY_ISO?=$(shell echo ${CURDIR}/iso/mobylinux-bios.iso | sed -e 's/\//\\\//g')
vmx-moby: vmx-moby-build
	@echo "+ $@"
	sed -e 's/@MOBY_ISO@/${MOBY_ISO}/g' vmx/mobylinux.vmwarevm/mobylinux.vmx.template > vmx/mobylinux.vmwarevm/mobylinux.vmx


