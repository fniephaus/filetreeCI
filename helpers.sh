################################################################################
# This file provides helper functions for smalltalkCI. It is used in the context
# of a smalltalkCI build and it is not meant to be executed by itself.
################################################################################

readonly BUILD_STATUS_FILE="${SMALLTALK_CI_BUILD}/build_status.txt"
readonly GITHUB_API="https://api.github.com"
readonly COVERALLS_API="https://coveralls.io/api/v1/jobs"
readonly COVERALLS_OPTIONAL_KEYS="flag_name parallel repo_token service_job_id
  service_job_number service_name service_number service_pull_request"

readonly ANSI_BOLD="\033[1m"
readonly ANSI_RED="\033[31m"
readonly ANSI_GREEN="\033[32m"
readonly ANSI_YELLOW="\033[33m"
readonly ANSI_BLUE="\033[34m"
readonly ANSI_RESET="\033[0m"
readonly ANSI_CLEAR="\033[0K"

print_info() {
  if is_colorful; then
    printf "${ANSI_BOLD}${ANSI_BLUE}%s${ANSI_RESET}\n" "$1"
  else
    echo "$1"
  fi
}

print_notice() {
  if is_colorful; then
   printf "${ANSI_BOLD}${ANSI_YELLOW}%s${ANSI_RESET}\n" "$1"
  else
    echo "$1"
  fi
}

print_success() {
  if is_colorful; then
   printf "${ANSI_BOLD}${ANSI_GREEN}%s${ANSI_RESET}\n" "$1"
  else
    echo "$1"
  fi
}

print_error() {
  if is_colorful; then
   printf "${ANSI_BOLD}${ANSI_RED}%s${ANSI_RESET}\n" "$1" 1>&2
  else
    echo "$1"
  fi
}

print_error_and_exit() {
  print_error "$1"
  exit "${2:-1}" # 2nd parameter, 1 if not set
}

print_help() {
  cat <<EOF
  USAGE: $(basename -- $0) [options] /path/to/project/your_smalltalk.ston

  This program prepares Smalltalk images/vms, loads projects, and runs tests.

  OPTIONS:
    --clean             Clear cache and delete builds.
    -d | --debug        Enable debug mode.
    -h | --help         Show this help text.
    --headful           Open vm in headful mode and do not close image.
    --image             Custom image for build (Squeak/Pharo).
    --install           Install symlink to this smalltalkCI instance.
    --print-env         Print all environment variables used by smalltalkCI
    --no-color          Disable colored output
    --no-tracking       Disable collection of anonymous build metrics (TravisCI & AppVeyor only).
    -s | --smalltalk    Overwrite Smalltalk image selection.
    --uninstall         Remove symlink to any smalltalkCI instance.
    -v | --verbose      Enable 'set -x'.
    --vm                Custom VM for build (Squeak/Pharo).

  GEMSTONE OPTIONS:
    --gs-BRANCH=<branch-SHA-tag>
                        Name of GsDevKit_home branch, SHA, or tag. Default is 'master'.

                        Environment variable GSCI_DEVKIT_BRANCH may be used to
                        specify <branch-SHA-tag>. Command line option overrides
                        value of environment variable.

    --gs-HOME=<GS_HOME-path>
                        Path to an existing GsDevKit_home clone to be used
                        instead of creating a fresh clone.

                        --gs-DEVKIT_BRANCH option is ignored.

    --gs-CLIENTS="<smalltalk-platform>..."
                        List of Smalltalk client versions to use as a GemStone client.

                        Environment variable GSCI_CLIENTS may also be used to
                        specify a list of <smalltalk-platform> client versions.
                        Command line option overrides value of environment variable.

                        If a client is specified, tests are run for both the client
                        and server based using the project .smalltalk.ston file.

  EXAMPLE:
    $(basename -- $0) -s "Squeak64-trunk" --headfull /path/to/project/.smalltalk.ston

EOF
}

print_config() {
  for var in ${!config_@}; do
    echo "${var}=${!var}"
  done
}

print_env() {
  env | grep "SMALLTALK_CI_"
}

is_colorful() {
  [[ "${config_colorful:-true}" == "true" ]]
}

is_empty() {
  local var=$1

  [[ -z $var ]]
}

is_not_empty() {
  local var=$1

  [[ -n $var ]]
}

is_file() {
  local file=$1

  [[ -f $file ]]
}

is_dir() {
  local dir=$1

  [[ -d $dir ]]
}

is_nonzero() {
  local status=$1

  [[ "${status}" -ne 0 ]]
}

is_int() {
  local value=$1

  [[ $value =~ ^-?[0-9]+$ ]]
}

program_exists() {
  local program=$1

  [[ $(command -v "${program}" 2> /dev/null) ]]
}

is_travis_build() {
  [[ "${TRAVIS:-}" = "true" ]]
}

is_appveyor_build() {
  [[ "${APPVEYOR:-}" = "True" ]]
}

is_github_build() {
  [[ "${GITHUB_ACTIONS:-}" = "true" ]]
}

is_gitlabci_build() {
  [[ "${GITLAB_CI:-}" = "true" ]]
}

is_linux_build() {
  [[ $(uname -s) = "Linux" ]]
}

is_cygwin_build() {
  [[ $(uname -s) = "CYGWIN_NT-"* ]]
}

is_mingw64_build() {
  [[ $(uname -s) = "MINGW64_NT-"* ]]
}

is_sudo_enabled() {
  $(sudo -n true > /dev/null 2>&1)
}

is_tagged_build() {
  if [[ "${config_smalltalk}" =~ ^(Squeak(32|64))?-([[:digit:]]+)$ ]]; then
    source "${SMALLTALK_CI_HOME}/squeak/version_tags.sh"
    export SCIII_SMALLTALK_VERSION="${BASH_REMATCH[-1]}"
    export SCIII_LATEST_RELEASE="${BASH_REMATCH[1]}-$(squeak::latest_release_before ${SCIII_SMALLTALK_VERSION})"
    return 0
  fi
  return 1
}

is_trunk_build() {
  if is_tagged_build; then
    case "${config_smalltalk}" in
      Squeak*)
        if config_smalltalk="${SCIII_LATEST_RELEASE}" is_trunk_build; then
          return 0
        else
          return 1
        fi
      ;;
    esac
    return 1
  fi

  case "${config_smalltalk}" in
    *"trunk"|*"Trunk"|*"latest"|*"Latest")
      return 0
      ;;
  esac
  return 1
}

image_is_user_provided() {
  is_not_empty "${config_image}"
}

vm_is_user_provided() {
  is_not_empty "${config_vm}"
}

is_64bit() {
  [[ "${config_smalltalk}" == *"64-"* ]]
}

is_spur_image() {
  local image_path=$1
  local image_format_number
  # "[...] bit 5 of the format number identifies an image that requires Spur
  # support from the VM [...]"
  # http://forum.world.st/VM-Maker-ImageFormat-dtl-17-mcz-td4713569.html
  local spur_bit=5

  if is_empty "${image_path}"; then
    print_error "Image not found at '${image_path}'."
    return 0
  fi

  if hash hexdump 2>/dev/null; then
    image_format_number="$(hexdump -n 4 -e '2/4 "%04d " "\n"' "${image_path}")"
  elif hash xxd 2>/dev/null; then
    image_format_number="$((16#$(xxd -p -l 1 "${image_path}")))"
  else
    print_error_and_exit "Unable to detect image format (xxd or hexdump needed)"
  fi

  [[ $((image_format_number>>(spur_bit-1) & 1)) -eq 1 ]]
}

is_headless() {
  [[ "${config_headless}" = "true" ]]
}

ston_includes_loading() {
  grep -Fq "#loading" "${config_ston}"
}

debug_enabled() {
  [[ "${config_debug}" = "true" ]]
}

signals_error() {
  [[ $1 != "[success]" ]]
}

current_build_status_signals_error() {
  if ! is_file "${BUILD_STATUS_FILE}"; then
    print_error "Build was unable to report intermediate build status."
    return 0
  fi
  if signals_error "$(cat "${BUILD_STATUS_FILE}")"; then
    return 0
  fi
  return 1
}

consume_build_status_file() {
  rm -f "${BUILD_STATUS_FILE}"
}

check_and_consume_build_status_file() {
  local build_status

  if current_build_status_signals_error; then
    build_status="$(cat "${BUILD_STATUS_FILE}")"
    if [[ "${build_status}" == "[test failure]" ]]; then
      exit 1
    fi
    print_error_and_exit "${build_status}"
  fi
  consume_build_status_file
}

finalize() {
  local build_status

  if is_travis_build || is_appveyor_build || is_github_build; then
    upload_coveralls_results
  else
    print_info "Skipping coveralls upload."
  fi

  if ! is_file "${BUILD_STATUS_FILE}"; then
    print_error_and_exit "Build was unable to report final build status."
  fi
  build_status=$(cat "${BUILD_STATUS_FILE}")
  if is_travis_build; then
    deploy "${build_status}"
  fi
  if signals_error "${build_status}"; then
    if [[ "${build_status}" != "[test failure]" ]]; then
      print_error_and_exit "${build_status}"
    fi
    exit 1
  else
   exit 0
  fi
}

conditional_debug_halt() {
  if ! is_headless && debug_enabled; then
    printf "self halt.\n"
  fi
}

download_file() {
  local url=$1
  local target=$2

  if is_empty "${url}" || is_empty "${target}"; then
    print_error_and_exit "download_file() expects an URL and a target path."
  fi

  if program_exists "curl"; then
    curl --fail --silent --show-error --location \
      --retry 3 --retry-delay 5 --max-time 30 \
      -o "${target}" "${url}" || print_error_and_exit \
        "curl failed to download ${url} to '${target}'."
  elif program_exists "wget"; then
    wget -t 3 --retry-connrefused --waitretry=5 --read-timeout=20 --timeout=15 \
      --no-dns-cache -q -O "${target}" "${url}" || print_error_and_exit \
        "wget failed to download ${url} to '${target}'."
  else
    print_error_and_exit "Please install curl or wget."
  fi
}

extract_file() {
  local path=$1
  local target=$2

  if [[ "${path}" == *".tar.gz" ]]; then
    tar xzf "${path}" -C "${target}"
  elif [[ "${path}" == *".zip" ]]; then
    unzip "${path}" -d "${target}"
  elif [[ "${path}" == *".dmg" ]]; then
    readonly VOLUME=$(hdiutil attach "${path}" | tail -1 | awk '{print $3}')
    cp -R "${VOLUME}/"* "${target}/"
    diskutil unmount "${VOLUME}"
  fi
}

resolve_path() {
  local path=$1

  if is_cygwin_build || is_mingw64_build; then
    echo $(cygpath -w "${path}")
  else
    echo "${path}"
  fi
}

return_vars() {
  (IFS="|"; echo "$*")
}

set_vars() {
  local variables=(${@:1:(($# - 1))})
  local values="${!#}"

  IFS="|" read -r "${variables[@]}" <<< "${values}"
}

to_lowercase() {
  echo $1 | tr "[:upper:]" "[:lower:]"
}

git_log() {
  local format_value=$1
  local output
  output=$(git --no-pager log -1 --pretty=format:"${format_value}")
  echo "${output//\"/\\\"}" # Escape double quotes
}


export_coveralls_data() {
  local branch_name="unknown"
  local flag_name="${COVERALLS_FLAG_NAME:-}"
  local optional_values=""
  local parallel="${COVERALLS_PARALLEL:-}"
  local repo_token=""
  local service_job_id=""
  local service_job_number=""
  local service_number=""
  local service_name=""
  local service_pull_request=""
  local url="unknown"

  if ! grep -q "#coverage" "${config_ston}"; then
    return 0 # Coverage data not needed
  fi

  # Handle info in same way as Coveralls' node module (see https://git.io/JJiOz)

  if is_not_empty "${COVERALLS_REPO_TOKEN:-}"; then
    print_info 'Using $COVERALLS_REPO_TOKEN instead of CI service info...'
    branch_name="$(git rev-parse --abbrev-ref HEAD)"
    repo_token="${COVERALLS_REPO_TOKEN:-}"
  elif is_travis_build; then
    branch_name="${TRAVIS_BRANCH}"
    service_job_id="${TRAVIS_JOB_ID}"
    service_name="travis-ci"
    service_pull_request="${TRAVIS_PULL_REQUEST:-}"
    url="https://github.com/${TRAVIS_REPO_SLUG}.git"
  elif is_appveyor_build; then
    branch_name="${APPVEYOR_REPO_BRANCH}"
    service_job_id="${APPVEYOR_BUILD_ID}"
    service_job_number="${APPVEYOR_BUILD_NUMBER}"
    service_name="appveyor"
    service_pull_request="${APPVEYOR_PULL_REQUEST_NUMBER:-}"
    url="https://github.com/${APPVEYOR_REPO_NAME}.git"
  elif is_gitlabci_build; then
    branch_name="${CI_COMMIT_REF_NAME}"
    service_job_id="${CI_BUILD_ID}"
    service_job_number="${CI_BUILD_NAME}"
    service_name="gitlab-ci"
    service_pull_request="${CI_MERGE_REQUEST_IID:-}"
    url="${CI_PROJECT_URL}"
  elif is_github_build; then
    if [[ "${GITHUB_REF}" == "refs/heads/"* ]]; then
      branch_name="${GITHUB_REF##*/}" # e.g. in push events.
    else
      branch_name="${GITHUB_HEAD_REF}" # e.g. in pull_request events.
    fi
    if is_empty "${GITHUB_TOKEN:-}"; then
      print_error_and_exit 'Running on GitHub Actions but $GITHUB_TOKEN is not set. Add `env: GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}` to your step config.'
    fi
    repo_token="${GITHUB_TOKEN}"
    service_name="github"
    service_number="${GITHUB_RUN_ID}"
    if [[ "${GITHUB_REF}" == "refs/pull/"* ]]; then
      service_pull_request="${GITHUB_REF#refs/pulls/}"
    fi
    url="https://github.com/${GITHUB_REPOSITORY}.git"
  fi

  for key in ${COVERALLS_OPTIONAL_KEYS}; do
    if is_not_empty "${!key:-}"; then
      optional_values="${optional_values}\"${key}\": \"${!key}\", "
    fi
  done

  cat >"${SMALLTALK_CI_BUILD}/coveralls_build_data.json" <<EOL
{
  ${optional_values}
  "git": {
    "branch": "${branch_name}",
    "head": {
      "author_email": "$(git_log "%ae")",
      "author_name": "$(git_log "%aN")",
      "committer_email": "$(git_log "%ce")",
      "committer_name": "$(git_log "%cN")",
      "id": "$(git_log "%H")",
      "message": "$(git_log "%s")"
    },
    "remotes": [
      {
        "url": "${url}",
        "name": "origin"
      }
    ]
  }
}
EOL
}

upload_coveralls_results() {
  local http_status=0
  local coverage_results="${SMALLTALK_CI_BUILD}/coveralls_results.json"
  local coveralls_response="${SMALLTALK_CI_BUILD}/coveralls_response"

  if is_file "${coverage_results}"; then
    print_info "Uploading coverage results to Coveralls..."
    http_status=$(curl -s -F json_file="@${coverage_results}" "${COVERALLS_API}" -o "${coveralls_response}" -w "%{http_code}")
    if [[ "${http_status}" != "200" ]]; then
      print_error "Failed to upload coverage results (HTTP status code #${http_status}):"
    fi
    cat "${coveralls_response}"
  fi
}

report_build_metrics() {
  local build_status=$1
  local env_name
  local project_slug
  local api_url
  local status_code
  local duration=$(($(timer_nanoseconds)-$smalltalk_ci_start_time))
  duration=$(echo "${duration}" | awk '{printf "%.3f\n", $1/1000000000}')

  if [[ "${config_tracking}" != "true" ]]; then
    return 0
  fi

  if is_travis_build; then
    env_name="TravisCI"
  elif is_appveyor_build; then
    env_name="AppVeyor"
  elif is_github_build; then
    env_name="GitHub"
  else
    return 0 # Only report build metrics when running on known CI service
  fi

  project_slug="${TRAVIS_REPO_SLUG:-${APPVEYOR_REPO_NAME:-${GITHUB_REPOSITORY:-}}}"
  api_url="${GITHUB_API}/repos/${project_slug}"
  status_code=$(curl -w %{http_code} -s -o /dev/null "${api_url}")
  if [[ "${status_code}" != "200" ]]; then
    return 0 # Not a public repository
  fi

  curl -s --header "X-BUILD-DURATION: ${duration}" \
          --header "X-BUILD-ENV: ${env_name}" \
          --header "X-BUILD-SMALLTALK: ${config_smalltalk}" \
          --header "X-BUILD-STATUS: ${build_status}" \
            "https://smalltalkci.fniephaus.com/api/" > /dev/null || true
}

################################################################################
# Deploy build artifacts to bintray if configured.
################################################################################
deploy() {
  local build_status_value=$1
  local target
  local version="${TRAVIS_BUILD_NUMBER}"
  local project_name="$(basename ${TRAVIS_BUILD_DIR})"
  local name="${project_name}-${TRAVIS_JOB_NUMBER}-${config_smalltalk}"
  local image_name="${SMALLTALK_CI_BUILD}/${name}.image"
  local changes_name="${SMALLTALK_CI_BUILD}/${name}.changes"
  local publish=false

  if is_empty "${BINTRAY_CREDENTIALS:-}" || \
      [[ "${TRAVIS_PULL_REQUEST}" != "false" ]]; then
    return
  fi

  if ! signals_error "${build_status_value}"; then
    if is_empty "${BINTRAY_RELEASE:-}" || \
        [[ "${TRAVIS_BRANCH}" != "master" ]]; then
      return
    fi
    target="${BINTRAY_API}/${BINTRAY_RELEASE}/${version}"
    publish=true
  else
    if is_empty "${BINTRAY_FAIL:-}"; then
      return
    fi
    target="${BINTRAY_API}/${BINTRAY_FAIL}/${version}"
  fi

  fold_start deploy "Deploying to bintray.com..."
    pushd "${SMALLTALK_CI_BUILD}" > /dev/null

    print_info "Compressing and uploading image and changes files..."
    mv "${SMALLTALK_CI_IMAGE}" "${name}.image"
    mv "${SMALLTALK_CI_CHANGES}" "${name}.changes"
    tar czf "${name}.tar.gz" "${name}.image" "${name}.changes"
    curl -s -u "$BINTRAY_CREDENTIALS" -T "${name}.tar.gz" \
        "${target}/${name}.tar.gz" > /dev/null
    zip -q "${name}.zip" "${name}.image" "${name}.changes"
    curl -s -u "$BINTRAY_CREDENTIALS" -T "${name}.zip" \
        "${target}/${name}.zip" > /dev/null

    if signals_error "${build_status_value}"; then
      # Check for xml files and upload them
      if ls *.xml 1> /dev/null 2>&1; then
        print_info "Compressing and uploading debugging files..."
        mv "${TRAVIS_BUILD_DIR}/"*.fuel "${SMALLTALK_CI_BUILD}/" || true
        find . -name "*.xml" -o -name "*.fuel" | tar czf "debug.tar.gz" -T -
        curl -s -u "$BINTRAY_CREDENTIALS" \
            -T "debug.tar.gz" "${target}/" > /dev/null
      fi
    fi

    if "${publish}"; then
      print_info "Publishing ${version}..."
      curl -s -X POST -u "$BINTRAY_CREDENTIALS" "${target}/publish" > /dev/null
    fi

    popd > /dev/null
  fold_end deploy
}


################################################################################
# Travis-related helper functions (based on https://git.io/vzcTj).
################################################################################

timer_nanoseconds() {
  local cmd="date"
  local format="+%s%N"
  local os=$(uname)

  if hash gdate > /dev/null 2>&1; then
    cmd="gdate" # use gdate if available
  elif [[ "${os}" = Darwin ]]; then
    format="+%s000000000" # fallback to second precision on darwin (does not support %N)
  fi

  $cmd -u $format
}

travis_wait() {
  local timeout="${SMALLTALK_CI_TIMEOUT:-}"

  local cmd="$@"

  if ! is_int "${timeout}"; then
    $cmd
    return $?
  fi

  $cmd &
  local cmd_pid=$!

  travis_jigger $! $timeout $cmd &
  local jigger_pid=$!
  local result

  {
    wait $cmd_pid 2>/dev/null
    result=$?
    ps -p$jigger_pid &>/dev/null && kill $jigger_pid
  }

  if [ $result -ne 0 ]; then
    print_error_and_exit "The command $cmd exited with $result."
  fi

  return $result
}

travis_jigger() {
  # helper method for travis_wait()
  local cmd_pid=$1
  shift
  local timeout=$1 # in minutes
  shift
  local count=0

  while [ $count -lt $timeout ]; do
    count=$(($count + 1))
    echo -e "Still running ($count of $timeout): $@"
    sleep 60
  done

  if is_colorful; then
    echo -e "\n${ANSI_BOLD}${ANSI_RED}Timeout (${timeout} minutes) reached. Terminating \"$@\"${ANSI_RESET}\n"
  else
    echo -e "\nTimeout (${timeout} minutes) reached. Terminating \"$@\"\n"
  fi
  kill -9 $cmd_pid
}

fold_start() {
  local identifier=$1
  local title=$2
  local prefix="${SMALLTALK_CI_TRAVIS_FOLD_PREFIX:-}"

  timer_start_time=$(timer_nanoseconds)
  travis_timer_id=$(printf %08x $(( RANDOM * RANDOM )))
  if is_travis_build; then
    echo -en "travis_fold:start:${prefix}${identifier}\r${ANSI_CLEAR}"
    echo -en "travis_time:start:$travis_timer_id\r${ANSI_CLEAR}"
  fi
  if is_colorful; then
    echo -e "${ANSI_BOLD}${ANSI_BLUE}${title}${ANSI_RESET}"
  else
    echo -e "${title}"
  fi
}

fold_end() {
  local identifier=$1
  local prefix="${SMALLTALK_CI_TRAVIS_FOLD_PREFIX:-}"
  local timer_end_time=$(timer_nanoseconds)
  local duration=$(($timer_end_time-$timer_start_time))

  if is_travis_build; then
    echo -en "travis_time:end:$travis_timer_id:start=$timer_start_time,finish=$timer_end_time,duration=$duration\r${ANSI_CLEAR}"
    echo -en "travis_fold:end:${prefix}${identifier}\r${ANSI_CLEAR}"
  else
    duration=$(echo "${duration}" | awk '{printf "%.3f\n", $1/1000000000}')
    if is_colorful; then
      printf "${ANSI_RESET}${ANSI_BLUE} > Time to run: %ss${ANSI_RESET}\n" "${duration}"
    else
      printf " > Time to run: %ss\n" "${duration}"
    fi
  fi
}
