#!/bin/bash
# Uploads a bundle made by central_bundle.sh to the Maven Central Portal as a deployment that waits to be published by
# hand, then waits for the Portal to validate it. Authenticates with a Portal user token from CENTRAL_TOKEN_USERNAME
# and CENTRAL_TOKEN_PASSWORD, asking for either if unset. Needs curl and jq.
#
# usage: central_upload.sh <bundle.zip> <deployment name>
set -euo pipefail
BUNDLE=$1
NAME=$2
PORTAL=https://central.sonatype.com

if [ -z "${CENTRAL_TOKEN_USERNAME:-}" ]; then read -rp "Portal user token username: " CENTRAL_TOKEN_USERNAME; fi
if [ -z "${CENTRAL_TOKEN_PASSWORD:-}" ]; then read -rsp "Portal user token password: " CENTRAL_TOKEN_PASSWORD; echo; fi
token=$(printf '%s:%s' "$CENTRAL_TOKEN_USERNAME" "$CENTRAL_TOKEN_PASSWORD" | base64 | tr -d '\n')

# POSTs to the Portal and prints the response, or the Portal's error on stderr. The header goes to curl on stdin so
# that the token stays out of the process list.
portal() {
  local response
  if ! response=$(printf 'Authorization: Bearer %s\n' "$token" | curl --fail-with-body -sS -X POST -H @- "$@"); then
    echo "$response" >&2
    return 1
  fi
  echo "$response"
}

id=$(portal -F "bundle=@$BUNDLE" "$PORTAL/api/v1/publisher/upload?name=$NAME&publishingType=USER_MANAGED")
echo "Uploaded $BUNDLE as deployment $id"
for _ in $(seq 60); do
  status=$(portal "$PORTAL/api/v1/publisher/status?id=$id")
  state=$(jq -r .deploymentState <<< "$status")
  echo "$state"
  case "$state" in
    VALIDATED)
      echo "Validated; publish it at $PORTAL/publishing/deployments"
      exit 0
      ;;
    FAILED)
      jq . <<< "$status" >&2
      exit 1
      ;;
  esac
  sleep 10
done
echo "Still $state after 10 minutes; see $PORTAL/publishing/deployments" >&2
exit 1
