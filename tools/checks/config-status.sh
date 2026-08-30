# shellcheck shell=bash
# shellcheck source=../verify.sh
# Config handling and status/summary guardrails: centralized atomic config writes, sanitization, and bounded status/port checks.

check_service_status_label() {
  local tmp_dir
  tmp_dir="$(mktemp -d)"
  cat > "${tmp_dir}/systemctl" <<'STUB'
#!/usr/bin/env bash
case "$1" in
  is-active)
    [[ "${3:-}" == "active-service" ]] && exit 0
    exit 3
    ;;
  list-unit-files)
    for arg in "$@"; do
      if [[ "$arg" == "inactive-service.service" ]]; then
        echo "inactive-service.service disabled"
        exit 0
      fi
      if [[ "$arg" == "missing-service.service" ]]; then
        exit 0
      fi
    done
    exit 0
    ;;
esac
exit 1
STUB
  chmod +x "${tmp_dir}/systemctl"

  PATH="${tmp_dir}:$PATH" DEPLOY_LANG=en "$BASH_BIN" -c '
    set -euo pipefail
    source lib/core.sh
    [[ "$(service_status_label active-service)" == "active" ]]
    [[ "$(service_status_label inactive-service)" == "inactive" ]]
    [[ "$(service_status_label missing-service)" == "unknown" ]]
  '
  rm -rf "$tmp_dir"
}

check_app_http_status_code_helper() {
  local tmp_dir output
  tmp_dir="$(mktemp -d)"
  cat > "${tmp_dir}/curl" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$HTTP_PROBE_ARGS_FILE"
printf '204'
STUB
  chmod +x "${tmp_dir}/curl"

  output="$(PATH="${tmp_dir}:$PATH" HTTP_PROBE_ARGS_FILE="${tmp_dir}/args" "$BASH_BIN" -c '
    set -euo pipefail
    source lib/core.sh
    app_http_status_code "http://127.0.0.1:8080/health" 7 -k -H "Host: example.test"
  ')" || {
    rm -rf "$tmp_dir"
    return 1
  }
  [[ "$output" == "204" ]] || {
    echo "HTTP probe helper did not return the curl status code: ${output}" >&2
    rm -rf "$tmp_dir"
    return 1
  }
  grep -Fx -- '--max-time' "${tmp_dir}/args" >/dev/null     && grep -Fx -- '7' "${tmp_dir}/args" >/dev/null     && grep -Fx -- '-k' "${tmp_dir}/args" >/dev/null     && grep -Fx -- '-H' "${tmp_dir}/args" >/dev/null     && grep -Fx -- 'Host: example.test' "${tmp_dir}/args" >/dev/null     && grep -Fx -- 'http://127.0.0.1:8080/health' "${tmp_dir}/args" >/dev/null || {
      echo "HTTP probe helper did not preserve timeout, curl options, and URL arguments." >&2
      rm -rf "$tmp_dir"
      return 1
    }

  output="$("$BASH_BIN" -c '
    set -euo pipefail
    source lib/core.sh
    curl() { return 1; }
    app_http_status_code "http://127.0.0.1:8080/health"
  ')" || {
    rm -rf "$tmp_dir"
    return 1
  }
  [[ "$output" == "000" ]] || {
    echo "HTTP probe helper must return 000 when curl fails: ${output}" >&2
    rm -rf "$tmp_dir"
    return 1
  }
  rm -rf "$tmp_dir"
}

check_custom_app_http_health_probes_use_shared_helper() {
  local file
  for file in lib/binary_app.sh impl/install_sub2api.sh impl/install_vaultwarden.sh impl/install_cyberstrikeai.sh; do
    grep -Fq 'app_http_status_code' "$file" || {
      echo "${file} must use the shared HTTP status probe helper." >&2
      return 1
    }
  done
}

check_config_writes_are_centralized() {
  if grep -R -nE '(>|>>)[[:space:]]*"?\$\{?CONF_FILE\}?"?|tee[[:space:]]+"?\$\{?CONF_FILE\}?"?' impl dist 2>/dev/null; then
    echo "Deployment config (CONF_FILE) must be written only through app_save_config." >&2
    return 1
  fi
  if grep -R -nE '(>|>>)[[:space:]]*/etc/[A-Za-z0-9_-]+-deploy\.conf' impl dist 2>/dev/null; then
    echo "Deployment config paths must come from app_conf_file, not be hardcoded." >&2
    return 1
  fi
  awk '
      /^app_save_config$/ { saw_save=1 }
      END {
        if (!saw_save) {
          print "Every app must persist deployment config through app_save_config." > "/dev/stderr"
          exit 1
        }
      }
    ' impl/install_hugo_blog.sh impl/install_cpa_stack.sh impl/install_cyberstrikeai.sh \
      impl/install_sub2api.sh impl/install_tickflow.sh impl/install_vaultwarden.sh
  awk '
      /bapp_install\(\)/ { in_install=1; saw_save=0; next }
      in_install && /app_save_config/ { saw_save=1 }
      in_install && /^}/ {
        if (!saw_save) {
          printf "%s shared install lifecycle must persist config through app_save_config\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_install=0
      }
    ' lib/binary_app.sh
}

check_config_crlf_handling() {
  local tmp_dir conf
  tmp_dir="$(mktemp -d)"
  conf="${tmp_dir}/deploy.conf"
  printf ' FOO = "bar"\r\n\tBAZ\t= qux \r\nQUOTED = " spaced value "\r\n' > "$conf"

  cat > "${tmp_dir}/stat" <<'STUB'
#!/usr/bin/env bash
case "${2:-}" in
  %U) echo root ;;
  %a) echo 600 ;;
  *) /usr/bin/stat "$@" ;;
esac
STUB
  chmod +x "${tmp_dir}/stat"

  PATH="${tmp_dir}:$PATH" "$BASH_BIN" -c '
    set -euo pipefail
    source lib/core.sh
    FOO=""
    BAZ=""
    QUOTED=""
    load_config_file "$1" FOO BAZ QUOTED
    [[ "$FOO" == "bar" ]] || { printf "FOO contained unexpected bytes: " >&2; printf "%s" "$FOO" | od -An -tx1 >&2; exit 1; }
    [[ "$BAZ" == "qux" ]] || { printf "BAZ contained unexpected bytes: " >&2; printf "%s" "$BAZ" | od -An -tx1 >&2; exit 1; }
    [[ "$QUOTED" == " spaced value " ]] || { printf "QUOTED contained unexpected bytes: " >&2; printf "%s" "$QUOTED" | od -An -tx1 >&2; exit 1; }
    sanitized="$(sanitize_conf_val $'"'"'one\ntwo'"'"')"
    [[ "$sanitized" == "one" ]] || { printf "sanitize_conf_val returned unexpected bytes: " >&2; printf "%s" "$sanitized" | od -An -tx1 >&2; exit 1; }
  ' _ "$conf"

  rm -rf "$tmp_dir"
}

check_config_write_failure_cleanup() {
  local tmp_dir conf
  tmp_dir="$(mktemp -d)"
  conf="${tmp_dir}/deploy.conf"

  cat > "${tmp_dir}/chmod" <<'STUB'
#!/usr/bin/env bash
exit 1
STUB
  chmod +x "${tmp_dir}/chmod"

  "$BASH_BIN" -c '
    set -euo pipefail
    source lib/core.sh
    FOO="bar"
    PATH="$1:$PATH"
    set +e
    write_config_file "$2" FOO
    status=$?
    set -e
    [[ "$status" -ne 0 ]] || { echo "write_config_file unexpectedly succeeded" >&2; exit 1; }
    if find "$(dirname "$2")" -maxdepth 1 -name "$(basename "$2").tmp.*" -type f | grep -q .; then
      echo "write_config_file left a temporary config file behind" >&2
      find "$(dirname "$2")" -maxdepth 1 -name "$(basename "$2").tmp.*" -type f >&2
      exit 1
    fi
  ' _ "$tmp_dir" "$conf"

  rm -f "${tmp_dir}/chmod"
  cat > "${tmp_dir}/chown" <<'STUB'
#!/usr/bin/env bash
exit 1
STUB
  chmod +x "${tmp_dir}/chown"

  "$BASH_BIN" -c '
    set -euo pipefail
    source lib/core.sh
    FOO="bar"
    PATH="$1:$PATH"
    set +e
    write_config_file "$2" FOO
    status=$?
    set -e
    [[ "$status" -ne 0 ]] || { echo "write_config_file unexpectedly ignored chown failure" >&2; exit 1; }
    if find "$(dirname "$2")" -maxdepth 1 -name "$(basename "$2").tmp.*" -type f | grep -q .; then
      echo "write_config_file left a temporary config file behind after chown failure" >&2
      find "$(dirname "$2")" -maxdepth 1 -name "$(basename "$2").tmp.*" -type f >&2
      exit 1
    fi
  ' _ "$tmp_dir" "$conf"

  rm -rf "$tmp_dir"
}

check_unsafe_config_loads_fail_closed() {
  if grep -R -n 'load_config_file "\$CONF_FILE" "\${CONFIG_KEYS\[@\]}" || return 0' impl dist 2>/dev/null; then
    echo "App config loaders must not ignore unsafe or unreadable config files." >&2
    return 1
  fi
  awk '
      /error "\$\(t error\.config_owner "\$conf_file"\)"/ { saw_owner=1 }
      /error "\$\(t error\.config_permission "\$conf_file"\)"/ { saw_permission=1 }
      /warn "\$\(t warn\.config_(owner|permission)/ { saw_warn=1 }
      END {
        if (!(saw_owner && saw_permission) || saw_warn) {
          print "Unsafe config ownership or permissions must fail closed with config errors." > "/dev/stderr"
          exit 1
        }
      }
    ' lib/config.sh
}

check_config_save_failures_are_explicit() {
  awk '
      /write_config_file\(\)/ { in_func=1; saw_tmp=0; saw_tmp_return=0; saw_chmod=0; saw_mv=0; saw_cleanup=0; next }
      in_func && /if ! tmp_file="\$\(mktemp "\$\{conf_file\}\.tmp\.XXXXXX"\)"; then/ { saw_tmp=1 }
      in_func && saw_tmp && /return 1/ { saw_tmp_return=1 }
      in_func && /chmod 600 "\$tmp_file"/ { saw_chmod=1 }
      in_func && /mv "\$tmp_file" "\$conf_file"/ { saw_mv=1 }
      in_func && /rm -f "\$tmp_file"/ { saw_cleanup=1 }
      in_func && /^}/ {
        if (!(saw_tmp && saw_tmp_return && saw_chmod && saw_mv && saw_cleanup)) {
          printf "%s write_config_file must report temp creation failures, secure, replace, and clean up temporary config files\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_func=0
      }
 ' lib/config.sh 
  awk '
      /error\.config_write/ { saw_key=1 }
      END {
        if (!saw_key) {
          print "Config save failures must have a shared error message." > "/dev/stderr"
          exit 1
        }
      }
 ' lib/i18n.sh 
  awk '
      /^(app_)?save_config\(\)/ { in_func=1; saw_if=0; saw_error=0; next }
      in_func && /write_config_file/ { saw_if=1 }
      in_func && /error.*config_write/ { saw_error=1 }
      in_func && /^}/ {
        if (!(saw_if && saw_error)) {
          printf "%s save_config must report config write failures explicitly\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_func=0
      }
    ' impl/install_sub2api.sh impl/install_cyberstrikeai.sh impl/install_vaultwarden.sh impl/install_hugo_blog.sh \
 lib/app.sh
}

check_summary_ip_detection_has_fallback() {
  if grep -R -n 'hostname -I .*| awk '\''{print $1}'\''' \
      impl/install_hugo_blog.sh impl/install_newapi.sh impl/install_sub2api.sh impl/install_vaultwarden.sh impl/install_cyberstrikeai.sh 2>/dev/null \
      | grep -v '|| true'; then
    echo "Summary IP detection must tolerate hostname -I failures and provide YOUR_SERVER_IP fallback." >&2
    return 1
  fi
  local file
  for file in impl/install_hugo_blog.sh impl/install_newapi.sh impl/install_sub2api.sh impl/install_vaultwarden.sh impl/install_cyberstrikeai.sh; do
    awk '
        /hostname -I 2>\/dev\/null \| awk '\''\{print \$1\}'\'' \|\| true/ { saw_safe=1 }
        /YOUR_SERVER_IP/ { saw_fallback=1 }
        END {
          if (!(saw_safe && saw_fallback)) {
            printf "%s summary IP detection must use a non-fatal hostname pipeline and fallback value\n", FILENAME > "/dev/stderr"
            exit 1
          }
        }
      ' "$file"
  done
}

check_systemctl_status_diagnostics_are_nonfatal() {
  awk '
      /systemctl status .*\| head .*\| sed/ {
        pending=1
        pending_line=FNR
        if (/&&|\|\| true/) {
          pending=0
        }
        next
      }
      pending {
        if (/\|\| (true|echo|warn|error)/) {
          pending=0
          next
        }
        printf "%s:%d systemctl status diagnostic pipelines must be non-fatal under pipefail.\n", FILENAME, pending_line > "/dev/stderr"
        exit 1
      }
    ' impl/install_sub2api.sh impl/install_vaultwarden.sh impl/install_cyberstrikeai.sh
}

check_status_commands_allow_non_root() {
  awk '
      /app\.sub2api\.warn\.non_root_status/ { saw_sub2api=1 }
      /app\.cyberstrikeai\.warn\.non_root_status/ { saw_csai=1 }
      /app\.tickflow\.warn\.non_root_status/ { saw_tickflow=1 }
      END {
        if (!(saw_sub2api && saw_csai && saw_tickflow)) {
          print "Status commands that run without root must warn when details may be incomplete." > "/dev/stderr"
          exit 1
        }
      }
    ' apps/sub2api.sh apps/cyberstrikeai.sh apps/tickflow.sh
  awk '
      /^bapp_status\(\)/ { in_status=1; saw_warn=0; next }
      in_status && /warn "\$\(t binary_app\.warn\.non_root_status "\$0"\)"/ { saw_warn=1 }
      in_status && /^}/ {
        if (!saw_warn) {
          printf "%s shared status must warn when running without root\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_status=0
      }
    ' lib/binary_app.sh
  awk '
      /preflight_check\(\)/ { in_preflight=1; saw_status_exemption=0; next }
      in_preflight && /status/ && /\$EUID/ { saw_status_exemption=1 }
      in_preflight && /^}/ {
        if (!saw_status_exemption) {
          printf "%s preflight must allow the status action without root\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_preflight=0
      }
      /do_status\(\)/ { in_status=1; saw_warn=0; next }
      in_status && /warn "\$\(t app\.(sub2api|cyberstrikeai|tickflow)\.warn\.non_root_status "\$0"\)"/ { saw_warn=1 }
      in_status && /^}/ {
        if (!saw_warn) {
          printf "%s status must warn when running without root\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_status=0
      }
    ' impl/install_sub2api.sh impl/install_cyberstrikeai.sh impl/install_tickflow.sh
}

check_api_status_directory_sizes_are_nonfatal() {
  awk '
      /do_status\(\)/ { in_status=1; next }
      in_status && /^}/ {
        if (!(saw_dir && saw_backup)) {
          printf "%s Sub2API status directory sizes must fall back instead of failing under pipefail\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_status=0
      }
      in_status && /_sz=\$\(du -sh "\$_d" 2>\/dev\/null \| awk '\''\{print \$1\}'\'' \|\| t app\.sub2api\.status\.unknown\)/ { saw_dir=1 }
      in_status && /bak_total_size=\$\(du -sh "\$BACKUP_DIR" 2>\/dev\/null \| awk '\''\{print \$1\}'\'' \|\| t app\.sub2api\.status\.unknown\)/ { saw_backup=1 }
    ' impl/install_sub2api.sh
  awk '
      /^bapp_status\(\)/ { in_status=1; next }
      in_status && /^}/ {
        if (!(saw_paths)) {
          printf "%s shared status must verify configured paths exist without failing under pipefail\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_status=0
      }
      in_status && /\[\[ -e "\$path" \]\]/ { saw_paths=1 }
    ' lib/binary_app.sh
}

check_status_port_matches_are_bounded() {
  if grep -R -nF 'grep ":${PORT}"' \
 impl/install_sub2api.sh 2>/dev/null; then
    echo "API port owner detection must not use substring port matches." >&2
    return 1
  fi
  if grep -R -nF 'grep "${PORT}"' \
 impl/install_sub2api.sh 2>/dev/null; then
    echo "API firewall status checks must not use substring port matches." >&2
    return 1
  fi
  if grep -R -nF 'grep ":${VW_PORT}"' \
      impl/install_vaultwarden.sh 2>/dev/null; then
    echo "Vaultwarden port owner detection must not use substring port matches." >&2
    return 1
  fi
  awk '
      index($0, "ss -ltn \"( sport = :$port )\"") { saw_listen=1 }
      index($0, "ss -ltnp \"( sport = :$port )\"") { saw_owner=1 }
      /lsof -iTCP:"\$port" -sTCP:LISTEN -Pn/ { saw_lsof=1 }
      END {
        if (!(saw_listen && saw_owner && saw_lsof)) {
          printf "%s shared port conflict helpers must use bounded port matches for listeners and owners\n", FILENAME > "/dev/stderr"
          exit 1
        }
      }
 ' lib/network.sh 
  awk '
      /app_check_port_conflict "\$PORT"/ { saw_owner++ }
      END {
        if (saw_owner < 1) {
          printf "%s shared lifecycle must use bounded PORT conflict detection\n", FILENAME > "/dev/stderr"
          exit 1
        }
      }
 ' lib/binary_app.sh
  awk '
      /app_check_port_conflict "\$VW_PORT"/ { saw_owner++ }
      END {
        if (saw_owner < 2) {
          printf "%s Vaultwarden checks must use shared bounded VW_PORT conflict detection\n", FILENAME > "/dev/stderr"
          exit 1
        }
      }
    ' impl/install_vaultwarden.sh
}

check_port_conflict_is_warn_only() {
  # Without strict mode the helper always succeeds (warn-only contract), even
  # when the caller passes an explicitly strict third argument.
  "$BASH_BIN" -c '
    set -euo pipefail
    source "$1/lib/logging.sh"
    source "$1/lib/i18n.sh"
    source "$1/lib/network.sh"
    app_check_port_conflict 59998 "TEST_PORT"
    app_check_port_conflict 59998 "TEST_PORT" ""
    exit 0
  ' _ "$ROOT_DIR"
}

# Strict mode must turn an occupied port into a failing preflight so installs
# abort cheaply instead of triggering heavyweight rollback at systemctl start.
check_port_conflict_strict_mode_aborts() {
  "$BASH_BIN" -c '
    set -euo pipefail
    source "$1/lib/logging.sh"
    source "$1/lib/i18n.sh"
    source "$1/lib/network.sh"
    # Stub the detection backend (platform-independent, mirrors
    # check_port_listening_process_behavior): header line plus one LISTEN row,
    # since port_is_listening strips the first line with tail -n +2.
    ss() { printf "State Recv-Q Send-Q Local Address:Port Peer Address:Port Process\nLISTEN 0 511 0.0.0.0:59995 0.0.0.0:* users:((\"nginx\",pid=123,fd=10))\n"; }

    set +e
    out1="$(app_check_port_conflict 59995 "TEST_PORT" 1 2>&1)"; rc1=$?
    out2="$(DEPLOY_FAIL_ON_PORT_CONFLICT=1 app_check_port_conflict 59995 "TEST_PORT" "" 2>&1)"; rc2=$?
    # Without any strict trigger the same occupied port still only warns.
    out3="$(app_check_port_conflict 59995 "TEST_PORT" "" 2>&1)"; rc3=$?
    set -e

    [[ "$rc1" -ne 0 ]] || { echo "strict arg did not fail on occupied port: $out1" >&2; exit 1; }
    [[ "$rc2" -ne 0 ]] || { echo "DEPLOY_FAIL_ON_PORT_CONFLICT=1 did not fail on occupied port: $out2" >&2; exit 1; }
    [[ "$rc3" -eq 0 ]] || { echo "warn-only mode must succeed on occupied port: $out3" >&2; exit 1; }
    [[ "$out1" == *"$(t warn.port_conflict_abort)"* ]] || { echo "strict abort hint missing: $out1" >&2; exit 1; }
    [[ "$out3" != *"$(t warn.port_conflict_abort)"* ]] || { echo "warn-only mode must not print abort hint" >&2; exit 1; }
    exit 0
  ' _ "$ROOT_DIR"
}

check_config_sanitization_behavior() {
  "$BASH_BIN" -c '
    set -euo pipefail
    source "$1/lib/config.sh"
    cr=$(printf "\r")
    lf=$(printf "\n")
    value="abc${cr}${lf}def\"quoted\""
    sanitized="$(sanitize_conf_val "$value")"
    [[ "$sanitized" == "abc" ]] || { echo "embedded CR/LF or quotes not stripped: [$sanitized]" >&2; exit 1; }
    [[ "$(sanitize_conf_val "8080")" == "8080" ]] || { echo "plain value altered" >&2; exit 1; }
    [[ "$(sanitize_conf_val "hello world")" == "hello world" ]] || { echo "value with spaces altered" >&2; exit 1; }
    [[ "$(sanitize_conf_val "a\"b\"c")" == "abc" ]] || { echo "double quotes not removed" >&2; exit 1; }
    [[ "$(trim_conf_token "  foo  ")" == "foo" ]] || { echo "trim_conf_token failed" >&2; exit 1; }
    tabbed=$(printf "\tbar\n")
    [[ "$(trim_conf_token "$tabbed")" == "bar" ]] || { echo "trim_conf_token tab/newline failed" >&2; exit 1; }
    exit 0
  ' _ "$ROOT_DIR"
}
check_config_key_shape_locale_independent() {
  local tmp_dir conf locale err_file
  tmp_dir="$(mktemp -d)"
  conf="${tmp_dir}/deploy.conf"
  err_file="${tmp_dir}/load.err"
  printf 'PORT=9090\nport=8080\npORT=9999\n' > "$conf"

  cat > "${tmp_dir}/stat" <<'STUB'
#!/usr/bin/env bash
case "${2:-}" in
  %U) echo root ;;
  %a) echo 600 ;;
  *) /usr/bin/stat "$@" ;;
esac
STUB
  chmod +x "${tmp_dir}/stat"

  # The shape regex ^[A-Z_][A-Z0-9_]*$ must reject lowercase/mixed-case keys on
  # every locale. UTF-8 collation locales (en_US.UTF-8, zh_CN.UTF-8) used to let
  # [A-Z0-9] match lowercase; run the behavior check under C and under each
  # UTF-8 locale whose collation actually differs from C, so the pin in
  # load_config_file cannot regress silently.
  for locale in C en_US.UTF-8 zh_CN.UTF-8; do
    if [[ "$locale" == "C" ]] || LC_ALL="$locale" "$BASH_BIN" -c '[[ "port" =~ ^[A-Z_][A-Z0-9_]*$ ]]'; then
      PATH="${tmp_dir}:$PATH" LC_ALL="$locale" "$BASH_BIN" -c '
        set -euo pipefail
        source "$1/lib/logging.sh"
        source "$1/lib/i18n.sh"
        source "$1/lib/config.sh"
        PORT=""
        port=""
        pORT=""
        set +e
        load_config_file "$2" PORT 2> "$3" >/dev/null
        status=$?
        set -e
        [[ "$status" -eq 0 ]] || { echo "load_config_file failed under LC_ALL=${LC_ALL:-unset}" >&2; exit 1; }
        [[ "$PORT" == "9090" ]] || { echo "PORT was not loaded under LC_ALL=${LC_ALL:-unset}" >&2; exit 1; }
        [[ -z "$port" && -z "$pORT" ]] || { echo "lowercase/mixed-case config key was assigned under LC_ALL=${LC_ALL:-unset}" >&2; exit 1; }
        err="$(cat "$3")"
        [[ "$err" == *"$(t warn.config_invalid_key port)"* ]] || { echo "expected invalid-key warning for "port" under LC_ALL=${LC_ALL:-unset}; got: $err" >&2; exit 1; }
        [[ "$err" == *"$(t warn.config_invalid_key pORT)"* ]] || { echo "expected invalid-key warning for "pORT" under LC_ALL=${LC_ALL:-unset}; got: $err" >&2; exit 1; }
        exit 0
      ' _ "$ROOT_DIR" "$conf" "$err_file"
    fi
  done

  rm -rf "$tmp_dir"
}

check_config_reserved_keys_are_rejected() {
  local tmp_dir conf err_file
  tmp_dir="$(mktemp -d)"
  conf="${tmp_dir}/deploy.conf"
  err_file="${tmp_dir}/load.err"
  printf 'PORT=9090\nIFS=evil\n' > "$conf"

  cat > "${tmp_dir}/stat" <<'STUB'
#!/usr/bin/env bash
case "${2:-}" in
  %U) echo root ;;
  %a) echo 600 ;;
  *) /usr/bin/stat "$@" ;;
esac
STUB
  chmod +x "${tmp_dir}/stat"

  PATH="${tmp_dir}:$PATH" "$BASH_BIN" -c '
    set -euo pipefail
    source "$1/lib/logging.sh"
    source "$1/lib/i18n.sh"
    source "$1/lib/config.sh"
    PORT=""
    IFS=$'"'"' 	
'"'"'
    set +e
    load_config_file "$2" PORT IFS 2> "$3" >/dev/null
    status=$?
    set -e
    [[ "$status" -eq 0 ]] || { echo "load_config_file failed" >&2; exit 1; }
    [[ "$PORT" == "9090" ]] || { echo "PORT was not loaded" >&2; exit 1; }
    [[ "$IFS" == $'"'"' 	
'"'"' ]] || { echo "reserved key IFS clobbered the shell" >&2; exit 1; }
    err="$(cat "$3")"
    [[ "$err" == *"$(t warn.config_reserved_key IFS)"* ]] || { echo "expected reserved-key warning for IFS; got: $err" >&2; exit 1; }
    exit 0
  ' _ "$ROOT_DIR" "$conf" "$err_file"

  rm -rf "$tmp_dir"
}

check_config_empty_values_keep_defaults() {
  local tmp_dir conf
  tmp_dir="$(mktemp -d)"
  conf="${tmp_dir}/deploy.conf"
  printf 'FOO=""\nBAR=   \nBAZ=nonempty\n' > "$conf"

  cat > "${tmp_dir}/stat" <<'STUB'
#!/usr/bin/env bash
case "${2:-}" in
  %U) echo root ;;
  %a) echo 600 ;;
  *) /usr/bin/stat "$@" ;;
esac
STUB
  chmod +x "${tmp_dir}/stat"

  PATH="${tmp_dir}:$PATH" "$BASH_BIN" -c '
    set -euo pipefail
    source "$1/lib/logging.sh"
    source "$1/lib/i18n.sh"
    source "$1/lib/config.sh"
    FOO="default-foo"
    BAR="default-bar"
    BAZ="default-baz"
    load_config_file "$2" FOO BAR BAZ
    [[ "$FOO" == "default-foo" ]] || { echo "empty quoted config value clobbered the script default: [$FOO]" >&2; exit 1; }
    [[ "$BAR" == "default-bar" ]] || { echo "blank config value clobbered the script default: [$BAR]" >&2; exit 1; }
    [[ "$BAZ" == "nonempty" ]] || { echo "non-empty config value was not loaded: [$BAZ]" >&2; exit 1; }
    exit 0
  ' _ "$ROOT_DIR" "$conf"

  rm -rf "$tmp_dir"
}
