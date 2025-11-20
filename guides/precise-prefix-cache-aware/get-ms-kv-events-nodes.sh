#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: get-ms-kv-events-nodes.sh [-n namespace] [-s selector]

Fetch Pod IP, node name, and datacenter label for ms-kv-events pods and print CSV.

Options:
  -n namespace   Kubernetes namespace to search (default: default)
  -s selector    Label selector to target pods (default: llm-d.ai/model=ms-kv-events-llm-d-modelservice)
  -h             Show this help message

The script requires kubectl access to the cluster context and jq installed locally.
EOF
}

NAMESPACE="default"
SELECTOR="llm-d.ai/model=ms-kv-events-llm-d-modelservice"
LABEL_KEY='llm-infer\.qifand\.com/datacenter-cluster'

while getopts ":n:s:h" opt; do
  case "${opt}" in
    n)
      NAMESPACE="${OPTARG}"
      ;;
    s)
      SELECTOR="${OPTARG}"
      ;;
    h)
      usage
      exit 0
      ;;
    :)
      echo "Option -${OPTARG} requires an argument" >&2
      usage
      exit 1
      ;;
    *)
      usage
      exit 1
      ;;
  esac
done

command -v kubectl >/dev/null 2>&1 || { echo "kubectl is required" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq is required" >&2; exit 1; }

mapfile -t POD_ROWS < <(
  kubectl get pods -n "${NAMESPACE}" -l "${SELECTOR}" -o json \
    | jq -r '.items[] | [.metadata.name // "", .status.podIP // "", .spec.nodeName // ""] | @tsv'
)

if [[ ${#POD_ROWS[@]} -eq 0 ]]; then
  echo "No pods matched selector '${SELECTOR}' in namespace '${NAMESPACE}'" >&2
  exit 1
fi

declare -A NODE_LABEL_CACHE=()

get_node_label() {
  local node_name="$1"
  if [[ -z "${node_name}" ]]; then
    echo ""
    return
  fi
  if [[ -n "${NODE_LABEL_CACHE[${node_name}]:-}" ]]; then
    echo "${NODE_LABEL_CACHE[${node_name}]}"
    return
  fi
  local node_label
  if ! node_label=$(kubectl get node "${node_name}" -o "jsonpath={.metadata.labels['${LABEL_KEY}']}"); then
    node_label=""
  fi
  NODE_LABEL_CACHE["${node_name}"]="${node_label}"
  echo "${node_label}"
}

echo "PodIP,NodeName,DatacenterLabel"
for row in "${POD_ROWS[@]}"; do
  IFS=$'\t' read -r pod_name pod_ip node_name <<<"${row}"
  datacenter_label=$(get_node_label "${node_name}")
  echo "${pod_ip},${node_name},${datacenter_label}"
done
