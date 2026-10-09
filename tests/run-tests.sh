#!/usr/bin/env bash
# Repository checks: privacy hygiene, script syntax, doc/script consistency.
# Usage: tests/run-tests.sh        (needs only bash + git; PowerShell checks run if pwsh is installed)
set -u
cd "$(dirname "${BASH_SOURCE[0]}")/.."

pass=0; fail=0; skip=0; warn=0
ok()   { echo "  ✓ $1"; pass=$((pass+1)); }
bad()  { echo "  ✗ $1"; shift; [[ $# -gt 0 ]] && printf '      %s\n' "$@"; fail=$((fail+1)); }
wrn()  { echo "  ⚠ $1"; shift; [[ $# -gt 0 ]] && printf '      %s\n' "$@"; warn=$((warn+1)); }
skp()  { echo "  - $1 (skipped)"; skip=$((skip+1)); }

tracked() { git ls-files -z | grep -zvE '^(tests/|\.github/)' ; }

echo "Privacy"
GUID='[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'
ZERO='00000000-0000-0000-0000-000000000000'
hits=$(git grep -InoE "$GUID" -- . ':!tests' ':!README.md' | grep -v "$ZERO" || true)
[[ -z "$hits" ]] && ok "no real tenant/subscription GUIDs in tracked files" || bad "real GUIDs found" "$hits"

hits=$(git grep -InEi '(password|client_?secret|accountkey|sharedaccesssignature)[[:space:]]*[=:][[:space:]]*["'"'"'][^"'"'"'<$ ]{6,}|sig=[A-Za-z0-9%]{20,}|BEGIN [A-Z ]*PRIVATE KEY' -- . ':!tests' || true)
[[ -z "$hits" ]] && ok "no hard-coded credentials, SAS tokens or private keys" || bad "credential-like strings found" "$hits"

hits=$(git grep -InE '[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+\.[A-Za-z.]{2,}' -- . ':!tests' ':!LICENSE' ':!README.md' || true)
[[ -z "$hits" ]] && ok "no email addresses in tracked files" || bad "email addresses found" "$hits"

hits=$(git ls-files | grep -E '(^|/)migration-data/|\.log$|\.pfx$|\.pem$|\.key$|\.local\.(ps1|sh)$|roleassignments\.' || true)
[[ -z "$hits" ]] && ok "no exports, logs or key material tracked" || bad "private artifacts tracked" "$hits"

for f in migration-params.local.ps1 migration-params.local.sh migration-data/x.json; do
  git check-ignore -q "$f" || { bad ".gitignore does not cover $f"; continue; }
done; ok ".gitignore covers local params and migration-data"

echo "Parameters"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
cp migration-params.sh "$tmp/"; printf 'SOURCE_SUBSCRIPTION_ID="override"\n' > "$tmp/migration-params.local.sh"
out=$(bash -c "source '$tmp/migration-params.sh' >/dev/null 2>&1; echo \"\$SOURCE_SUBSCRIPTION_ID|\$SOURCE_SUB|\$TARGET_SUB|\$OLD_SUBSCRIPTION_ID\"")
[[ "$out" == "override|override||override" ]] && ok "migration-params.local.sh overrides and aliases follow" || bad "param override/alias chain broken" "$out"

echo "Syntax"
shell_files=$(git ls-files '*.sh' '*.azcli')
bad_syntax=""
for f in $shell_files; do bash -n "$f" 2>/dev/null || bad_syntax+="$f"$'\n'; done
[[ -z "$bad_syntax" ]] && ok "all bash scripts parse ($(echo "$shell_files" | wc -l) files)" || bad "bash syntax errors" $bad_syntax

if command -v pwsh >/dev/null; then
  res=$(pwsh -NoProfile -Command '
    $bad = foreach ($f in (git ls-files "*.ps1")) {
      $e = $null; [void][System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path $f), [ref]$null, [ref]$e)
      if ($e) { "$f : $($e[0].Message)" } }
    $bad')
  [[ -z "$res" ]] && ok "all PowerShell scripts parse" || bad "PowerShell parse errors" "$res"
else
  skp "PowerShell parse check (pwsh not installed; CI runs it)"
fi

echo "Documentation"
missing=""
for doc in README.md Docs/*.md; do
  [[ -f "$doc" ]] || continue
  while IFS= read -r p; do [[ -e "$p" ]] || missing+="$doc -> $p"$'\n'; done < <(grep -oE '`[0-9A-Za-z./_-]+\.(ps1|sh|azcli)`' "$doc" | tr -d '`' | grep -v '\.local\.' | sort -u)
done
[[ -z "$missing" ]] && ok "every script named in the docs exists" || bad "docs reference missing scripts" $missing

echo "Scripts load shared parameters"
noparams=""
for f in $(git ls-files '*.ps1' | grep -vE '^(migration-params|tests/)'); do
  grep -qE 'migration-params\.ps1|\$sourceSubscription|\$backupRootDir|\$outputDirectory' "$f" || noparams+="$f"$'\n'
done
[[ -z "$noparams" ]] && ok "every PowerShell script uses migration-params.ps1" || bad "scripts that never reference shared params" $noparams

echo "Pester (parameter binding, dashboard/runbook parity, orchestrator behaviour)"
if command -v pwsh >/dev/null && pwsh -NoProfile -Command 'exit [int](-not (Get-Module -ListAvailable Pester))'; then
  if pwsh -NoProfile -Command 'Invoke-Pester ./tests -CI -Output Minimal' >/tmp/pester.$$ 2>&1; then
    ok "$(grep -o 'Tests Passed: [0-9]*' /tmp/pester.$$ | head -1) (tests/Repo.Tests.ps1)"
  else
    bad "Pester failures" "$(tail -25 /tmp/pester.$$)"
  fi
  rm -f /tmp/pester.$$
else
  skp "Pester suite (needs pwsh + Pester: Install-Module Pester -Scope CurrentUser)"
fi

echo; echo "passed: $pass  failed: $fail  skipped: $skip"
[[ $fail -eq 0 ]]
