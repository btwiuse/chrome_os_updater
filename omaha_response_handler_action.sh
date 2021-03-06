#!/bin/bash
# 2019 (c) Muntashir Al-Islam. All rights reserved.
# This file is converted from the original omaha_response_handler_action.cc
# located at https://chromium.googlesource.com/chromiumos/platform/update_engine/+/refs/heads/master/omaha_response_handler_action.cc
# fetched at 30 Jun 2019

# Get script directory
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

. "$SCRIPT_DIR/omaha_request_action.sh"
[ command -v debug >/dev/null 2>&1 ] || source "${SCRIPT_DIR}/debug_utils.sh"

kDeadlineFile="/tmp/update-check-response-deadline"
kCrosUpdateConf="/usr/local/cros_update.conf" # Our conf file
# cros_update.conf format:
# ROOTA='<ROOT-A UUID, lowercase>'
# ROOTB='<ROOT-B UUID, lowercase>'
# EFI='<EFI-SYSTEM UUID, lowercase>'
# TPM=true/false (default: auto)


# install_plan assoc array, refer to ./payload_consumer/install_plan.cc
declare -A install_plan


function GetDownloadRoot {
    if [ -n "${CROS_DOWNLOAD_ROOT}" ]; then
        echo "${CROS_DOWNLOAD_ROOT}"
    else
        echo '/usr/local/updater'
    fi
}


function GetCurrentSlot {  # Actually get current /dev/sdXX
    rootdev -s 2> /dev/null
}


# $1: Label
# $2: Device root (e.g. /dev/sd%D)
function FindPartitionByLabel {
    local label=$1
    local root_dev=$2
    if ! [ $root_dev ]; then
      root_dev=`rootdev -s -d 2> /dev/null`
    fi
    /sbin/blkid -o device -t PARTLABEL="${label}" "$root_dev"*
}


# Get partition by UUID, if not found, try using label
# $1: UUID
# $2: Label
function GetPartitionFromUUID {
    local uuid=$1  # Can be empty
    local label=$2  # Not empty
    local part=
    if [ "$uuid" == "" ]; then
      echo_stderr "Warning: Empty UUID for ${label}, default will be used."
      part=$(FindPartitionByLabel "${label}")
    else
      part=`/sbin/blkid --uuid "${uuid}"`
      if [ "${part}" == "" ]; then
        echo_stderr "Warning: Given UUID for ${label} not found, default will be used."
        part=$(FindPartitionByLabel "${label}")
      fi
    fi
    echo "${part}"
}

#
# OmahaResponseHandlerAction::PerformAction
#
function OmahaResponseHandlerAction_PerformAction {
    if ! [ ${ORA_update_exists} ]; then
      echo_stderr "There are no updates. Aborting."
      return 1
    fi
    # PayloadState::GetCurrentURL is not necessary right now.
    # We're only going to use the first item
    # Backup HTTPS url should always supply, but just in case
    install_plan['download_url']="${ORA_payload_urls[1]}"
    install_plan['version']="${ORA_version}"
    install_plan['system_version']=  # TODO
    # No p2p support right now
    install_plan['payload_size']="${ORA_size}"  # Renamed to payloads.size
    install_plan['payload_hash']="${ORA_hash}"  # Renamed to payloads.hash
    install_plan['metadata_size']="${ORA_metadata_size}"  # Renamed to payloads.metadata_size
    install_plan['metadata_signature']="${ORA_metadata_signature}"  # Renamed to payloads.metadata_signature
    install_plan['public_key_rsa']="${ORA_public_key_rsa}"
    install_plan['hash_checks_mandatory']=false  # since no p2p support
    install_plan['is_resume']=true  # Since we're using curl with -C option
    install_plan['is_full_update']="${ORA_is_delta_payload}"  # Renamed to payloads.type = is_delta_payload ? kDelta : kFull
    install_plan['kernel_install_path']=  # We don't need this
    install_plan['powerwash_required']=false  # For now
    # target and source slots: we use them as /dev/sdXX loaded from cros_update.conf
    # Details specification: http://www.chromium.org/chromium-os/chromiumos-design-docs/disk-format
    install_plan['target_slot_alphabet']=  # Alphabet 'A' or 'B' of the target slot
    install_plan['target_slot']=  # For our case, it's actually the target partition
    install_plan['source_slot']=  # For our case, it's actually the source partition
    install_plan['efi_slot']=  # Not included in the original install_plan, but required for us
    install_plan['tpm']="auto"  # TPM support is automatically detected by default
    # Create cros_update.conf if not exists
    touch "${kCrosUpdateConf}"
    # Use the conf
    source "${kCrosUpdateConf}"
    # Set the values of the slot, if not found find them
    # Again, we don't need is_install since install won't be supported
    # FIXME: Should be part of BootControl
    local root_a=$(GetPartitionFromUUID "${ROOTA}" 'ROOT-A')
    local root_b=$(GetPartitionFromUUID "${ROOTB}" 'ROOT-B')
    local current_slot=$(GetCurrentSlot)
    install_plan['source_slot']=${current_slot}
    if [ "${current_slot}" == "${root_a}" ]; then
      install_plan['target_slot_alphabet']="B"
      install_plan['target_slot']=${root_b}
    elif [ "${current_slot}" == "${root_b}" ]; then
      install_plan['target_slot_alphabet']="A"
      install_plan['target_slot']=${root_a}
    else
      echo_stderr "No valid target partition is found. Update aborted."
      return 1
    fi
    install_plan['efi_slot']=$(GetPartitionFromUUID "${EFI}" 'EFI-SYSTEM')
    if [ -n "${TPM}" ]; then
      # Forced vtpm (true/false)
      install_plan['tpm']="${TPM}"
    fi
    install_plan['is_rollback']=true  # No functionality
    install_plan['powerwash_required']=false  # No functionality
    # No need for deadline since we're installing right away
    # Custom paths
    install_plan['download_root']="$(GetDownloadRoot)"  # Download root
    install_plan['update_file_path']=  # Update file path/location
    install_plan['tpm_url']="https://github.com/imperador/chromefy/raw/master/swtpm.tar"
    install_plan['target_partition']=  # Target partition path
    return 0
}


# Check environment variables
if [ "${0##*/}" == "omaha_response_handler_action.sh" ]; then
    OmahaResponseHandlerAction_PerformAction
    ( set -o posix ; set )
fi
