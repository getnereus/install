#!/bin/sh
# Installs the nereus CLI on Linux (#1782); the help below documents its environment.

show_usage() {
  cat <<'USAGE'
Installs the nereus CLI on Linux (x86_64 and aarch64), as a uv tool:

  curl -fsSL https://getnereus.github.io/install/install.sh | sh

It reads the release manifest (latest.json: the version, the wheel's URL and its sha256), downloads the wheel, checks
its sha256, installs uv when it is missing (Astral's installer, into ~/.local/bin), then runs
`uv tool install --force --python <python> <wheel>`. Running it again reinstalls the same or a newer version.

Environment:
  NEREUS_VERSION                a version to install instead of the latest (0.1.23 or v0.1.23)
  NEREUS_INSTALL_MANIFEST_URL   the manifest to read (default: the latest release's latest.json); wins over
                                NEREUS_VERSION
  NEREUS_PYTHON                 the Python uv runs the CLI with (default 3.12; uv downloads it when missing)
  UV_INSTALL_DIR                where uv is installed when missing (Astral's installer, default ~/.local/bin)
  UV_NO_MODIFY_PATH             set to 1 so Astral's installer leaves the shell profiles alone

Example, a pinned version:
  curl -fsSL https://getnereus.github.io/install/install.sh | NEREUS_VERSION=0.1.23 sh

Help: curl -fsSL https://getnereus.github.io/install/install.sh | sh -s -- --help
USAGE
}

set -eu

RELEASES="https://github.com/getnereus/install/releases"
UV_INSTALLER="https://astral.sh/uv/install.sh"

say() {
  printf '%s\n' "${1?}"
}

fail() {
  printf '✗ %s\n' "${1?}" >&2
  exit 1
}

check_platform() {
  os="$(uname -s)"
  arch="$(uname -m)"
  case "${os}" in
    Linux) ;;
    Darwin) fail "macOS is not supported by this installer yet: only Linux (x86_64, aarch64)" ;;
    *) fail "${os} is not supported by this installer yet: only Linux (x86_64, aarch64)" ;;
  esac
  case "${arch}" in
    x86_64 | amd64 | aarch64 | arm64) ;;
    *) fail "the ${arch} architecture is not supported yet: only x86_64 and aarch64" ;;
  esac
}

# download <url> <file>: curl, else wget.
download() {
  if command -v curl > /dev/null 2>&1; then
    curl --fail --silent --show-error --location --output "${2?}" "${1?}"
  elif command -v wget > /dev/null 2>&1; then
    wget --quiet --output-document "${2?}" "${1?}"
  else
    fail "neither curl nor wget is installed: install one of them and run this again"
  fi
}

sha256_of() {
  if command -v sha256sum > /dev/null 2>&1; then
    sha256sum "${1?}" | cut -d ' ' -f 1
  elif command -v shasum > /dev/null 2>&1; then
    shasum -a 256 "${1?}" | cut -d ' ' -f 1
  else
    fail "neither sha256sum nor shasum is installed: the wheel's sha256 cannot be checked"
  fi
}

# field <file> <key>: a string field of the flat JSON manifest.
field() {
  tr -d '\n\r' < "${1?}" | sed -n "s/.*\"${2?}\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p"
}

manifest_url() {
  if [ -n "${NEREUS_INSTALL_MANIFEST_URL:-}" ]; then
    printf '%s\n' "${NEREUS_INSTALL_MANIFEST_URL}"
  elif [ -n "${NEREUS_VERSION:-}" ]; then
    pinned="${NEREUS_VERSION#v}"
    case "${pinned}" in
      *[!0-9.]* | .* | *. | *..* | "") fail "NEREUS_VERSION is not a version like 0.1.23: ${NEREUS_VERSION}" ;;
    esac
    printf '%s\n' "${RELEASES}/download/v${pinned}/latest.json"
  else
    printf '%s\n' "${RELEASES}/latest/download/latest.json"
  fi
}

# find_uv: the uv on PATH, else the one Astral's installer puts in place; empty when there is none.
find_uv() {
  if command -v uv > /dev/null 2>&1; then
    command -v uv
    return
  fi
  for candidate in "${UV_INSTALL_DIR:-}" "${XDG_BIN_HOME:-}" "${HOME}/.local/bin" "${HOME}/.cargo/bin"; do
    if [ -n "${candidate}" ] && [ -x "${candidate}/uv" ]; then
      printf '%s\n' "${candidate}/uv"
      return
    fi
  done
}

ensure_uv() {
  uv="$(find_uv)"
  if [ -n "${uv}" ]; then
    return
  fi
  say "installing uv (${UV_INSTALLER})"
  download "${UV_INSTALLER}" "${work}/uv-install.sh"
  sh "${work}/uv-install.sh" --quiet
  uv="$(find_uv)"
  [ -n "${uv}" ] || fail "uv was installed but is not found: put its folder on PATH and run this again"
}

main() {
  case "${1:-}" in
    --help | -h)
      show_usage
      exit 0
      ;;
    "") ;;
    *) fail "unknown argument: ${1} (see --help)" ;;
  esac

  check_platform
  work="$(mktemp -d)"
  trap 'rm -rf "${work}"' EXIT

  manifest="$(manifest_url)"
  download "${manifest}" "${work}/latest.json" || fail "could not read the manifest: ${manifest}"
  version="$(field "${work}/latest.json" version)"
  wheel_url="$(field "${work}/latest.json" wheel)"
  sha256="$(field "${work}/latest.json" sha256)"
  if [ -z "${version}" ] || [ -z "${wheel_url}" ] || [ -z "${sha256}" ]; then
    fail "the manifest has no version, wheel or sha256: ${manifest}"
  fi

  wheel_name="${wheel_url##*/}"
  case "${wheel_name}" in
    nereus-*-py3-none-any.whl) ;;
    *) fail "the manifest's wheel is not a nereus wheel: ${wheel_url}" ;;
  esac

  say "nereus ${version}: downloading ${wheel_url}"
  download "${wheel_url}" "${work}/${wheel_name}" || fail "could not download the wheel: ${wheel_url}"
  actual="$(sha256_of "${work}/${wheel_name}")"
  [ "${actual}" = "${sha256}" ] \
    || fail "the wheel's sha256 is ${actual}, the manifest says ${sha256}: nothing was installed"

  ensure_uv
  "${uv}" tool install --quiet --force --python "${NEREUS_PYTHON:-3.12}" "${work}/${wheel_name}"

  bin_dir="$("${uv}" tool dir --bin)"
  say "✓ $(NEREUS_AUTO_UPGRADE=off "${bin_dir}/nereus" --version) installed in ${bin_dir} (also as nrs)"
  case ":${PATH}:" in
    *":${bin_dir}:"*) ;;
    *)
      say "  ${bin_dir} is not on your PATH: add it to your shell's profile, then open a new terminal:"
      say "    export PATH=\"${bin_dir}:\${PATH}\""
      ;;
  esac
  say "  nereus upgrades itself in the background; turn it off with NEREUS_AUTO_UPGRADE=off or nereus config set auto_upgrade off"
}

main "$@"
