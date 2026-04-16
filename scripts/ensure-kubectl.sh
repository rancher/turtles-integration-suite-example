#!/usr/bin/env bash

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

set -o errexit
set -o nounset
set -o pipefail

if [[ "${TRACE-0}" == "1" ]]; then
    set -o xtrace
fi

source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"

GOPATH_BIN="$(go env GOPATH)/bin/"

# kubectl version and immutable checksum for validation
MINIMUM_KUBECTL_VERSION=v1.35.3
KUBECTL_SUM_linux_amd64="fd31c7d7129260e608f6faf92d5984c3267ad0b5ead3bced2fe125686e286ad6" # immutable sha256 for v1.35.3 linux amd64
KUBECTL_SUM_linux_arm64="6f0cd088a82dde5d5807122056069e2fac4ed447cc518efc055547ae46525f14" # immutable sha256 for v1.35.3 linux arm64
KUBECTL_SUM_darwin_amd64="2f339b1eae2e1792ec08da281b37afbeee94f70bed6b7398e7efd81ba08f8d37" # immutable sha256 for v1.35.3 darwin amd64
KUBECTL_SUM_darwin_arm64="280651239d84bab214ba83403666bf6976a5fa0dbdb41404f26eb6f276d34963" # immutable sha256 for v1.35.3 darwin arm64

# Krew version and immutable checksum for validation
KREW_VERSION="v0.5.0"
KREW_SUM_linux_amd64="5d5a221fffdf331d1c5c68d9917530ecd102e0def5b5a6d62eeed1c404efb28a" # immutable sha256 for krew v0.5.0 linux amd64
KREW_SUM_linux_arm64="ab7a98b992424e76b6c162f8b67fb76c4b1e243598aa2807bdf226752f964548" # immutable sha256 for krew v0.5.0 linux arm64
KREW_SUM_darwin_amd64="2d60559126452b57e3df0612f0475a473363f064da35f817290dbbcd877d1ea8" # immutable sha256 for krew v0.5.0 darwin amd64
KREW_SUM_darwin_arm64="cd6e58b4e954e301abd19001d772846997216d696bcaa58f0bcf04708339ece3" # immutable sha256 for krew v0.5.0 darwin arm64

goarch="$(go env GOARCH)"
goos="$(go env GOOS)"

# Ensure the kubectl tool exists and is a viable version, or installs it
verify_kubectl_version() {

  local kubectl_version
  IFS=" " read -ra kubectl_version <<< "$(kubectl version --client || echo 'v0.0.0')"

  # If kubectl is not available on the path, get it
  if ! [ -x "$(command -v kubectl)" ] || [[ "${MINIMUM_KUBECTL_VERSION}" != $(echo -e "${MINIMUM_KUBECTL_VERSION}\n${kubectl_version[2]}" | sort -s -t. -k 1,1 -k 2,2n -k 3,3n | head -n1) ]]; then
    if [ "$goos" == "linux" ] || [ "$goos" == "darwin" ]; then
      if ! [ -d "${GOPATH_BIN}" ]; then
        mkdir -p "${GOPATH_BIN}"
      fi

      echo "kubectl not found or below ${MINIMUM_KUBECTL_VERSION}, installing"
      echo "Updating to ${MINIMUM_KUBECTL_VERSION}."

      curl -sLo "${GOPATH_BIN}/kubectl" "https://dl.k8s.io/release/${MINIMUM_KUBECTL_VERSION}/bin/${goos}/${goarch}/kubectl"
      KUBECTL_SUM_VAR="KUBECTL_SUM_${goos}_${goarch}"
      echo "${!KUBECTL_SUM_VAR}  $GOPATH_BIN/kubectl" | sha256sum --check

      chmod +x "${GOPATH_BIN}/kubectl"
      verify_gopath_bin
    else
      echo "Missing required binary in path: kubectl"
      return 2
    fi
  fi
}

install_plugins() {
  (
    set -x; cd "$(mktemp -d)"
    OS="$(uname | tr '[:upper:]' '[:lower:]')"
    ARCH="$(uname -m | sed -e 's/x86_64/amd64/' -e 's/\(arm\)\(64\)\?.*/\1\2/' -e 's/aarch64$/arm64/')"
    KREW="krew-${OS}_${ARCH}"

    curl -fsSLO "https://github.com/kubernetes-sigs/krew/releases/download/${KREW_VERSION}/${KREW}.tar.gz"
    KREW_SUM_VAR="KREW_SUM_${OS}_${ARCH}"
    echo "${!KREW_SUM_VAR}  ${KREW}.tar.gz" | sha256sum --check

    tar zxvf "${KREW}.tar.gz"
    ./"${KREW}" install krew
  )
  kubectl krew version

  kubectl krew install crust-gather
  kubectl crust-gather --version
}

verify_kubectl_version
install_plugins
