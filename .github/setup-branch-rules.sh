#!/usr/bin/env bash
# =============================================================================
# setup-branch-rules.sh — Wikialisalabs Branch Protection + Role Setup
# =============================================================================
# Thiết lập Branch Protection Rules cho các nhánh:
#   main    — Production (chỉ ledger + admin merge)
#   master  — Release candidates (master + ledger role)
#   dev     — Development integration (dev + master + ledger role)
#   ledger  — Audit/compliance trail (chỉ ledger role)
#
# Vai trò (GitHub Teams trong org wikialisalabs):
#   dev     — Developer: push vào dev, tạo PR từ feature/* → dev
#   master  — Senior Dev: review + merge dev → master
#   ledger  — Auditor/Release: review + merge master → main/ledger
#   main    — Alias admin: full repo admin
#
# Yêu cầu:
#   - GitHub PAT với scopes: repo, admin:org, read:org
#   - GitHub CLI (gh) hoặc curl
#
# Cách dùng:
#   export GH_TOKEN="ghp_xxxxxxxxxxxxxxxxxxxx"
#   chmod +x setup-branch-rules.sh
#   ./setup-branch-rules.sh
#
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
NC='\033[0m' # No Color

log_info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
log_ok()      { echo -e "${GREEN}[OK]${NC}   $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error()   { echo -e "${RED}[ERR]${NC}  $*"; }
log_section() { echo -e "\n${CYAN}════════════════════════════════════════${NC}"; echo -e "${CYAN} $*${NC}"; echo -e "${CYAN}════════════════════════════════════════${NC}"; }

# ── Kiểm tra token ────────────────────────────────────────────────────────────
if [[ -z "${GH_TOKEN:-}" ]]; then
    log_error "GH_TOKEN chưa được set!"
    echo "  export GH_TOKEN=\"ghp_xxxxxxxxxxxxxxxxxxxx\""
    echo "  ./setup-branch-rules.sh"
    exit 1
fi

# ── Helper: GitHub API call ───────────────────────────────────────────────────
gh_api() {
    local method="$1"
    local endpoint="$2"
    local data="${3:-}"
    
    local args=(-s -f -X "$method" \
        -H "Authorization: Bearer ${GH_TOKEN}" \
        -H "Accept: application/vnd.github+json" \
        -H "X-GitHub-Api-Version: 2022-11-28")
    
    if [[ -n "$data" ]]; then
        args+=(-H "Content-Type: application/json" -d "$data")
    fi
    
    curl "${args[@]}" "https://api.github.com${endpoint}"
}

# ── Kiểm tra kết nối ─────────────────────────────────────────────────────────
log_section "Bước 1: Kiểm tra kết nối GitHub"

WHOAMI=$(gh_api GET /user | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['login'])" 2>/dev/null || echo "ERROR")
if [[ "$WHOAMI" == "ERROR" ]]; then
    log_error "Không thể kết nối GitHub API. Kiểm tra lại GH_TOKEN."
    exit 1
fi
log_ok "Đăng nhập với: ${WHOAMI}"

# ── Kiểm tra quyền admin trên repo ───────────────────────────────────────────
PERM=$(gh_api GET "/repos/${FULL_REPO}" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('permissions',{}).get('admin','false'))" 2>/dev/null || echo "false")
if [[ "$PERM" != "True" && "$PERM" != "true" ]]; then
    log_warn "Tài khoản ${WHOAMI} không có quyền admin trên ${FULL_REPO}. Một số bước có thể thất bại."
fi

# ── Bước 2: Tạo GitHub Teams ──────────────────────────────────────────────────
log_section "Bước 2: Tạo Teams trong Org ${ORG}"

create_team() {
    local team_name="$1"
    local team_desc="$2"
    local privacy="${3:-closed}"
    
    # Kiểm tra team đã tồn tại chưa
    local existing
    existing=$(gh_api GET "/orgs/${ORG}/teams/${team_name}" 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('id',''))" 2>/dev/null || echo "")
    
    if [[ -n "$existing" ]]; then
        log_warn "Team '${team_name}' đã tồn tại (id=${existing}), bỏ qua tạo mới."
        return
    fi
    
    local payload
    payload=$(python3 -c "import json; print(json.dumps({
        'name': '${team_name}',
        'description': '${team_desc}',
        'privacy': '${privacy}',
        'permission': 'push'
    }))")
    
    local result
    result=$(gh_api POST "/orgs/${ORG}/teams" "$payload" 2>/dev/null | \
        python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('id','ERROR'))" 2>/dev/null || echo "ERROR")
    
    if [[ "$result" == "ERROR" ]]; then
        log_warn "Không thể tạo team '${team_name}' — có thể cần quyền admin:org."
    else
        log_ok "Team '${team_name}' đã tạo (id=${result})"
    fi
}

# Tạo 4 teams tương ứng với 4 vai trò
create_team "dev"    "Developer role — push to dev, create PRs from feature branches"
create_team "master" "Senior Developer role — review and merge dev → master"
create_team "ledger" "Auditor/Release role — review and merge master → main, compliance trail"
create_team "main"   "Admin role — full repository administration"

# ── Bước 3: Cấp quyền Teams trên Repo ────────────────────────────────────────
log_section "Bước 3: Cấp quyền Teams trên ${REPO}"

grant_team_permission() {
    local team_slug="$1"
    local permission="$2"  # pull | push | maintain | triage | admin
    
    local payload
    payload=$(python3 -c "import json; print(json.dumps({'permission': '${permission}'}))")
    
    gh_api PUT "/orgs/${ORG}/teams/${team_slug}/repos/${FULL_REPO}" "$payload" > /dev/null 2>&1 && \
        log_ok "Team '${team_slug}' → quyền '${permission}' trên ${REPO}" || \
        log_warn "Không thể cấp quyền cho team '${team_slug}'"
}

grant_team_permission "dev"    "push"
grant_team_permission "master" "maintain"
grant_team_permission "ledger" "admin"
grant_team_permission "main"   "admin"

# ── Bước 4: Tạo các nhánh nếu chưa tồn tại ───────────────────────────────────
log_section "Bước 4: Tạo các nhánh dev, master, ledger"

# Lấy SHA của nhánh main hiện tại
MAIN_SHA=$(gh_api GET "/repos/${FULL_REPO}/git/refs/heads/main" | \
    python3 -c "import sys,json; print(json.load(sys.stdin)['object']['sha'])" 2>/dev/null || echo "")

if [[ -z "$MAIN_SHA" ]]; then
    log_error "Không thể lấy SHA của nhánh main!"
    exit 1
fi
log_info "main SHA: ${MAIN_SHA}"

create_branch_if_not_exists() {
    local branch="$1"
    
    # Kiểm tra branch đã tồn tại chưa
    local existing
    existing=$(gh_api GET "/repos/${FULL_REPO}/git/refs/heads/${branch}" 2>/dev/null | \
        python3 -c "import sys,json; print(json.load(sys.stdin).get('ref',''))" 2>/dev/null || echo "")
    
    if [[ -n "$existing" ]]; then
        log_warn "Nhánh '${branch}' đã tồn tại, bỏ qua."
        return
    fi
    
    local payload
    payload=$(python3 -c "import json; print(json.dumps({'ref': 'refs/heads/${branch}', 'sha': '${MAIN_SHA}'}))")
    
    gh_api POST "/repos/${FULL_REPO}/git/refs" "$payload" > /dev/null 2>&1 && \
        log_ok "Đã tạo nhánh '${branch}' từ main (${MAIN_SHA:0:8})" || \
        log_warn "Không thể tạo nhánh '${branch}'"
}

create_branch_if_not_exists "dev"
create_branch_if_not_exists "master"
create_branch_if_not_exists "ledger"

# ── Bước 5: Thiết lập Branch Protection Rules ─────────────────────────────────
log_section "Bước 5: Branch Protection Rules"

set_branch_protection() {
    local branch="$1"
    local payload="$2"
    
    gh_api PUT "/repos/${FULL_REPO}/branches/${branch}/protection" "$payload" > /dev/null 2>&1 && \
        log_ok "Protection rule đã áp dụng cho nhánh '${branch}'" || \
        log_warn "Không thể áp dụng protection cho '${branch}' — cần quyền admin."
}

# --- main: chỉ ledger + main team mới được merge, cần 2 reviews ---
log_info "Cấu hình nhánh: main"
set_branch_protection "main" "$(python3 -c "
import json
print(json.dumps({
    'required_status_checks': {
        'strict': True,
        'contexts': ['ci / build', 'ci / test', 'ci / clippy']
    },
    'enforce_admins': False,
    'required_pull_request_reviews': {
        'dismissal_restrictions': {
            'teams': ['ledger', 'main']
        },
        'dismiss_stale_reviews': True,
        'require_code_owner_reviews': True,
        'required_approving_review_count': 2,
        'require_last_push_approval': True
    },
    'restrictions': {
        'users': [],
        'teams': ['ledger', 'main'],
        'apps': []
    },
    'required_linear_history': True,
    'allow_force_pushes': False,
    'allow_deletions': False,
    'block_creations': False,
    'required_conversation_resolution': True,
    'lock_branch': False,
    'allow_fork_syncing': False
}))
")"

# --- master: ledger + master team, cần 1 review ---
log_info "Cấu hình nhánh: master"
set_branch_protection "master" "$(python3 -c "
import json
print(json.dumps({
    'required_status_checks': {
        'strict': True,
        'contexts': ['ci / build', 'ci / test']
    },
    'enforce_admins': False,
    'required_pull_request_reviews': {
        'dismissal_restrictions': {
            'teams': ['master', 'ledger', 'main']
        },
        'dismiss_stale_reviews': True,
        'require_code_owner_reviews': True,
        'required_approving_review_count': 1,
        'require_last_push_approval': False
    },
    'restrictions': {
        'users': [],
        'teams': ['master', 'ledger', 'main'],
        'apps': []
    },
    'required_linear_history': True,
    'allow_force_pushes': False,
    'allow_deletions': False,
    'required_conversation_resolution': True
}))
")"

# --- dev: dev + master + ledger, cần 1 review ---
log_info "Cấu hình nhánh: dev"
set_branch_protection "dev" "$(python3 -c "
import json
print(json.dumps({
    'required_status_checks': {
        'strict': False,
        'contexts': ['ci / build']
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
        'teams': ['dev', 'master', 'ledger', 'main'],
        'apps': []
    },
    'required_linear_history': False,
    'allow_force_pushes': False,
    'allow_deletions': False,
    'required_conversation_resolution': False
}))
")"

# --- ledger: chỉ ledger + main team, không ai xóa được ---
log_info "Cấu hình nhánh: ledger"
set_branch_protection "ledger" "$(python3 -c "
import json
print(json.dumps({
    'required_status_checks': None,
    'enforce_admins': True,
    'required_pull_request_reviews': {
        'dismissal_restrictions': {
            'teams': ['ledger', 'main']
        },
        'dismiss_stale_reviews': True,
        'require_code_owner_reviews': True,
        'required_approving_review_count': 2,
        'require_last_push_approval': True
    },
    'restrictions': {
        'users': [],
        'teams': ['ledger', 'main'],
        'apps': []
    },
    'required_linear_history': True,
    'allow_force_pushes': False,
    'allow_deletions': False,
    'lock_branch': False,
    'required_conversation_resolution': True
}))
")"

# ── Bước 6: Tóm tắt ──────────────────────────────────────────────────────────
log_section "Hoàn tất — Tóm tắt cấu hình"

echo ""
echo "  Repo : https://github.com/${FULL_REPO}"
echo ""
echo "  Teams và quyền:"
echo "    dev    → push        (dev branch)"
echo "    master → maintain    (dev + master branch)"
echo "    ledger → admin       (tất cả nhánh, audit trail)"
echo "    main   → admin       (full admin)"
echo ""
echo "  Nhánh và bảo vệ:"
echo "    main   → 2 reviews required | chỉ ledger/main merge | CI bắt buộc"
echo "    master → 1 review required  | ledger/master/main merge | CI build+test"
echo "    dev    → 1 review required  | dev/master/ledger/main push | CI build"
echo "    ledger → 2 reviews required | chỉ ledger/main merge | locked history"
echo ""
echo "  Xem rules tại:"
echo "    https://github.com/${FULL_REPO}/settings/branches"
echo "    https://github.com/${ORG}/settings/teams"
echo ""
log_ok "Script hoàn tất!"
