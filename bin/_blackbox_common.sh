#!/usr/bin/env bash

#
# Common constants and functions used by the blackbox_* utilities.
#

# Usage:
#   . _blackbox_common.sh

# Where in the VCS repo should the blackbox data be found?
: ${BLACKBOXDATA:=keyrings/live} ;   # If BLACKBOXDATA not set, set it.

set -e
 
# Outputs a string that is the base directory of this VCS repo.
# By side-effect, sets the variable VCS_TYPE to either 'git', 'hg',
# or 'unknown'.
function _determine_vcs_base_and_type() {
  if hg root 2>/dev/null ; then
    VCS_TYPE=hg
  elif git rev-parse --show-toplevel 2>/dev/null ; then
    VCS_TYPE=git
  else
    echo /dev/null
    VCS_TYPE=unknown
  fi
}

REPOBASE=$(_determine_vcs_base_and_type)
KEYRINGDIR="$REPOBASE/$BLACKBOXDATA"
BB_ADMINS_FILE="blackbox-admins.txt"
BB_ADMINS="${KEYRINGDIR}/${BB_ADMINS_FILE}"
BB_FILES_FILE="blackbox-files.txt"
BB_FILES="${KEYRINGDIR}/${BB_FILES_FILE}"
SECRING="${KEYRINGDIR}/secring.gpg"
PUBRING="${KEYRINGDIR}/pubring.gpg"

# Exit with error if a file exists.
function fail_if_exists() {
  if [[ -f "$1" ]]; then
    echo ERROR: "$1" exists.  "$2"
    echo Exiting...
    exit 1
  fi
}

# Exit with error if a file is missing.
function fail_if_not_exists() {
  if [[ ! -f "$1" ]]; then
    echo ERROR: "$1" not found.  "$2"
    echo Exiting...
    exit 1
  fi
}

# Exit we we aren't in a VCS repo.
function fail_if_not_in_repo() {
  _determine_vcs_base_and_type
  if [[ $VCS_TYPE = "unknown" ]]; then
    echo "ERROR: This must be run in a VCS repo such as git or hg."
    echo Exiting...
    exit 1
  fi
}

# Exit with error if filename is not registered on blackbox list.
function fail_if_not_on_cryptlist() {
  if ! grep -s -q "$name" "$BB_FILES" ; then
    echo 'ERROR: Please run this script from the base directory.'
    echo 'Exiting...'
    exit 1
  fi
}

# Exit with error if keychain contains secret keys.
function fail_if_keychain_has_secrets() {
  if [[ -s ${SECRING} ]]; then
    echo 'ERROR: The file' "$SECRING" 'should be empty.'
    echo 'Did someone accidentally add this private key to the ring?'
    echo 'Exiting...'
    exit 1
  fi
}

# Output the unencrypted filename.
function get_unencrypted_filename() {
  echo $(dirname "$1")/$(basename "$1" .gpg) | sed -e 's#^\./##'
}

# Output the encrypted filename.
function get_encrypted_filename() {
  echo $(dirname "$1")/$(basename "$1" .gpg).gpg | sed -e 's#^\./##'
}

# Prepare keychain for use.
function prepare_keychain() {
  echo '========== Importing keychain: START'
  gpg --import "${PUBRING}" 2>&1 | egrep -v 'not changed$'
  echo '========== Importing keychain: DONE'
}

# Add file to list of encrypted files.
function add_filename_to_cryptlist() {
  # If the name is already on the list, this is a no-op.
  # However no matter what the datestamp is updated.
  local name
  name="$1"

  if grep -s -q "$name" "$BB_FILES" ; then
    echo ========== File is registered. No need to add to list.
  else
    echo ========== Adding file to list.
    touch "$BB_FILES"
    sort -u -o "$BB_FILES" <(echo "$name") "$BB_FILES"
  fi
}

# Print out who the current BB ADMINS are:
function disclose_admins() {
  echo ========== blackbox administrators are:
  cat "$BB_ADMINS"
}

# Encrypt file, overwriting .gpg if it exists.
function encrypt_file() {
  local unencrypted
  local encrypted
  unencrypted="$1"
  encrypted="$2"

  echo "========== Encrypting: $unencrypted"
  gpg --yes --trust-model=always --encrypt -o "$encrypted"  $(awk '{ print "-r" $1 }' < "$BB_ADMINS") "$unencrypted"
  echo '========== Encrypting: DONE'
}

# Decrypt .gpg file, asking "yes/no" before overwriting unencrypted file.
function decrypt_file() {
  local encrypted
  local unencrypted
  encrypted="$1"
  unencrypted="$2"

  echo "========== EXTRACTING $unencrypted"
  gpg -q --decrypt -o "$unencrypted" "$encrypted"
}

# Decrypt .gpg file, overwriting unencrypted file if it exists.
function decrypt_file_overwrite() {
  local encrypted
  local unencrypted
  local old_hash
  local new_hash
  encrypted="$1"
  unencrypted="$2"

  if [[ -f "$unencrypted" ]]; then
    old_hash=$(md5sum_file "$unencrypted")
  else
    old_hash=unmatchable
  fi
  gpg --yes -q --decrypt -o "$unencrypted" "$encrypted"
  new_hash=$(md5sum_file "$unencrypted")
  if [[ $old_hash != $new_hash ]]; then
    echo "========== EXTRACTED $unencrypted"
  fi
}

# Shred a file.  If shred binary does not exist, delete it.
function shred_file() {
  local name
  local CMD
  local OPT
  name="$1"

  if which shred >/dev/null ; then
    CMD=shred
    OPT=-u
  else
    CMD=rm
    OPT=-f
  fi

  $CMD $OPT "$name"
}

function md5sum_file() {
  # Portably generate the MD5 hash of file $1.
  case $(uname -s) in
    Darwin )
      md5 -r "$1" | awk '{ print $1 }'
      ;;
    Linux )
      md5sum "$1" | awk '{ print $1 }'
      ;;
    * )
      echo 'ERROR: Unknown OS. Exiting.'
      exit 1
      ;;
  esac
}

# $1 is the name of a file that contains a list of files.
# For each filename, output the individual subdirectories
# leading up to that file. i.e. one one/two one/two/three
function enumerate_subdirs() {
  local listfile
  local dir
  local filename
  listfile="$1"

  while read filename; do
    dir=$(dirname "$filename")
    while [[ $dir != '.' && $dir != '/' ]]; do
      echo $dir
      dir=$(dirname $dir)
    done
  done <"$listfile" | sort -u
}

# Are we in git, hg, or unknown repo?
function which_vcs() {
  if [[ $VCS_TYPE = '' ]]; then
    _determine_vcs_base_and_type >/dev/null
  fi
  echo "$VCS_TYPE"
}


# Is this file in the current repo?
function is_in_vcs() {
  is_in_$(which_vcs) """$@"""
}
# Mercurial
function is_in_hg() {
  local filename
  filename="$1"

  if hg locate "$filename" ; then
    echo true
  else
    echo false
  fi
}
# Git:
function is_in_git() {
  local filename
  filename="$1"

  if git ls-files --error-unmatch >/dev/null 2>&1 -- "$filename" ; then
    echo true
  else
    echo false
  fi
}


# Add a file to the repo (but don't commit it).
function vcs_add() {
  vcs_add_$(which_vcs) """$@"""
}
# Mercurial
function vcs_add_hg() {
  hg add """$@"""
}
# Git
function vcs_add_git() {
  git add """$@"""
}

# Commit a file to the repo
function vcs_commit() {
  vcs_commit_$(which_vcs) """$@"""
}
# Mercurial
function vcs_commit_hg() {
  hg commit -m"""$@"""
}
# Git
function vcs_commit_git() {
  git commit -m"""$@"""
}


# TODO(tlim): Rename these vcs_rm_file* to be in sync with the others.

# Remove file from repo, even if it was deleted locally already.
# If it doesn't exist yet in the repo, it should be a no-op.
function vcs_remove() {
  vcs_remove_$(which_vcs) """$@"""
}
# Mercurial
function vcs_remove_hg() {
  hg rm -A """$@"""
}
# Git
function vcs_remove_git() {
  git rm --ignore-unmatch -f -- """$@"""
}
