#!/usr/bin/env bash
# Copyright 2025-2026 Bootstrap Academy
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

set -uo pipefail

usage() {
  cat <<'USAGE'
Usage: run-gitlab-opencode.sh --repo <gitlab-https-url> --token <token> [OPTIONS]

Clones a GitLab repository and runs RepoLens with opencode.

Required:
  --repo <url>        HTTPS clone URL of the GitLab repository.
  --token <token>    GitLab personal/project/group access token.

Options:
  --project <path>   Checkout directory inside the container.
                     Default: $REPOLENS_PROJECT_DIR or ~/news-server
  --agent <agent>    RepoLens agent. Default: $REPOLENS_AGENT or opencode
  --mode <mode>      Optional RepoLens mode. Uses RepoLens default if omitted.
  --domain <domain>  Optional RepoLens domain. Default: $REPOLENS_DOMAIN or security
  --branch <name>    Optional branch, tag, or ref to checkout.
  --local            Pass --local to RepoLens instead of filing GitLab issues.
  -h, --help         Show this help text.

Environment alternatives:
  GITLAB_REPO        Same as --repo
  GITLAB_TOKEN       Same as --token

Any arguments after "--" are forwarded to repolens.sh.
USAGE
}

die() {
  echo "ERROR: $*" >&2
  exit 1
}

repo_url="${GITLAB_REPO:-}"
token="${GITLAB_TOKEN:-}"
project_dir="${REPOLENS_PROJECT_DIR:-$HOME/news-server}"
agent="${REPOLENS_AGENT:-opencode}"
mode="${REPOLENS_MODE:-}"
domain="${REPOLENS_DOMAIN:-security}"
mode_or_domain_set=0
branch=""
local_mode=0
extra_args=()

if [[ -n "${REPOLENS_MODE:-}" && -n "${REPOLENS_DOMAIN:-}" ]]; then
  die "Use either REPOLENS_MODE or REPOLENS_DOMAIN, not both"
fi

while (($#)); do
  case "$1" in
    --repo)
      [[ $# -ge 2 ]] || die "--repo requires a value"
      repo_url="$2"
      shift 2
      ;;
    --token)
      [[ $# -ge 2 ]] || die "--token requires a value"
      token="$2"
      shift 2
      ;;
    --project|--project-dir)
      [[ $# -ge 2 ]] || die "$1 requires a value"
      project_dir="$2"
      shift 2
      ;;
    --agent)
      [[ $# -ge 2 ]] || die "--agent requires a value"
      agent="$2"
      shift 2
      ;;
    --mode)
      [[ $# -ge 2 ]] || die "--mode requires a value"
      [[ -z "${REPOLENS_DOMAIN:-}" ]] || die "Use either --mode or REPOLENS_DOMAIN, not both"
      (( mode_or_domain_set == 0 )) || die "Use either --mode or --domain, not both"
      mode="$2"
      mode_or_domain_set=1
      shift 2
      ;;
    --domain)
      [[ $# -ge 2 ]] || die "--domain requires a value"
      [[ -z "${REPOLENS_MODE:-}" ]] || die "Use either --domain or REPOLENS_MODE, not both"
      (( mode_or_domain_set == 0 )) || die "Use either --mode or --domain, not both"
      domain="$2"
      mode_or_domain_set=1
      shift 2
      ;;
    --branch|--ref)
      [[ $# -ge 2 ]] || die "$1 requires a value"
      branch="$2"
      shift 2
      ;;
    --local)
      local_mode=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      extra_args+=("$@")
      break
      ;;
    *)
      die "Unknown argument: $1"
      ;;
  esac
done

[[ -n "$repo_url" ]] || die "Missing --repo or GITLAB_REPO"
[[ -n "$token" ]] || die "Missing --token or GITLAB_TOKEN"
[[ "$repo_url" =~ ^https:// ]] || die "Only HTTPS GitLab clone URLs are supported when cloning with a token"

command -v git >/dev/null 2>&1 || die "git is not installed"
command -v glab >/dev/null 2>&1 || die "glab is not installed"
command -v opencode >/dev/null 2>&1 || die "opencode is not installed"
command -v jq >/dev/null 2>&1 || die "jq is not installed"

host="$(printf '%s\n' "$repo_url" | sed -E 's#^https://([^/]+)/.*#\1#')"
[[ -n "$host" && "$host" != "$repo_url" ]] || die "Could not parse GitLab host from repo URL"

export GITLAB_TOKEN="$token"
export GIT_TERMINAL_PROMPT=0

# Authenticate glab for RepoLens forge operations. GITLAB_TOKEN is kept exported
# because glab also honors it directly in non-interactive environments.
glab auth login --hostname "$host" --token "$token" >/dev/null 2>&1 || true

mkdir -p "$(dirname "$project_dir")"
rm -rf -- "$project_dir"

askpass_file="$(mktemp)"
cleanup() {
  rm -f -- "$askpass_file"
}
trap cleanup EXIT

cat > "$askpass_file" <<'ASKPASS'
#!/usr/bin/env bash
case "$1" in
  *Username*) printf '%s\n' "oauth2" ;;
  *Password*) printf '%s\n' "${GITLAB_TOKEN:-}" ;;
  *) printf '\n' ;;
esac
ASKPASS
chmod 700 "$askpass_file"
export GIT_ASKPASS="$askpass_file"

clone_args=(clone)
if [[ -n "$branch" ]]; then
  clone_args+=(--branch "$branch")
fi
clone_args+=("$repo_url" "$project_dir")

git "${clone_args[@]}" || die "git clone failed"
git -C "$project_dir" remote set-url origin "$repo_url" || true

repolens_args=(-y --project "$project_dir" --agent "$agent")
if [[ -n "$mode" ]]; then
  repolens_args+=(--mode "$mode")
else
  repolens_args+=(--domain "$domain")
fi
if ((local_mode)); then
  repolens_args+=(--local)
fi
repolens_args+=("${extra_args[@]}")

exec /opt/repolens/repolens.sh "${repolens_args[@]}"
