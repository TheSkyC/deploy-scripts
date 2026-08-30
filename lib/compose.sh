#!/usr/bin/env bash

# Shared Docker Compose support layer: resolve the compose command binary,
# validate the runtime, and run compose operations with strict path checks
# on the project file and working directory. Handles both `docker compose`
# (plugin) and the legacy `docker-compose` standalone binary.
#
# Never prints table/color output itself; callers format results.

# Print the compose command as a single string ("docker compose" or
# "docker-compose"), or empty when neither is usable.
compose_command() {
  if docker compose version >/dev/null 2>&1; then
    printf '%s' "docker compose"
  elif command -v docker-compose >/dev/null 2>&1; then
    printf '%s' "docker-compose"
  fi
  # An absent backend is a valid probe result. Callers that require compose
  # use compose_require_runtime(), while status-style callers can treat an
  # empty command as unavailable without triggering errexit.
  return 0
}

# Require a usable compose runtime; errors out when neither backend exists.
compose_require_runtime() {
  command -v docker >/dev/null 2>&1 \
    || error "$(t compose.error.docker_missing)"
  if ! docker compose version >/dev/null 2>&1 && ! command -v docker-compose >/dev/null 2>&1; then
    error "$(t compose.error.runtime_missing)"
  fi
}

# Validate the compose project file and working directory before any run:
# both must be safe, absolute paths, and the project file must exist.
# Returns nonzero (never exits) so probes can treat validation as a check;
# compose_run escalates the failure with a localized error.
compose_validate_project() {
  local work_dir="$1" project_file="$2" work_name project_name
  work_name="$(basename "$work_dir")"
  project_name="$(basename "$project_file")"
  is_safe_path "$work_dir" || return 1
  is_safe_path "$project_file" || return 1
  [[ -d "$work_dir" && -f "$project_file" ]] || return 1
  # Compose may resolve relative paths from --project-directory; keep the
  # project file inside that validated directory rather than accepting an
  # unrelated existing system file such as /etc/passwd.
  while [[ "$work_dir" != "/" && "$work_dir" == */ ]]; do
    work_dir="${work_dir%/}"
  done
  [[ "$project_file" == "$work_dir/"* ]] || return 1
}

# Echo an argv-ready compose invocation prefix given the working directory
# and project file. Example: "docker compose --project-directory /opt/app -f /opt/app/compose.yml"
compose_base_args() {
  local work_dir="$1" project_file="$2"
  printf -- '--project-directory %q -f %q' "$work_dir" "$project_file"
}

# Run one compose operation against the project, streaming output to stderr.
# Arguments: work dir, project file, then the compose subcommand + args.
compose_run() {
  local work_dir="$1" project_file="$2"
  shift 2
  compose_require_runtime
  compose_validate_project "$work_dir" "$project_file" \
    || error "$(t compose.error.project_missing "$project_file")"
  local compose_cmd
  compose_cmd="$(compose_command)"
  [[ -n "$compose_cmd" ]] || error "$(t compose.error.runtime_missing)"
  local -a base_args
  read -r -a base_args <<< "$(compose_base_args "$work_dir" "$project_file")"
  # shellcheck disable=SC2086
  $compose_cmd "${base_args[@]}" "$@" >&2
}

# Run one compose operation capturing only its exit status, with output
# suppressed unless the operation fails. Used by status-style probes.
compose_try() {
  local work_dir="$1" project_file="$2"
  shift 2
  local compose_cmd out
  compose_cmd="$(compose_command)"
  [[ -n "$compose_cmd" ]] || return 1
  compose_validate_project "$work_dir" "$project_file" || return 1
  local -a base_args
  read -r -a base_args <<< "$(compose_base_args "$work_dir" "$project_file")"
  # shellcheck disable=SC2086
  out="$($compose_cmd "${base_args[@]}" "$@" 2>&1)" || {
    printf '%s\n' "$out" >&2
    return 1
  }
  return 0
}

# Lifecycle helpers. Each validates and runs through compose_run, so output
# streams to stderr and no formatting decisions leak into the caller.
compose_up() {
  compose_run "$1" "$2" up -d --build
}

compose_down() {
  compose_run "$1" "$2" down
}

compose_ps() {
  compose_run "$1" "$2" ps
}

# Health check: `compose ps --format json` lists one JSON line per service;
# every service must report running/healthy. Accepts either docker compose
# or docker-compose output shape; returns nonzero when any service is not
# running, without printing anything (the caller renders the verdict).
compose_health() {
  local work_dir="$1" project_file="$2"
  local compose_cmd out
  compose_cmd="$(compose_command)"
  [[ -n "$compose_cmd" ]] || return 1
  compose_validate_project "$work_dir" "$project_file" || return 1
  local -a base_args
  read -r -a base_args <<< "$(compose_base_args "$work_dir" "$project_file")"
  # shellcheck disable=SC2086
  out="$($compose_cmd "${base_args[@]}" ps --format json 2>/dev/null)" || return 1
  # Case-insensitive state scan: running/healthy pass; exited, dead, or
  # restarting services fail the check. docker compose uses lowercase
  # values ("running"), docker-compose uses title case ("Running").
  printf '%s' "$out" | grep -qi '"running"\|"Running"\|"healthy"\|"Healthy"' \
    && ! printf '%s' "$out" | grep -qi '"exited"\|"Exited"\|"dead"\|"Dead"\|"restarting"\|"Restarting"' \
    || return 1
}
