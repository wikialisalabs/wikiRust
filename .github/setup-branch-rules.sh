#!/usr/bin/env bash
# =============================================================================
# setup-branch-rules.sh — Wikialisalabs Branch Protection + Role Setup
# =============================================================================
# Thiết lập Branch Protection Rules cho các nhánh:
#   main    — Production        (chỉ ledger-team + main-admin merge)
#   master  — Release candidates (master-team + ledger-team review)
#   dev     — Development       (dev-leads + core/evm/ledger team push)
#   ledger  — Audit/compliance  (chỉ ledger-team, immutable trail)
#
# Teams cần tạo trong org wikialisalabs:
#   dev-leads       — Lead Developers
#   core-devs       — Core Primitives team
#   evm-team        — EVM Runtime team
#   zk-team         — ZK/Experimental team
#   ledger-team     — Auditor/Release team
#   l2-team         — OP Stack / L2 team
#   tooling-team    — Developer tooling team
#   doc-reviewers   — Documentation team
#   devops-team     — CI/CD / Infrastructure team
#
# Yêu cầu PAT (Classic Token) với scopes:
#   ✅ repo           — Full control of private/public repositories
#   ✅ workflow        — Update GitHub Action workflows
#   ✅ admin:org       — Full control of orgs and teams
#   ✅ read:org        — Read org and team membership
#
# Tạo PAT tại: https://github.com/settings/tokens/new
#   → Chọn: repo, workflow, admin:org, read:org
#
# Cách dùng:
#   export GH_TOKEN="ghp_xxxxxxxxxxxxxxxxxxxx"
#   chmod +x .github/setup-branch-rules.sh
#   ./.github/setup-branch-rules.sh
#
# Hoặc dùng gh CLI (khuyến khích):
#   gh auth login   # chọn GitHub.com → HTTPS → Paste token
#   ./.github/setup-branch-rules.sh
# =============================================================================

set -euo pipefail

# ── Cấu hình ─────────────────────────────────────────────────────────────────
ORG="wikialisalabs"
REPO="wikiRust"
FULL_REPO="${ORG}/${REPO}"

# Màu sắc terminal
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
log_ok()      { echo -e "${GREEN}[OK]${NC}   $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error()   { echo -e "${RED}[ERR]${NC}  $*"; }
log_section() {
    echo -e "\n${CYAN}════════════════════════════════════════${NC}"
    echo -e "${CYAN} $*${NC}"
    echo -e "${CYAN}════════════════════════════════════════${NC}"
}

# ── Kiểm tra token ────────────────────────────────────────────────────────────
if [[ -z "${GH_TOKEN:-}" ]]; then
    log_error "GH_TOKEN chưa được set!"
    echo ""
    echo "  Cách 1 — PAT trực tiếp:"
    echo "    export GH_TOKEN=\"ghp_xxxxxxxxxxxxxxxxxxxx\""
    echo "    ./.github/setup-branch-rules.sh"
    echo ""
    echo "  Cách 2 — gh CLI (khuyến khích):"
    echo "    gh auth login   # chọn GitHub.com → HTTPS → Paste token"
    echo "    export GH_TOKEN=\$(gh auth token)"
    echo "    ./.github/setup-branch-rules.sh"
    echo ""
    echo "  Tạo token tại: https://github.com/settings/tokens/new"
    echo "  Scopes cần thiết: repo, workflow, admin:org, read:org"
    exit 1
fi

# ── Helper: GitHub API call với hiển thị lỗi chi tiết ────────────────────────
gh_api() {
    local method="$1"
    local endpoint="$2"
    local data="${3:-}"
    local allow_fail="${4:-false}"  # "true" = không exit khi lỗi

    local args=(-s -X "$method" \
        -H "Authorization: Bearer ${GH_TOKEN}" \
        -H "Accept: application/vnd.github+json" \
        -H "X-GitHub-Api-Version: 2022-11-28")

    if [[ -n "$data" ]]; then
        args+=(-H "Content-Type: application/json" -d "$data")
    fi

    local response http_code body
    # Lấy cả HTTP status code và body
    response=$(curl "${args[@]}" -w "\n__HTTP_CODE__%{http_code}" \
        "https://api.github.com${endpoint}" 2>/dev/null)
    http_code=$(echo "$response" | tail -1 | sed 's/__HTTP_CODE__//')
    body=$(echo "$response" | sed '$d')

    if [[ "$http_code" -ge 400 ]]; then
        local msg
        msg=$(echo "$body" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('message','unknown error'))" 2>/dev/null || echo "$body")
        if [[ "$allow_fail" == "true" ]]; then
            echo "__API_ERROR__: HTTP ${http_code} — ${msg}" >&2
            echo ""
            return 0
        fi
        echo "__API_ERROR__: HTTP ${http_code} — ${msg}" >&2
        return 1
    fi

    echo "$body"
}

# ── Bước 1: Kiểm tra kết nối & scopes ────────────────────────────────────────
log_section "Bước 1: Kiểm tra kết nối & Token Scopes"

USER_RESP=$(gh_api GET /user "" "false" 2>/dev/null || echo "")
if [[ -z "$USER_RESP" ]] || echo "$USER_RESP" | grep -q "__API_ERROR__"; then
    log_error "Không thể kết nối GitHub API."
    log_error "Kiểm tra lại GH_TOKEN (phải có scopes: repo, workflow, admin:org)."
    exit 1
fi

WHOAMI=$(echo "$USER_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin)['login'])" 2>/dev/null || echo "unknown")
log_ok "Đăng nhập với: ${WHOAMI}"

# Kiểm tra scopes thực tế qua header
SCOPES_RAW=$(curl -sI -H "Authorization: Bearer ${GH_TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/user" 2>/dev/null | grep -i "x-oauth-scopes:" || echo "")
if [[ -n "$SCOPES_RAW" ]]; then
    log_info "Token scopes: $(echo "$SCOPES_RAW" | sed 's/x-oauth-scopes://I' | tr -d '\r' | xargs)"
else
    log_warn "Không thể đọc token scopes — dùng fine-grained token thì bỏ qua cảnh báo này."
fi

# Kiểm tra quyền admin trên repo
PERM=$(gh_api GET "/repos/${FULL_REPO}" "" "true" | \
    python3 -c "import sys,json; d=json.load(sys.stdin); print(str(d.get('permissions',{}).get('admin',False)).lower())" 2>/dev/null || echo "false")
if [[ "$PERM" != "true" ]]; then
    log_warn "Token không có quyền admin trên ${FULL_REPO}."
    log_warn "Branch protection rules (Bước 5) sẽ thất bại nếu không có quyền này."
    log_warn "Đảm bảo: scope 'repo' đã bật VÀ tài khoản là Owner/Admin của repo."
fi

# ── Bước 2: Tạo GitHub Teams ──────────────────────────────────────────────────
log_section "Bước 2: Tạo Teams trong Org ${ORG}"
log_info "Cần scope: admin:org — nếu thiếu, bỏ qua và tạo teams thủ công tại:"
log_info "  https://github.com/orgs/${ORG}/teams/new"

# Danh sách teams cần tạo: slug | description
declare -A TEAMS=(
    ["dev-leads"]="Lead Developers — review mặc định toàn repo"
    ["core-devs"]="Core Primitives team — Tầng 1: alloy-core, RLP, Sol Types"
    ["evm-team"]="EVM Runtime team — Tầng 2: evm, evm2"
    ["zk-team"]="ZK/Experimental team — Tầng 2: evm2 ZK-IR output"
    ["ledger-team"]="Auditor/Release team — compliance, merge master→main"
    ["l2-team"]="OP Stack / L2 team — Tầng 3: op-alloy"
    ["tooling-team"]="Developer tooling team — Tầng 3: svm-rs"
    ["doc-reviewers"]="Documentation reviewers"
    ["devops-team"]="CI/CD Infrastructure team"
)

TEAMS_CREATED=0
TEAMS_FAILED=0

create_team() {
    local slug="$1"
    local desc="$2"

    # Kiểm tra đã tồn tại
    local existing
    existing=$(gh_api GET "/orgs/${ORG}/teams/${slug}" "" "true" 2>/dev/null)
    if ! echo "$existing" | grep -q "__API_ERROR__"; then
        local existing_id
        existing_id=$(echo "$existing" | python3 -c "import sys,json; print(json.load(sys.stdin).get('id',''))" 2>/dev/null || echo "")
        if [[ -n "$existing_id" ]]; then
            log_warn "Team '${slug}' đã tồn tại (id=${existing_id}), bỏ qua."
            return
        fi
    fi

    local payload
    payload=$(python3 -c "
import json, sys
print(json.dumps({
    'name': sys.argv[1],
    'description': sys.argv[2],
    'privacy': 'closed',
    'permission': 'push'
}))" "$slug" "$desc")

    local result
    result=$(gh_api POST "/orgs/${ORG}/teams" "$payload" "true" 2>/dev/null)

    if echo "$result" | grep -q "__API_ERROR__"; then
        local errmsg
        errmsg=$(echo "$result" | sed 's/__API_ERROR__: //')
        log_warn "Team '${slug}' — ${errmsg}"
        TEAMS_FAILED=$((TEAMS_FAILED + 1))
    else
        local new_id
        new_id=$(echo "$result" | python3 -c "import sys,json; print(json.load(sys.stdin).get('id','?'))" 2>/dev/null || echo "?")
        log_ok "Team '${slug}' đã tạo (id=${new_id})"
        TEAMS_CREATED=$((TEAMS_CREATED + 1))
    fi
}

for slug in "${!TEAMS[@]}"; do
    create_team "$slug" "${TEAMS[$slug]}"
done

if [[ $TEAMS_FAILED -gt 0 ]]; then
    log_warn "${TEAMS_FAILED} team(s) thất bại — thường do thiếu scope 'admin:org'."
    log_warn "Tạo thủ công tại: https://github.com/orgs/${ORG}/teams/new"
fi

# ── Bước 3: Cấp quyền Teams trên Repo ────────────────────────────────────────
log_section "Bước 3: Cấp quyền Teams trên ${REPO}"

grant_team_permission() {
    local team_slug="$1"
    local permission="$2"  # pull | push | triage | maintain | admin

    local payload
    payload=$(python3 -c "import json; print(json.dumps({'permission': '${permission}'}))")

    local result
    result=$(gh_api PUT "/orgs/${ORG}/teams/${team_slug}/repos/${FULL_REPO}" "$payload" "true" 2>/dev/null)

    if echo "$result" | grep -q "__API_ERROR__"; then
        log_warn "Team '${team_slug}' → '${permission}': $(echo "$result" | sed 's/__API_ERROR__: //')"
    else
        log_ok "Team '${team_slug}' → quyền '${permission}' trên ${REPO}"
    fi
}

# Phân quyền theo vai trò
grant_team_permission "dev-leads"    "maintain"
grant_team_permission "core-devs"    "push"
grant_team_permission "evm-team"     "push"
grant_team_permission "zk-team"      "push"
grant_team_permission "ledger-team"  "admin"
grant_team_permission "l2-team"      "push"
grant_team_permission "tooling-team" "push"
grant_team_permission "doc-reviewers" "triage"
grant_team_permission "devops-team"  "maintain"

# ── Bước 4: Tạo các nhánh nếu chưa tồn tại ───────────────────────────────────
log_section "Bước 4: Tạo các nhánh dev, master, ledger"

MAIN_SHA_RESP=$(gh_api GET "/repos/${FULL_REPO}/git/refs/heads/main" "" "false")
MAIN_SHA=$(echo "$MAIN_SHA_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin)['object']['sha'])" 2>/dev/null || echo "")

if [[ -z "$MAIN_SHA" ]]; then
    log_error "Không thể lấy SHA của nhánh main!"
    exit 1
fi
log_info "main HEAD: ${MAIN_SHA}"

create_branch_if_not_exists() {
    local branch="$1"

    local check
    check=$(gh_api GET "/repos/${FULL_REPO}/git/refs/heads/${branch}" "" "true" 2>/dev/null)
    if ! echo "$check" | grep -q "__API_ERROR__"; then
        local ref
        ref=$(echo "$check" | python3 -c "import sys,json; print(json.load(sys.stdin).get('ref',''))" 2>/dev/null || echo "")
        if [[ -n "$ref" ]]; then
            log_warn "Nhánh '${branch}' đã tồn tại (${ref}), bỏ qua."
            return
        fi
    fi

    local payload
    payload=$(python3 -c "import json; print(json.dumps({
        'ref': 'refs/heads/${branch}',
        'sha': '${MAIN_SHA}'
    }))")

    local result
    result=$(gh_api POST "/repos/${FULL_REPO}/git/refs" "$payload" "true" 2>/dev/null)

    if echo "$result" | grep -q "__API_ERROR__"; then
        log_warn "Nhánh '${branch}': $(echo "$result" | sed 's/__API_ERROR__: //')"
    else
        log_ok "Đã tạo nhánh '${branch}' từ main (${MAIN_SHA:0:8})"
    fi
}

create_branch_if_not_exists "dev"
create_branch_if_not_exists "master"
create_branch_if_not_exists "ledger"

# ── Bước 5: Branch Protection Rules ──────────────────────────────────────────
log_section "Bước 5: Branch Protection Rules"
log_info "API: PUT /repos/${FULL_REPO}/branches/{branch}/protection"
log_info "Cần scope 'repo' VÀ quyền admin trên repo."

set_branch_protection() {
    local branch="$1"
    local payload="$2"

    local result
    result=$(gh_api PUT "/repos/${FULL_REPO}/branches/${branch}/protection" "$payload" "true" 2>/dev/null)

    if echo "$result" | grep -q "__API_ERROR__"; then
        local errmsg
        errmsg=$(echo "$result" | sed 's/__API_ERROR__: //')
        log_warn "Branch '${branch}' protection: ${errmsg}"
        if echo "$errmsg" | grep -qi "must have admin rights\|403\|not found"; then
            log_warn "  → Thiết lập thủ công tại: https://github.com/${FULL_REPO}/settings/branches"
        fi
    else
        log_ok "Protection rule áp dụng cho nhánh '${branch}'"
    fi
}

# --- main: 2 reviews, CI bắt buộc, chỉ ledger-team/dev-leads push ---
log_info "Cấu hình nhánh: main"
set_branch_protection "main" "$(python3 -c "
import json
print(json.dumps({
    'required_status_checks': {
        'strict': True,
        'contexts': [
            'CI \u2014 wikiRust / build',
            'CI \u2014 wikiRust / test',
            'CI \u2014 wikiRust / clippy',
            'Enforce Branch & Role Rules / Validate Branch & Role Governance'
        ]
    },
    'enforce_admins': False,
    'required_pull_request_reviews': {
        'dismissal_restrictions': {'teams': ['ledger-team', 'dev-leads']},
        'dismiss_stale_reviews': True,
        'require_code_owner_reviews': True,
        'required_approving_review_count': 2,
        'require_last_push_approval': True
    },
    'restrictions': {
        'users': [],
        'teams': ['ledger-team', 'dev-leads'],
        'apps': []
    },
    'required_linear_history': True,
    'allow_force_pushes': False,
    'allow_deletions': False,
    'required_conversation_resolution': True
}))
")"

# --- master: 1 review, CI build+test, ledger-team/dev-leads/evm-team ---
log_info "Cấu hình nhánh: master"
set_branch_protection "master" "$(python3 -c "
import json
print(json.dumps({
    'required_status_checks': {
        'strict': True,
        'contexts': [
            'CI \u2014 wikiRust / build',
            'CI \u2014 wikiRust / test',
            'Enforce Branch & Role Rules / Validate Branch & Role Governance'
        ]
    },
    'enforce_admins': False,
    'required_pull_request_reviews': {
        'dismissal_restrictions': {'teams': ['ledger-team', 'dev-leads']},
        'dismiss_stale_reviews': True,
        'require_code_owner_reviews': True,
        'required_approving_review_count': 1,
        'require_last_push_approval': False
    },
    'restrictions': {
        'users': [],
        'teams': ['ledger-team', 'dev-leads'],
        'apps': []
    },
    'required_linear_history': True,
    'allow_force_pushes': False,
    'allow_deletions': False,
    'required_conversation_resolution': True
}))
")"

# --- dev: 1 review, CI build, tất cả teams push ---
log_info "Cấu hình nhánh: dev"
set_branch_protection "dev" "$(python3 -c "
import json
print(json.dumps({
    'required_status_checks': {
        'strict': False,
        'contexts': ['CI \u2014 wikiRust / build']
    },
    'enforce_admins': False,
    'required_pull_request_reviews': {
        'dismiss_stale_reviews': False,
        'require_code_owner_reviews': False,
        'required_approving_review_count': 1,
        'require_last_push_approval': False
    },
    'restrictions': {
        'users': [],
        'teams': ['dev-leads', 'core-devs', 'evm-team', 'zk-team',
                  'ledger-team', 'l2-team', 'tooling-team', 'devops-team'],
        'apps': []
    },
    'required_linear_history': False,
    'allow_force_pushes': False,
    'allow_deletions': False,
    'required_conversation_resolution': False
}))
")"

# --- ledger: 2 reviews, enforce_admins, bất biến ---
log_info "Cấu hình nhánh: ledger"
set_branch_protection "ledger" "$(python3 -c "
import json
print(json.dumps({
    'required_status_checks': None,
    'enforce_admins': True,
    'required_pull_request_reviews': {
        'dismissal_restrictions': {'teams': ['ledger-team', 'dev-leads']},
        'dismiss_stale_reviews': True,
        'require_code_owner_reviews': True,
        'required_approving_review_count': 2,
        'require_last_push_approval': True
    },
    'restrictions': {
        'users': [],
        'teams': ['ledger-team', 'dev-leads'],
        'apps': []
    },
    'required_linear_history': True,
    'allow_force_pushes': False,
    'allow_deletions': False,
    'required_conversation_resolution': True
}))
")"

# ── Bước 6: Tóm tắt ──────────────────────────────────────────────────────────
log_section "Hoàn tất — Tóm tắt cấu hình"

cat <<EOF

  Repo : https://github.com/${FULL_REPO}

  Teams (tạo thủ công nếu script thiếu scope admin:org):
    dev-leads    → maintain   https://github.com/orgs/${ORG}/teams/new
    core-devs    → push
    evm-team     → push
    zk-team      → push
    ledger-team  → admin
    l2-team      → push
    tooling-team → push
    doc-reviewers→ triage
    devops-team  → maintain

  Nhánh và bảo vệ:
    main   → 2 reviews | CI full | ledger-team/dev-leads only
    master → 1 review  | CI build+test | ledger-team/dev-leads only
    dev    → 1 review  | CI build | all teams push
    ledger → 2 reviews | enforce_admins | immutable history

  Xem/chỉnh tại:
    Branches : https://github.com/${FULL_REPO}/settings/branches
    Teams    : https://github.com/orgs/${ORG}/teams
    Rules    : https://github.com/${FULL_REPO}/settings/rules

  Nếu Branch Protection bị lỗi 403, kiểm tra:
    1. PAT có scope 'repo' (không chỉ 'public_repo')
    2. Tài khoản là Owner hoặc Admin của repo
    3. Token chưa hết hạn: https://github.com/settings/tokens

EOF
log_ok "Script hoàn tất!"
