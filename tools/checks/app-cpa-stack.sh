# shellcheck shell=bash
# shellcheck source=../verify.sh
# Verify checks for the cpa-stack app (apps/cpa_stack.sh).

check_cpa_stack_layout() {
  local file
  for file in impl/install_cpa_stack.sh dist/install_cpa_stack.sh; do
    grep -Fq 'host: "127.0.0.1"' "$file" \
      && grep -Fq 'usage-statistics-enabled: true' "$file" \
      && grep -Fq 'Environment=HTTP_ADDR=127.0.0.1:18317' "$file" \
      && grep -Fq 'CPA_UPSTREAM_URL="${prior_upstream:-http://127.0.0.1:8317}"' "$file" \
      && grep -Fq 'cpa_stack_download_verified_archive' "$file" \
      && grep -Fq 'checksums.txt' "$file" \
      && grep -Fq 'data.key' "$file" \
      && grep -Fq 'CPAMP_ENV_FILE' "$file" \
      && grep -Fq 'location /.well-known/acme-challenge/' "$file" \
      && grep -Fq 'proxy_pass http://127.0.0.1:8317;' "$file" \
      && grep -Fq 'proxy_pass http://127.0.0.1:18317;' "$file" \
      && grep -Fq 'certbot certonly --webroot' "$file" \
      && grep -Fq 'CPA_STACK_COMPONENT' "$file" \
      && grep -Fq 'do_cert()' "$file" \
      && grep -Fq 'app.cpa_stack.success.https' "$file" \
      && grep -Fq 'cpa_stack_nginx_http2_directives' "$file" \
      && grep -Fq 'http2 on;' "$file" \
      && grep -Fq 'listen 443 ssl http2;' "$file" \
      || {
        echo "CPA Stack must retain local-only backends, verified releases, HTTPS reverse proxy, and component update controls: ${file}" >&2
        return 1
      }
  done
}
