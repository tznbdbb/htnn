#!/usr/bin/env bash
# Copyright The HTNN Authors.
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


set -eo pipefail
set -x

HELM="${LOCALBIN}/helm"
E2E_DIR="$(pwd)"

install() {
    OPTIONS_DISABLED="$1"

    # Print helm version for debugging
    echo "--- Helm version ---"
    $HELM version

    # Install yq for better YAML debugging
    if ! command -v yq &> /dev/null; then
        echo "--- Installing yq ---"
        sudo wget https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -O /usr/bin/yq && sudo chmod +x /usr/bin/yq
    fi

    pushd ../manifests/charts

    $HELM dependency update htnn-controller
    $HELM dependency update htnn-gateway
    $HELM package htnn-controller htnn-controller
    $HELM package htnn-gateway htnn-gateway

    CONTROLLER_VALUES_OPT="-f $E2E_DIR/htnn_controller_values.yaml"
    GATEWAY_VALUES_OPT="-f $E2E_DIR/htnn_gateway_values.yaml"
    if [ -n "$OPTIONS_DISABLED" ]; then
        CONTROLLER_VALUES_OPT=
        GATEWAY_VALUES_OPT=
    fi

    # shellcheck disable=SC2086
    $HELM install htnn-controller htnn-controller --namespace istio-system --create-namespace --wait $CONTROLLER_VALUES_OPT \
        || exitWithAnalysis

    echo "--- Debugging htnn-gateway installation ---"
    echo "--- Unpacking htnn-gateway chart for inspection ---"
    tar -xzf htnn-gateway-*.tgz
    echo "--- Content of htnn-gateway/Chart.yaml ---"
    cat htnn-gateway/Chart.yaml
    echo "--- Content of htnn-gateway/values.yaml ---"
    cat htnn-gateway/values.yaml
    echo "--- Content of htnn-gateway/charts/gateway/values.schema.json (the schema causing issues) ---"
    # The istio/gateway chart is inside the charts dir, we need to check its schema
    if [ -f "htnn-gateway/charts/gateway/values.schema.json" ]; then
        cat htnn-gateway/charts/gateway/values.schema.json
    fi

    echo "--- Running helm template to render final values (best for debugging) ---"
    # shellcheck disable=SC2086
    $HELM template htnn-gateway htnn-gateway --namespace istio-system --create-namespace $GATEWAY_VALUES_OPT --validate \
        || ( \
            echo "Helm template validation failed. Analyzing computed values for the 'gateway' sub-chart..." && \
            $HELM template htnn-gateway htnn-gateway --namespace istio-system --create-namespace $GATEWAY_VALUES_OPT > /tmp/template_output.yaml && \
            echo "--- Computed values for 'gateway' sub-chart: ---" && \
            yq '.gateway' /tmp/template_output.yaml && \
            exit 1 \
           )

    echo "--- Now attempting helm install for htnn-gateway ---"
    # shellcheck disable=SC2086
    $HELM install htnn-gateway htnn-gateway --namespace istio-system --create-namespace $GATEWAY_VALUES_OPT \
        && \
        (kubectl wait --timeout=5m -n istio-system deployment/istio-ingressgateway --for=condition=Available \
        || exitWithAnalysis)

    popd
}

installWithoutOptions() {
    install WithoutOptions
}

exitWithAnalysis() {
    kubectl get pods -n istio-system -o yaml
    for pod in $(kubectl get pods -n istio-system | grep 'istiod-' | awk '{print $1}'); do
        kubectl -n istio-system logs --tail=1000 "$pod"
        echo
    done
    for pod in $(kubectl get pods -n istio-system | grep 'istio-ingressgateway' | awk '{print $1}'); do
        kubectl -n istio-system logs --tail=1000 "$pod"
        echo
    done
    exit 1
}

uninstall() {
    $HELM uninstall htnn-controller -n istio-system && $HELM uninstall htnn-gateway -n istio-system && kubectl delete ns istio-system
}

opt=$1
shift

${opt} "$@"
