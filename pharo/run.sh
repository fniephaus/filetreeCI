################################################################################
# This file provides Pharo support for smalltalkCI. It is used in the context
# of a smalltalkCI build and it is not meant to be executed by itself.
################################################################################

################################################################################
# Select Pharo image download url. Exit if smalltalk_name is unsupported.
# Arguments:
#   smalltalk_name
# Return:
#   Pharo image download url
################################################################################
pharo::get_image_url() {
  local smalltalk_name=$1
  local arch=""
  
  if [ "PHARO_ARCH" == "x86_64" ]; then
    arch="/64" 
  fi
  case "${smalltalk_name}" in
    "Pharo-alpha")
      echo "get.pharo.org$arch/alpha"
      ;;
    "Pharo-stable")
      echo "get.pharo.org$arch/stable"
      ;;
    "Pharo-6.0")
      echo "get.pharo.org$arch/60"
      ;;
    "Pharo-5.0")
      echo "get.pharo.org/50"
      ;;
    "Pharo-4.0")
      echo "get.pharo.org/40"
      ;;
    "Pharo-3.0")
      echo "get.pharo.org/30"
      ;;
    *)
      print_error_and_exit "Unsupported Pharo version '${smalltalk_name}'."
      ;;
  esac
}

################################################################################
# Select Moose image download url. Exit if smalltalk_name is unsupported.
# Arguments:
#   smalltalk_name
# Return:
#   Moose image download url
################################################################################
moose::get_image_url() {
  local smalltalk_name=$1
  local moose_name

  case "${smalltalk_name}" in
    "Moose-trunk")
      moose_name="moose-6.1"
      ;;
    "Moose-6"*)
      moose_name="$(to_lowercase "${smalltalk_name}")"
      ;;
    *)
      print_error_and_exit "Unsupported Pharo version '${smalltalk_name}'."
      ;;
  esac

  echo "https://ci.inria.fr/moose/job/${moose_name}/\
lastSuccessfulBuild/artifact/${moose_name}.zip"
}

################################################################################
# Select Pharo vm download url. Exit if smalltalk_name is unsupported.
# Arguments:
#   smalltalk_name
# Return:
#   Pharo vm download url
################################################################################

# get os
pharo::get_os() {
	local TMP_OS=`uname | tr "[:upper:]" "[:lower:]"`
	if [[ "{$TMP_OS}" = *darwin* ]]; then
	    echo "mac";
	elif [[ "{$TMP_OS}" = *linux* ]]; then
	    echo "linux";
	elif [[ "{$TMP_OS}" = *win* ]]; then
	    echo "win";
	elif [[ "{$TMP_OS}" = *mingw* ]]; then
	    echo "win";
	else
	    echo "Unsupported OS";
	    exit 1;
	fi
}

# get vm url
# variables: 
#  PHARO_VM=stable*|latest
#  PHARO_ARCH=i386*|x86_64
#  LINUX_HEARTBEAT=threaded*|itimer
pharo::get_vm_url() {
  local smalltalk_name=$1
  local os="$(pharo::get_os)"
  local heartbeat=""
  local latest=""
  local arch=""

  if [ "$PHARO_VM" == "latest" ]; then
    latest="Latest"
  fi
  if [ "PHARO_ARCH" == "x86_64" ]; then
    arch="/64" 
  fi
  # in linux, we use threaded hearbeat by default
  if [ "$os" == "linux" ]; then
	if [ "$LINUX_HEARTBEAT" != "itimer" ]; then
	  heartbeat="T"
	fi
  fi
  # 
  case "${smalltalk_name}" in
    # NOTE: vmLatestXX should be updated every time new Pharo is released
    "Pharo-alpha")
      echo "get.pharo.org$arch/vm${heartbeat}${latest}60"
      ;;
    "Pharo-6.0")
      echo "get.pharo.org$arch/vm${heartbeat}${latest}60"
      ;;
    "Pharo-stable"|"Pharo-5.0"|"Moose-6"*)
      echo "get.pharo.org/vm50"
      ;;
    "Pharo-4.0")
      echo "get.pharo.org/vm40"
      ;;
    "Pharo-3.0")
      echo "get.pharo.org/vm30"
      ;;
    *)
      print_error_and_exit "Unsupported Pharo version '${smalltalk_name}'."
      ;;
  esac
}

################################################################################
# Download and move vm if necessary.
# Globals:
#   SMALLTALK_CI_VM
# Arguments:
#   smalltalk_name
################################################################################
pharo::prepare_vm() {
  local smalltalk_name=$1
  local pharo_vm_url="$(pharo::get_vm_url "${smalltalk_name}")"
  local pharo_vm_folder="${SMALLTALK_CI_VMS}/${smalltalk_name}"
  local pharo_zeroconf="${pharo_vm_folder}/zeroconfig"

  # Skip in case vm is already set up
  if is_file "${SMALLTALK_CI_VM}"; then
    return 0
  fi

  if ! is_dir "${pharo_vm_folder}"; then
    travis_fold start download_vm "Downloading ${smalltalk_name} vm..."
      timer_start

      mkdir "${pharo_vm_folder}"
      pushd "${pharo_vm_folder}" > /dev/null

      download_file "${pharo_vm_url}" "${pharo_zeroconf}"
      bash "${pharo_zeroconf}"

      popd > /dev/null

      timer_finish
    travis_fold end download_vm
  fi

  if is_headless; then
    echo "${pharo_vm_folder}/pharo \"\$@\"" > "${SMALLTALK_CI_VM}"
  else
    echo "${pharo_vm_folder}/pharo-ui \"\$@\"" > "${SMALLTALK_CI_VM}"
  fi
  chmod +x "${SMALLTALK_CI_VM}"

  if ! is_file "${SMALLTALK_CI_VM}"; then
    print_error_and_exit "Unable to set vm up at '${SMALLTALK_CI_VM}'."
  fi
}

################################################################################
# Download image if necessary and copy it to build folder.
# Globals:
#   SMALLTALK_CI_BUILD
#   SMALLTALK_CI_CACHE
# Arguments:
#   smalltalk_name
################################################################################
pharo::prepare_image() {
  local smalltalk_name=$1
  local pharo_image_url="$(pharo::get_image_url "${smalltalk_name}")"
  local pharo_image_file="${smalltalk_name}.image"
  local pharo_changes_file="${smalltalk_name}.changes"
  local pharo_zeroconf="${SMALLTALK_CI_CACHE}/${smalltalk_name}_zeroconfig"

  if ! is_file "${SMALLTALK_CI_CACHE}/${pharo_image_file}"; then
    travis_fold start download_image "Downloading ${smalltalk_name} image..."
      timer_start

      pushd "${SMALLTALK_CI_CACHE}" > /dev/null

      download_file "${pharo_image_url}" "${pharo_zeroconf}"
      bash "${pharo_zeroconf}"

      mv "Pharo.image" "${pharo_image_file}"
      mv "Pharo.changes" "${pharo_changes_file}"
      popd > /dev/null

      timer_finish
    travis_fold end download_image
  fi

  print_info "Preparing Pharo image..."
  cp "${SMALLTALK_CI_CACHE}/${pharo_image_file}" "${SMALLTALK_CI_IMAGE}"
  cp "${SMALLTALK_CI_CACHE}/${pharo_changes_file}" "${SMALLTALK_CI_CHANGES}"
}

################################################################################
# Download Moose image if necessary and extract it into build folder.
# Globals:
#   SMALLTALK_CI_BUILD
#   SMALLTALK_CI_CACHE
# Arguments:
#   smalltalk_name
################################################################################
pharo::prepare_moose_image() {
  local smalltalk_name=$1
  local moose_image_url="$(moose::get_image_url "${smalltalk_name}")"
  local target="${SMALLTALK_CI_CACHE}/${smalltalk_name}.zip"

  if ! is_file "${target}"; then
    travis_fold start download_image "Downloading ${smalltalk_name} image..."
      timer_start

      set +e
      download_file "${moose_image_url}" "${target}"
      if [[ ! $? -eq 0 ]]; then
        rm -f "${target}"
        print_error_and_exit "Download failed."
      fi
      set -e

      timer_finish
    travis_fold end download_image
  fi

  print_info "Extracting and preparing ${smalltalk_name} image..."
  unzip -q "${target}" -d "${SMALLTALK_CI_BUILD}"
  mv "${SMALLTALK_CI_BUILD}/"*.image "${SMALLTALK_CI_IMAGE}"
  mv "${SMALLTALK_CI_BUILD}/"*.changes "${SMALLTALK_CI_CHANGES}"

  if ! is_file "${SMALLTALK_CI_IMAGE}"; then
    print_error_and_exit "Failed to prepare image at '${SMALLTALK_CI_IMAGE}'."
  fi
}

################################################################################
# Run a Smalltalk script.
################################################################################
pharo::run_script() {
  local script=$1
  local vm_flags=""
  local resolved_vm="${config_vm:-${SMALLTALK_CI_VM}}"
  local resolved_image="$(resolve_path "${config_image:-${SMALLTALK_CI_IMAGE}}")"

  if ! is_travis_build && ! is_headless; then
    vm_flags="--no-quit"
  fi

  travis_wait "${resolved_vm}" "${resolved_image}" eval ${vm_flags} "${script}"
}

################################################################################
# Load project into Pharo image.
################################################################################
pharo::load_project() {
  pharo::run_script "
    | smalltalkCI |
    $(conditional_debug_halt)
    [ Metacello new
        baseline: 'SmalltalkCI';
        repository: 'filetree://$(resolve_path "${SMALLTALK_CI_HOME}/repository")';
        onConflict: [:ex | ex pass];
        load ] on: Warning do: [:w | w resume ].
    smalltalkCI := (Smalltalk at: #SmalltalkCI).
    smalltalkCI load: '$(resolve_path "${config_ston}")'.
    smalltalkCI isHeadless ifTrue: [ smalltalkCI saveAndQuitImage ]
  "
}

################################################################################
# Run tests for project.
################################################################################
pharo::test_project() {
  pharo::run_script "
    $(conditional_debug_halt)
    smalltalkCI := Smalltalk at: #SmalltalkCI ifAbsent: [
    [ Metacello new
        baseline: 'SmalltalkCI';
        repository: 'filetree://$(resolve_path "${SMALLTALK_CI_HOME}/repository")';
        onConflict: [:ex | ex pass];
        load ] on: Warning do: [:w | w resume ].
        Smalltalk at: #SmalltalkCI
    ].
    (Smalltalk at: #SmalltalkCI) test: '$(resolve_path "${config_ston}")'
  "
}

################################################################################
# Main entry point for Pharo builds.
################################################################################
run_build() {
  if ! image_is_user_provided; then
    case "${config_smalltalk}" in
      Pharo*)
        pharo::prepare_image "${config_smalltalk}"
        ;;
      Moose*)
        pharo::prepare_moose_image "${config_smalltalk}"
        ;;
    esac
  fi

  if ! vm_is_user_provided; then
    pharo::prepare_vm "${config_smalltalk}"
  fi
  if ston_includes_loading; then
    pharo::load_project
  fi
  pharo::test_project
}
