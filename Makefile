# Copyright © 2023 - 2024 SUSE LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Setting SHELL to bash allows bash commands to be executed by recipes.
# Options are set to exit when a recipe line exits non-zero or a piped command fails.
SHELL = /usr/bin/env bash -o pipefail
.SHELLFLAGS = -ec

# Directories
ROOT_DIR:=$(shell dirname $(realpath $(firstword $(MAKEFILE_LIST))))
BIN_DIR := bin
TEST_DIR := suites
TOOLS_DIR := hack/tools
TOOLS_BIN_DIR := $(abspath $(TOOLS_DIR)/$(BIN_DIR))
ARTIFACTS_FOLDER ?= ${ROOT_DIR}/_artifacts
ARTIFACTS ?= ${ARTIFACTS_FOLDER}

export PATH := $(abspath $(TOOLS_BIN_DIR)):$(PATH)
export KREW_ROOT := $(abspath $(TOOLS_BIN_DIR))
export PATH := $(KREW_ROOT)/bin:$(PATH)

# Tools
CURL_RETRIES = 3 # Retries to download a tool

GO_VERSION ?= $(shell grep "go " go.mod | head -1 |awk '{print $$NF}')
GO_INSTALL := ./scripts/go-install.sh

GINKGO_BIN := ginkgo
GINGKO_VER := $(shell grep "github.com/onsi/ginkgo/v2" go.mod | head -1 |awk '{print $$NF}')
GINKGO := $(abspath $(TOOLS_BIN_DIR)/$(GINKGO_BIN)-$(GINGKO_VER))
GINKGO_PKG := github.com/onsi/ginkgo/v2/ginkgo

HELM_VER := v3.18.4
HELM_BIN := helm
HELM := $(TOOLS_BIN_DIR)/$(HELM_BIN)-$(HELM_VER)

$(HELM): ## Put helm into tools folder.
	mkdir -p $(TOOLS_BIN_DIR)
	rm -f "$(TOOLS_BIN_DIR)/$(HELM_BIN)*"
	curl --retry $(CURL_RETRIES) -fsSL -o $(TOOLS_BIN_DIR)/get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
	chmod 700 $(TOOLS_BIN_DIR)/get_helm.sh
	USE_SUDO=false HELM_INSTALL_DIR=$(TOOLS_BIN_DIR) DESIRED_VERSION=$(HELM_VER) BINARY_NAME=$(HELM_BIN)-$(HELM_VER) $(TOOLS_BIN_DIR)/get_helm.sh
	ln -sf $(HELM) $(TOOLS_BIN_DIR)/$(HELM_BIN)
	rm -f $(TOOLS_BIN_DIR)/get_helm.sh

$(GINKGO): # Build ginkgo from tools folder.
	GOBIN=$(TOOLS_BIN_DIR) $(GO_INSTALL) $(GINKGO_PKG) $(GINKGO_BIN) $(GINGKO_VER)

kubectl: # Download kubectl cli if not available, and crust-gather plugin into tools bin folder
	scripts/ensure-kubectl.sh \
		-b $(TOOLS_BIN_DIR) ""

#
# Ginkgo configuration.
#
GINKGO_FOCUS ?=
GINKGO_SKIP ?=
GINKGO_NODES ?= 1
GINKGO_TIMEOUT ?= 2h
GINKGO_POLL_PROGRESS_AFTER ?= 60m
GINKGO_POLL_PROGRESS_INTERVAL ?= 5m
GINKGO_ARGS ?=
GINKGO_NOCOLOR ?= false
GINKGO_LABEL_FILTER ?=
GINKGO_TESTS ?= $(ROOT_DIR)/$(TEST_DIR)/...
E2E_CONFIG ?= $(ROOT_DIR)/config/config.yaml

# Test run configuration
E2ECONFIG_VARS ?= ROOT_DIR=$(ROOT_DIR) \
E2E_CONFIG=$(E2E_CONFIG) \
ARTIFACTS=$(ARTIFACTS) \
ARTIFACTS_FOLDER=$(ARTIFACTS_FOLDER) \
HELM_BINARY_PATH=$(HELM) \
TURTLES_PATH=$(E2E_CONFIG) #not really used, just for validation

.PHONY: test-e2e
test-e2e: $(HELM) $(GINKGO) kubectl ## Run the end-to-end tests
	$(E2ECONFIG_VARS) $(GINKGO) -v --trace -p -procs=10 -poll-progress-after=$(GINKGO_POLL_PROGRESS_AFTER) \
		-poll-progress-interval=$(GINKGO_POLL_PROGRESS_INTERVAL) --tags=e2e --focus="$(GINKGO_FOCUS)" --label-filter="$(GINKGO_LABEL_FILTER)" \
		$(_SKIP_ARGS) --nodes=$(GINKGO_NODES) --timeout=$(GINKGO_TIMEOUT) --no-color=$(GINKGO_NOCOLOR) \
		--output-dir="$(ARTIFACTS)" --junit-report="junit.e2e_suite.1.xml" $(GINKGO_ARGS) $(GINKGO_TESTS)
