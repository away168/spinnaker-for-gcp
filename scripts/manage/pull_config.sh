#!/usr/bin/env bash

bold() {
  echo ". $(tput bold)" "$*" "$(tput sgr0)";
}

CURRENT_CONTEXT=$(kubectl config current-context)

if [ "$?" != "0" ]; then
  bold "No current Kubernetes context is configured."
  exit 1
fi

HALYARD_POD=spin-halyard-0

TEMP_DIR=$(mktemp -d -t halyard.XXXXX)
pushd $TEMP_DIR

mkdir .hal

# Remove local config so persistent config from Halyard Daemon pod can be copied into place.
bold "Removing $HOME/.hal..."
rm -rf ~/.hal

# Copy persistent config into place.
bold "Copying halyard/$HALYARD_POD:/home/spinnaker/.hal into $HOME/.hal..."

kubectl cp halyard/$HALYARD_POD:/home/spinnaker/.hal .hal

source ~/spinnaker-for-gcp/scripts/manage/restore_config_utils.sh
rewrite_hal_key_paths

# We want just these subdirs from the Halyard Daemon pod to be copied into place in ~/.hal.
copy_hal_subdirs
cp .hal/config ~/.hal

EXISTING_DEPLOYMENT_SECRET_NAME=$(kubectl get secret -n halyard \
  --field-selector metadata.name=="spinnaker-deployment" \
  -o json | jq .items[0].metadata.name)

if [ $EXISTING_DEPLOYMENT_SECRET_NAME != 'null' ]; then
  bold "Restoring Spinnaker deployment config files from Kubernetes secret spinnaker-deployment..."
  DEPLOYMENT_SECRET_DATA=$(kubectl get secret spinnaker-deployment -n halyard -o json)

  extract_to_file_if_defined() {
    DATA_ITEM_VALUE=$(echo $DEPLOYMENT_SECRET_DATA | jq -r ".data.\"$1\"")

    if [ $DATA_ITEM_VALUE != 'null' ]; then
      echo $DATA_ITEM_VALUE | base64 -d > $2
    fi
  }

  extract_to_file_if_defined properties ~/spinnaker-for-gcp/scripts/install/properties
  extract_to_file_if_defined config.json ~/spinnaker-for-gcp/scripts/install/spinnakerAuditLog/config.json
  extract_to_file_if_defined index.js ~/spinnaker-for-gcp/scripts/install/spinnakerAuditLog/index.js
  extract_to_file_if_defined configure_iap_expanded.md ~/spinnaker-for-gcp/scripts/expose/configure_iap_expanded.md
  extract_to_file_if_defined openapi_expanded.yml ~/spinnaker-for-gcp/scripts/expose/openapi_expanded.yml
  extract_to_file_if_defined landing_page_expanded.md ~/spinnaker-for-gcp/scripts/manage/landing_page_expanded.md
  mkdir -p ~/.spin
  extract_to_file_if_defined config ~/.spin/config
  extract_to_file_if_defined key.json ~/.spin/key.json

  rewrite_spin_key_path
fi

popd
rm -rf $TEMP_DIR
