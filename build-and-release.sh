#!/usr/bin/env bash

set -euo pipefail

. "${BASH_SOURCE%/*}/brew-common.sh"

run_hub_cmd() {
  if [[ -n ${GITHUB_TOKEN:-} && ${GITHUB_TOKEN:-} != *yugabyte.githubToken* ]]; then
    ( set -x; hub "$@" )
  else
    log "Would have run the command but the GitHub token is not set: hub $*"
  fi
}

recreate_release=false
while [[ $# -gt 0 ]]; do
  case $1 in
    --existing-timestamp)
      shift
      export YB_BREW_TIMESTAMP=$1
      export YB_BREW_REUSE_PREBUILT=1
      if [[ ! $YB_BREW_TIMESTAMP =~ ^[0-9]{8}T[0-9]{6}$ ]]; then
        fatal "Invalid format of timestamp, should be: YYYYmmddTHHMMSS"
      fi
    ;;
    --recreate-release)
      recreate_release=true
    ;;
    *)
      fatal "Invalid option: $1"
  esac
  shift
done

if [[ -z ${GITHUB_TOKEN:-} ]]; then
  log "GITHUB_TOKEN is not set, won't be able to upload release artifacts"
elif [[ ${#GITHUB_TOKEN} != 40 ]]; then
  log "GITHUB_TOKEN has unexpected length: ${#GITHUB_TOKEN}, 40 characters expected"
else
  log "GITHUB_TOKEN has the expected length of 40 characters"
fi

if [[ ${GITHUB_TOKEN:-} == "(yugabyte.githubToken)" ]]; then
  log "GITHUB_TOKEN has its default value (yugabyte.githubToken), probably not set."
fi

this_repo_top_dir=$( cd "$( dirname "$0" )" && git rev-parse --show-toplevel )
if [[ ! -d $this_repo_top_dir ]]; then
  fatal "Failed to determine the top directory of the Git repository containing this script"
fi

export USER=$( whoami )
export PATH=/usr/local/bin:$PATH

repo_dir=$PWD
timestamp=$( date +%Y-%m-%dT%H_%M_%S )
num_commits=$( git rev-list --count HEAD )
num_commits=$( printf "%06d" $num_commits )
set_brew_timestamp
tag=$YB_BREW_TIMESTAMP
readonly brew_dir=/opt/yb-build/brew
mkdir -p "$brew_dir"
cd "$brew_dir"
"$repo_dir/brew-clone-and-build-all.sh"

create_release_cmd=( release create "$tag" -m "Release $tag" )
has_files=false
archive_prefix="$brew_dir/$YB_BREW_DIR_PREFIX-$YB_BREW_TIMESTAMP"
log "Looking for .tar.gz files and SHA256 checksum files with prefix: '$archive_prefix'"
for f in "$archive_prefix.tar.gz" \
         "$archive_prefix.tar.gz.sha256" \
         "$archive_prefix-"*".tar.gz" \
         "$archive_prefix-"*".tar.gz.sha256"; do
  if [[ -f $f ]]; then
    log "File '$f' exists, will upload."
    create_release_cmd+=( -a "$f" )
    has_files=true
  else
    log "File '$f' does not exist."
  fi
done
if ! "$has_files"; then
  fatal "No archive files found with prefix: '$archive_prefix'"
fi
cd "$this_repo_top_dir"
if "$recreate_release"; then
  log "Deleting the old release with this tag as requested by --recreate-release."
  set +e
  run_hub_cmd release delete "$tag"
  set -e
fi
run_hub_cmd "${create_release_cmd[@]}"
