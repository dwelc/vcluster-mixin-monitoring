# vcluster-mixin-monitoring build

# `go install`-placed binaries (mixtool typically) live under $GOPATH/bin = $HOME/go/bin
# by default. Prepend so make finds them without the caller exporting PATH.
export PATH := $(HOME)/go/bin:$(PATH)

JB := jb
JSONNET := jsonnet
JSONNETFMT := jsonnetfmt
MIXTOOL := mixtool

MIXIN_DIR := mixin
VENDOR := $(MIXIN_DIR)/vendor
EXAMPLES := examples
DASHBOARDS_OUT := $(EXAMPLES)/dashboards

.PHONY: all build vendor fmt lint clean help

all: build

vendor: $(MIXIN_DIR)/jsonnetfile.json
	cd $(MIXIN_DIR) && $(JB) install

build: vendor
	@mkdir -p $(DASHBOARDS_OUT)
	@echo "→ generating alerts + rules + dashboards"
	$(MIXTOOL) generate all $(MIXIN_DIR)/mixin.libsonnet \
		--output-alerts $(EXAMPLES)/prometheus-alerts.yaml \
		--output-rules $(EXAMPLES)/prometheus-rules.yaml \
		--directory $(DASHBOARDS_OUT)

fmt:
	@find $(MIXIN_DIR) -name '*.libsonnet' -not -path '*/vendor/*' -exec $(JSONNETFMT) -i {} \;

lint: vendor
	$(MIXTOOL) lint $(MIXIN_DIR)/mixin.libsonnet

clean:
	rm -rf $(VENDOR) $(EXAMPLES)/prometheus-*.yaml $(DASHBOARDS_OUT)

help:
	@echo "Targets:"
	@echo "  vendor  — jb install dependencies into mixin/vendor"
	@echo "  build   — generate alerts.yaml, rules.yaml, dashboards/ into examples/"
	@echo "  fmt     — jsonnetfmt -i on all .libsonnet files"
	@echo "  lint    — mixtool lint the mixin"
	@echo "  clean   — remove build artifacts"
