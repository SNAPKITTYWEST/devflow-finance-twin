# ========================================================================
# SOVEREIGN LEVIATHAN NODE LICENSE
# License-ID: SL-AGPL3-001 | Covenant-Version: 1.0
# Copyright (C) 2026 SnapKittyWest. Ahmad Ali Parr, Bel Esprit D'Accord Irrevocable Trust.
# ========================================================================
#
# This file is a covered work under the GNU Affero General Public License,
# version 3, together with the Sovereign Leviathan additional terms.
#
# Hark, though this node be but a spark,
# Its covenant endureth through the dark.
#
# Ignorantia juris non excusat.
# ========================================================================

#!/usr/bin/env bash
set -Eeuo pipefail

###############################################################################
# publish.sh â€” Deterministic repository publisher
#
# Scans .inbox/, classifies files, organizes into repository structure,
# verifies integrity via SHA-256, stages only publication files, commits,
# and pushes.
#
# Usage:
#   ./publish.sh              Full publish pipeline
#   ./publish.sh --dry-run    Classify and show plan without commit/push
#   ./publish.sh --status     Show repository publication state
#   ./publish.sh --manifest   Display current publication manifest
#   ./publish.sh --help       Show this help
###############################################################################

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INBOX="${REPO_ROOT}/.inbox"
CONFLICT_DIR="${INBOX}/conflicts"
MANIFEST_FILE="${REPO_ROOT}/PUBLISH_MANIFEST.json"
REPORT_FILE="${REPO_ROOT}/PUBLISH_REPORT.md"

DRY_RUN=0
MODE="publish"

readonly COLOR_RED='\033[0;31m'
readonly COLOR_GREEN='\033[0;32m'
readonly COLOR_YELLOW='\033[1;33m'
readonly COLOR_CYAN='\033[0;36m'
readonly COLOR_RESET='\033[0m'

# Accumulator arrays
declare -a FILES_ADDED=()
declare -a FILES_MODIFIED=()
declare -a FILES_MOVED=()
declare -a FILES_UNCHANGED=()
declare -a FILES_CONFLICTED=()
declare -a FILES_REJECTED=()
declare -a STAGED_PATHS=()
declare -A HASH_RECORD=()

###############################################################################
# Logging
###############################################################################
log_info()  { printf "${COLOR_CYAN}[INFO]${COLOR_RESET}  %s\n" "$*"; }
log_ok()    { printf "${COLOR_GREEN}[OK]${COLOR_RESET}    %s\n" "$*"; }
log_warn()  { printf "${COLOR_YELLOW}[WARN]${COLOR_RESET}  %s\n" "$*"; }
log_error() { printf "${COLOR_RED}[ERROR]${COLOR_RESET} %s\n" "$*" >&2; }

halt_publication() {
    local reason="$1" file="${2:-}" expected="${3:-}" actual="${4:-}" remediation="${5:-}"
    echo ""
    echo "============================================"
    echo "  PUBLICATION HALTED"
    echo "============================================"
    echo "REASON:      ${reason}"
    [[ -n "${file}" ]]        && echo "FILE:        ${file}"
    [[ -n "${expected}" ]]    && echo "EXPECTED:    ${expected}"
    [[ -n "${actual}" ]]      && echo "ACTUAL:      ${actual}"
    [[ -n "${remediation}" ]] && echo "REMEDIATION: ${remediation}"
    echo "============================================"
    exit 1
}

###############################################################################
# Hashing
###############################################################################
compute_sha256() {
    local file="$1"
    sha256sum "$file" | awk '{print $1}'
}

###############################################################################
# Path safety: reject traversal attempts
###############################################################################
check_path_safety() {
    local relpath="$1"
    # Normalize and reject any component that is ".."
    local normalized
    normalized="$(printf '%s' "$relpath" | sed 's|\\|/|g')"
    if printf '%s' "$normalized" | grep -qE '(^|/)\.\.(/|$)'; then
        return 1
    fi
    # Reject absolute paths
    if printf '%s' "$normalized" | grep -qE '^(/|[A-Za-z]:)'; then
        return 1
    fi
    return 0
}

###############################################################################
# Classification: determine destination directory from file extension,
# filename, and incoming directory context.
###############################################################################
classify_file() {
    local relpath="$1"    # path relative to .inbox/
    local filename
    filename="$(basename "$relpath")"
    local ext="${filename##*.}"
    local dir_context
    dir_context="$(dirname "$relpath")"

    # Lowercase extension for matching
    ext="$(printf '%s' "$ext" | tr '[:upper:]' '[:lower:]')"

    # --- BRAID subsystem detection ---
    if printf '%s' "$relpath" | grep -qi 'braid'; then
        classify_braid "$relpath" "$filename" "$ext"
        return
    fi

    # --- Directory context hints ---
    # If the incoming path has a recognizable top-level subdirectory in .inbox/,
    # honor it when it maps to an existing repo directory.
    local top_dir
    top_dir="$(printf '%s' "$dir_context" | cut -d/ -f1)"

    case "$top_dir" in
        mathematics|math)
            classify_mathematics "$relpath" "$filename" "$ext"
            return
            ;;
        formal|proofs|verification)
            classify_formal "$relpath" "$filename" "$ext"
            return
            ;;
        graphics|images|assets)
            classify_graphics "$relpath" "$filename" "$ext"
            return
            ;;
        tests|test)
            printf 'tests/%s' "$relpath"
            return
            ;;
        docs|documentation)
            printf 'docs/%s' "$relpath"
            return
            ;;
        scripts)
            printf 'scripts/%s' "$relpath"
            return
            ;;
        examples)
            printf 'examples/%s' "$relpath"
            return
            ;;
    esac

    # --- Extension-based classification ---
    case "$ext" in
        # Ada
        adb|ads)
            printf 'ada/%s' "$relpath"
            ;;
        # APL
        apl|dyalog)
            printf 'apl/%s' "$relpath"
            ;;
        # Assembly
        asm|s)
            printf 'assembly-120-strict-model/%s' "$filename"
            ;;
        # C#
        cs)
            printf 'csharp/%s' "$relpath"
            ;;
        # COBOL
        cob|cbl|cpy)
            printf 'cobol/%s' "$relpath"
            ;;
        # Chisel / Scala
        scala)
            if printf '%s' "$relpath" | grep -qi 'chisel'; then
                printf 'chisel/%s' "$filename"
            else
                printf 'scala/%s' "$relpath"
            fi
            ;;
        # CUDA / PTX
        cu)
            printf 'src/%s' "$relpath"
            ;;
        ptx)
            printf 'ptx/%s' "$filename"
            ;;
        # Eclipse
        ecl)
            printf 'eclipse/%s' "$relpath"
            ;;
        # Futhark
        fut)
            printf 'src/%s' "$relpath"
            ;;
        # Go
        go)
            printf 'src/%s' "$relpath"
            ;;
        # Haskell
        hs|lhs)
            printf 'haskell/%s' "$relpath"
            ;;
        # Header files
        h|hpp)
            printf 'src/%s' "$relpath"
            ;;
        # Java
        java)
            printf 'src/%s' "$relpath"
            ;;
        # JavaScript / TypeScript
        js|jsx)
            if printf '%s' "$relpath" | grep -qi 'wasm\|compile'; then
                printf 'wasm/%s' "$filename"
            else
                printf 'src/%s' "$relpath"
            fi
            ;;
        ts|tsx)
            printf 'frontend/%s' "$relpath"
            ;;
        # Lean
        lean)
            printf 'lean/%s' "$relpath"
            ;;
        # Lisp / Scheme / Clojure
        lisp|cl|el|scm|clj|cljs|edn)
            printf 'lisp/%s' "$relpath"
            ;;
        # Logtalk
        lgt)
            printf 'logtalk/%s' "$relpath"
            ;;
        # Pascal
        pas|pp)
            printf 'src/%s' "$relpath"
            ;;
        # PL/I
        pli|pl1)
            printf 'pli/%s' "$relpath"
            ;;
        # Prolog
        pl|pro)
            if printf '%s' "$relpath" | grep -qi 'prolog'; then
                printf 'prolog/%s' "$filename"
            else
                printf 'prolog/%s' "$relpath"
            fi
            ;;
        # Python
        py)
            printf 'src/%s' "$relpath"
            ;;
        # RPG
        rpgle|rpg)
            printf 'rpgle/%s' "$relpath"
            ;;
        # Rust
        rs)
            classify_rust "$relpath" "$filename"
            ;;
        # WASM
        wasm|wat)
            printf 'wasm/%s' "$filename"
            ;;
        # x86_64 assembly
        x86|x86_64)
            printf 'x86_64/%s' "$filename"
            ;;
        # Zig
        zig)
            printf 'src/%s' "$relpath"
            ;;
        # C/C++
        c|cpp|cc|cxx)
            printf 'src/%s' "$relpath"
            ;;
        # Markdown
        md)
            printf 'docs/%s' "$relpath"
            ;;
        # Graphics
        svg|png|jpg|jpeg|gif|bmp|webp|ico)
            classify_graphics "$relpath" "$filename" "$ext"
            ;;
        # Config / Data
        json)
            printf 'config-or-data/%s' "$relpath"
            ;;
        yaml|yml)
            printf 'config/%s' "$relpath"
            ;;
        toml)
            printf 'config/%s' "$relpath"
            ;;
        # Shell scripts
        sh|bash)
            printf 'scripts/%s' "$relpath"
            ;;
        # Docker
        dockerfile)
            printf '%s' "$filename"
            ;;
        # Makefiles and build files
        mk)
            printf 'scripts/%s' "$filename"
            ;;
        # Agda
        agda)
            printf 'formal-token-verification/agda/%s' "$relpath"
            ;;
        # Coq
        v)
            printf 'formal-token-verification/coq/%s' "$relpath"
            ;;
        # F*
        fst|fsti)
            printf 'formal-token-verification/fstar/%s' "$relpath"
            ;;
        # Datalog
        dl)
            printf 'datalog-engine/%s' "$relpath"
            ;;
        # Fallback: preserve the incoming relative path under src/
        *)
            if [[ "$filename" == "Makefile" || "$filename" == "Dockerfile" || "$filename" == "Cargo.toml" || "$filename" == "Cargo.lock" ]]; then
                printf '%s' "$relpath"
            else
                printf 'src/%s' "$relpath"
            fi
            ;;
    esac
}

###############################################################################
# Sub-classifiers
###############################################################################
classify_braid() {
    local relpath="$1" filename="$2" ext="$3"
    local lower_path
    lower_path="$(printf '%s' "$relpath" | tr '[:upper:]' '[:lower:]')"

    local braid_sub="braid"
    if printf '%s' "$lower_path" | grep -q 'algebra'; then
        braid_sub="braid/algebra"
    elif printf '%s' "$lower_path" | grep -q 'group'; then
        braid_sub="braid/groups"
    elif printf '%s' "$lower_path" | grep -q 'generator'; then
        braid_sub="braid/generators"
    elif printf '%s' "$lower_path" | grep -q 'word'; then
        braid_sub="braid/words"
    elif printf '%s' "$lower_path" | grep -q 'relation'; then
        braid_sub="braid/relations"
    elif printf '%s' "$lower_path" | grep -q 'normal'; then
        braid_sub="braid/normalization"
    elif printf '%s' "$lower_path" | grep -q 'represent'; then
        braid_sub="braid/representations"
    elif printf '%s' "$lower_path" | grep -q 'visual\|render\|draw\|plot'; then
        braid_sub="braid/visualization"
    elif printf '%s' "$lower_path" | grep -q 'test'; then
        braid_sub="braid/tests"
    fi

    printf '%s/%s' "$braid_sub" "$filename"
}

classify_mathematics() {
    local relpath="$1" filename="$2" ext="$3"
    local lower_path
    lower_path="$(printf '%s' "$relpath" | tr '[:upper:]' '[:lower:]')"

    local math_sub="mathematics"
    if printf '%s' "$lower_path" | grep -q 'algebra'; then
        math_sub="mathematics/algebra"
    elif printf '%s' "$lower_path" | grep -q 'topology'; then
        math_sub="mathematics/topology"
    elif printf '%s' "$lower_path" | grep -q 'group'; then
        math_sub="mathematics/groups"
    elif printf '%s' "$lower_path" | grep -q 'braid'; then
        math_sub="mathematics/braid"
    elif printf '%s' "$lower_path" | grep -q 'proof'; then
        math_sub="mathematics/proofs"
    elif printf '%s' "$lower_path" | grep -q 'research'; then
        math_sub="mathematics/research"
    fi

    printf '%s/%s' "$math_sub" "$filename"
}

classify_formal() {
    local relpath="$1" filename="$2" ext="$3"
    case "$ext" in
        lean)   printf 'lean/%s' "$relpath" ;;
        agda)   printf 'formal-token-verification/agda/%s' "$relpath" ;;
        v)      printf 'formal-token-verification/coq/%s' "$relpath" ;;
        fst|fsti) printf 'formal-token-verification/fstar/%s' "$relpath" ;;
        *)      printf 'formal-token-verification/%s' "$relpath" ;;
    esac
}

classify_graphics() {
    local relpath="$1" filename="$2" ext="$3"
    local lower_path
    lower_path="$(printf '%s' "$relpath" | tr '[:upper:]' '[:lower:]')"

    local gfx_sub="assets"
    if printf '%s' "$lower_path" | grep -q 'architect'; then
        gfx_sub="assets/architecture"
    elif printf '%s' "$lower_path" | grep -q 'braid'; then
        gfx_sub="assets/braid"
    elif printf '%s' "$lower_path" | grep -q 'math'; then
        gfx_sub="assets/mathematics"
    elif printf '%s' "$lower_path" | grep -q 'verif'; then
        gfx_sub="assets/verification"
    elif printf '%s' "$lower_path" | grep -q 'diagram'; then
        gfx_sub="assets/diagrams"
    elif printf '%s' "$lower_path" | grep -q 'screenshot'; then
        gfx_sub="assets/screenshots"
    fi

    printf '%s/%s' "$gfx_sub" "$filename"
}

classify_rust() {
    local relpath="$1" filename="$2"
    local lower_path
    lower_path="$(printf '%s' "$relpath" | tr '[:upper:]' '[:lower:]')"

    # Check if it belongs to an existing Rust sub-project
    if printf '%s' "$lower_path" | grep -q 'fsl\|finance'; then
        printf 'rust/fsl/src/%s' "$filename"
    elif printf '%s' "$lower_path" | grep -q 'cobalt'; then
        printf 'cobalt-compiler/src/%s' "$filename"
    else
        printf 'rust/%s' "$relpath"
    fi
}

###############################################################################
# Collision detection
###############################################################################
handle_collision() {
    local src_file="$1" dest_file="$2" src_relpath="$3"

    local src_hash dest_hash
    src_hash="$(compute_sha256 "$src_file")"
    dest_hash="$(compute_sha256 "$dest_file")"

    if [[ "$src_hash" == "$dest_hash" ]]; then
        # Identical â€” no-op
        FILES_UNCHANGED+=("$src_relpath -> $(realpath --relative-to="$REPO_ROOT" "$dest_file" 2>/dev/null || printf '%s' "$dest_file") [IDENTICAL]")
        HASH_RECORD["$src_relpath"]="${src_hash}:${dest_hash}:UNCHANGED"
        return 0
    else
        # Conflict â€” move to conflicts dir
        mkdir -p "$CONFLICT_DIR"
        local conflict_name
        conflict_name="$(basename "$dest_file")"
        local conflict_path="${CONFLICT_DIR}/${conflict_name}"

        # Avoid overwriting existing conflicts
        local i=1
        while [[ -e "$conflict_path" ]]; do
            conflict_path="${CONFLICT_DIR}/${conflict_name%.${conflict_name##*.}}.conflict-${i}.${conflict_name##*.}"
            ((i++))
        done

        cp -- "$src_file" "$conflict_path"

        local dest_rel
        dest_rel="$(realpath --relative-to="$REPO_ROOT" "$dest_file" 2>/dev/null || printf '%s' "$dest_file")"

        FILES_CONFLICTED+=("CONFLICT: $src_relpath -> $dest_rel | SRC_HASH=$src_hash DEST_HASH=$dest_hash")
        HASH_RECORD["$src_relpath"]="${src_hash}:${dest_hash}:CONFLICT"

        log_warn "CONFLICT detected"
        echo "  SOURCE:           $src_relpath"
        echo "  DESTINATION:      $dest_rel"
        echo "  SOURCE HASH:      $src_hash"
        echo "  DESTINATION HASH: $dest_hash"
        echo "  CONFLICT COPY:    $(realpath --relative-to="$REPO_ROOT" "$conflict_path" 2>/dev/null || printf '%s' "$conflict_path")"

        return 1
    fi
}

###############################################################################
# Copy with hash verification
###############################################################################
verified_copy() {
    local src_file="$1" dest_file="$2" src_relpath="$3"

    local src_hash
    src_hash="$(compute_sha256 "$src_file")"

    local dest_dir
    dest_dir="$(dirname "$dest_file")"
    mkdir -p "$dest_dir"

    cp -- "$src_file" "$dest_file"

    local dest_hash
    dest_hash="$(compute_sha256 "$dest_file")"

    if [[ "$src_hash" != "$dest_hash" ]]; then
        halt_publication \
            "Hash verification failed after copy" \
            "$src_relpath" \
            "$src_hash" \
            "$dest_hash" \
            "Re-run publish or check disk integrity"
    fi

    HASH_RECORD["$src_relpath"]="${src_hash}:${dest_hash}:COPIED"
    return 0
}

###############################################################################
# Discover all files in .inbox/
###############################################################################
discover_files() {
    if [[ ! -d "$INBOX" ]]; then
        log_error "No .inbox/ directory found at ${INBOX}"
        echo "Create .inbox/ and place completed artifacts there."
        exit 1
    fi

    local count
    count="$(find "$INBOX" -type f ! -path "${CONFLICT_DIR}/*" 2>/dev/null | wc -l)"
    count="$(printf '%s' "$count" | tr -d '[:space:]')"

    if [[ "$count" -eq 0 ]]; then
        log_info "No files found in .inbox/"
        echo "Nothing to publish."
        exit 0
    fi

    log_info "Discovered ${count} file(s) in .inbox/"
}

###############################################################################
# Main processing loop
###############################################################################
process_inbox() {
    local had_conflicts=0

    while IFS= read -r -d '' src_file; do
        # Get path relative to .inbox/
        local relpath="${src_file#${INBOX}/}"

        # Skip conflicts directory
        if printf '%s' "$relpath" | grep -q '^conflicts/'; then
            continue
        fi

        # Path safety check
        if ! check_path_safety "$relpath"; then
            FILES_REJECTED+=("$relpath [PATH TRAVERSAL REJECTED]")
            log_error "REJECTED (path traversal): $relpath"
            continue
        fi

        # Check readability
        if [[ ! -r "$src_file" ]]; then
            FILES_REJECTED+=("$relpath [UNREADABLE]")
            log_error "REJECTED (unreadable): $relpath"
            continue
        fi

        # Classify
        local dest_relpath
        dest_relpath="$(classify_file "$relpath")"

        # Clean up double slashes and leading dots
        dest_relpath="$(printf '%s' "$dest_relpath" | sed 's|/\+|/|g; s|^\./||')"

        # Final path safety on destination
        if ! check_path_safety "$dest_relpath"; then
            FILES_REJECTED+=("$relpath -> $dest_relpath [DESTINATION PATH UNSAFE]")
            log_error "REJECTED (unsafe destination): $relpath -> $dest_relpath"
            continue
        fi

        local dest_file="${REPO_ROOT}/${dest_relpath}"
        local src_hash
        src_hash="$(compute_sha256 "$src_file")"
        local classification
        classification="$(printf '%s' "$dest_relpath" | cut -d/ -f1)"

        if [[ "$DRY_RUN" -eq 1 ]]; then
            local action="ADD"
            if [[ -e "$dest_file" ]]; then
                local existing_hash
                existing_hash="$(compute_sha256 "$dest_file")"
                if [[ "$src_hash" == "$existing_hash" ]]; then
                    action="UNCHANGED"
                else
                    action="CONFLICT"
                fi
            fi

            echo ""
            echo ".inbox/${relpath}"
            echo "    ->"
            echo "${dest_relpath}"
            echo ""
            echo "classification: ${classification}"
            echo "sha256: ${src_hash}"
            echo "action: ${action}"
            echo "---"
            continue
        fi

        # Check for collision
        if [[ -e "$dest_file" ]]; then
            if handle_collision "$src_file" "$dest_file" "$relpath"; then
                # Identical â€” skip
                log_ok "UNCHANGED: ${relpath} (identical to ${dest_relpath})"
            else
                # Conflict â€” was handled
                had_conflicts=1
            fi
            continue
        fi

        # Copy with verification
        verified_copy "$src_file" "$dest_file" "$relpath"
        FILES_ADDED+=("${dest_relpath}")
        STAGED_PATHS+=("${dest_relpath}")
        log_ok "ADD: .inbox/${relpath} -> ${dest_relpath}"

    done < <(find "$INBOX" -type f -print0 2>/dev/null | sort -z)

    if [[ "$had_conflicts" -gt 0 ]]; then
        log_warn "Conflicts detected. Review .inbox/conflicts/ before re-running."
    fi
}

###############################################################################
# Generate manifest
###############################################################################
generate_manifest() {
    local timestamp branch commit_before
    timestamp="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    branch="$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")"
    commit_before="$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null || echo "none")"

    local files_added_json files_modified_json files_unchanged_json files_conflicted_json files_rejected_json sha256_json

    files_added_json="$(printf '%s\n' "${FILES_ADDED[@]+"${FILES_ADDED[@]}"}" | awk 'NF{printf "    \"%s\",\n", $0}' | sed '$ s/,$//')"
    files_modified_json="$(printf '%s\n' "${FILES_MODIFIED[@]+"${FILES_MODIFIED[@]}"}" | awk 'NF{printf "    \"%s\",\n", $0}' | sed '$ s/,$//')"
    files_unchanged_json="$(printf '%s\n' "${FILES_UNCHANGED[@]+"${FILES_UNCHANGED[@]}"}" | awk 'NF{printf "    \"%s\",\n", $0}' | sed '$ s/,$//')"
    files_conflicted_json="$(printf '%s\n' "${FILES_CONFLICTED[@]+"${FILES_CONFLICTED[@]}"}" | awk 'NF{printf "    \"%s\",\n", $0}' | sed '$ s/,$//')"
    files_rejected_json="$(printf '%s\n' "${FILES_REJECTED[@]+"${FILES_REJECTED[@]}"}" | awk 'NF{printf "    \"%s\",\n", $0}' | sed '$ s/,$//')"

    # Build sha256 entries
    sha256_json=""
    for key in "${!HASH_RECORD[@]}"; do
        local val="${HASH_RECORD[$key]}"
        local src_h dest_h status
        src_h="$(printf '%s' "$val" | cut -d: -f1)"
        dest_h="$(printf '%s' "$val" | cut -d: -f2)"
        status="$(printf '%s' "$val" | cut -d: -f3)"
        sha256_json+="$(printf '    {\"file\": \"%s\", \"source_hash\": \"%s\", \"destination_hash\": \"%s\", \"status\": \"%s\"},\n' "$key" "$src_h" "$dest_h" "$status")"
    done
    sha256_json="$(printf '%s' "$sha256_json" | sed '$ s/,$//')"

    cat > "$MANIFEST_FILE" <<MANIFEST_EOF
{
  "timestamp": "${timestamp}",
  "repository": "$(git -C "$REPO_ROOT" remote get-url origin 2>/dev/null || echo "local")",
  "branch": "${branch}",
  "commit_before": "${commit_before}",
  "commit_after": "PENDING",
  "files_added": [
${files_added_json}
  ],
  "files_modified": [
${files_modified_json}
  ],
  "files_moved": [],
  "files_unchanged": [
${files_unchanged_json}
  ],
  "files_conflicted": [
${files_conflicted_json}
  ],
  "files_rejected": [
${files_rejected_json}
  ],
  "sha256": [
${sha256_json}
  ]
}
MANIFEST_EOF

    log_ok "Manifest written to PUBLISH_MANIFEST.json"
}

###############################################################################
# Generate report
###############################################################################
generate_report() {
    local timestamp
    timestamp="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

    cat > "$REPORT_FILE" <<REPORT_EOF
# Publication Report

**Timestamp:** ${timestamp}
**Branch:** $(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")

## Summary

| Category | Count |
|----------|-------|
| Files Discovered | $(( ${#FILES_ADDED[@]} + ${#FILES_MODIFIED[@]} + ${#FILES_UNCHANGED[@]} + ${#FILES_CONFLICTED[@]} + ${#FILES_REJECTED[@]} )) |
| Files Added | ${#FILES_ADDED[@]} |
| Files Modified | ${#FILES_MODIFIED[@]} |
| Files Unchanged | ${#FILES_UNCHANGED[@]} |
| Files Conflicted | ${#FILES_CONFLICTED[@]} |
| Files Rejected | ${#FILES_REJECTED[@]} |

## Files Added
REPORT_EOF

    if [[ ${#FILES_ADDED[@]} -gt 0 ]]; then
        for f in "${FILES_ADDED[@]}"; do
            echo "- \`${f}\`" >> "$REPORT_FILE"
        done
    else
        echo "_None_" >> "$REPORT_FILE"
    fi

    cat >> "$REPORT_FILE" <<REPORT_EOF

## Files Unchanged
REPORT_EOF

    if [[ ${#FILES_UNCHANGED[@]} -gt 0 ]]; then
        for f in "${FILES_UNCHANGED[@]}"; do
            echo "- \`${f}\`" >> "$REPORT_FILE"
        done
    else
        echo "_None_" >> "$REPORT_FILE"
    fi

    cat >> "$REPORT_FILE" <<REPORT_EOF

## Files Conflicted
REPORT_EOF

    if [[ ${#FILES_CONFLICTED[@]} -gt 0 ]]; then
        for f in "${FILES_CONFLICTED[@]}"; do
            echo "- \`${f}\`" >> "$REPORT_FILE"
        done
    else
        echo "_None_" >> "$REPORT_FILE"
    fi

    cat >> "$REPORT_FILE" <<REPORT_EOF

## Files Rejected
REPORT_EOF

    if [[ ${#FILES_REJECTED[@]} -gt 0 ]]; then
        for f in "${FILES_REJECTED[@]}"; do
            echo "- \`${f}\`" >> "$REPORT_FILE"
        done
    else
        echo "_None_" >> "$REPORT_FILE"
    fi

    echo "" >> "$REPORT_FILE"
    echo "## Commit" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    echo "## Push Status" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"

    log_ok "Report written to PUBLISH_REPORT.md"
}

###############################################################################
# Git safety: check for pre-existing changes
###############################################################################
git_safety_check() {
    log_info "Checking repository state..."

    local status_output
    status_output="$(git -C "$REPO_ROOT" status --short 2>/dev/null || true)"

    if [[ -n "$status_output" ]]; then
        log_warn "Pre-existing uncommitted changes detected:"
        echo "$status_output"
        echo ""
        log_info "Publication will stage ONLY inbox-originated files."
    fi
}

###############################################################################
# Git staging: stage only publication files
###############################################################################
git_stage() {
    if [[ ${#STAGED_PATHS[@]} -eq 0 ]]; then
        log_info "No new files to stage."
        return 1
    fi

    log_info "Staging ${#STAGED_PATHS[@]} file(s)..."

    # Also stage manifest and report
    STAGED_PATHS+=("PUBLISH_MANIFEST.json" "PUBLISH_REPORT.md")

    for path in "${STAGED_PATHS[@]}"; do
        git -C "$REPO_ROOT" add -- "$path"
    done

    log_ok "Staged ${#STAGED_PATHS[@]} file(s)"
    return 0
}

###############################################################################
# Generate commit message from manifest
###############################################################################
generate_commit_message() {
    local count=${#FILES_ADDED[@]}
    local categories=()

    for f in "${FILES_ADDED[@]}"; do
        local cat
        cat="$(printf '%s' "$f" | cut -d/ -f1)"
        local found=0
        for c in "${categories[@]+"${categories[@]}"}"; do
            if [[ "$c" == "$cat" ]]; then
                found=1
                break
            fi
        done
        if [[ "$found" -eq 0 ]]; then
            categories+=("$cat")
        fi
    done

    local cat_str
    cat_str="$(printf '%s, ' "${categories[@]+"${categories[@]}"}" | sed 's/, $//')"

    if [[ "$count" -eq 1 ]]; then
        printf 'publish: add %s to %s' "$(basename "${FILES_ADDED[0]}")" "$cat_str"
    elif [[ ${#categories[@]} -eq 1 ]]; then
        printf 'publish: add %d artifacts to %s' "$count" "$cat_str"
    else
        printf 'publish: ingest %d artifacts across %s' "$count" "$cat_str"
    fi
}

###############################################################################
# Git commit
###############################################################################
git_commit() {
    local msg
    msg="$(generate_commit_message)"

    log_info "Committing: ${msg}"
    git -C "$REPO_ROOT" commit -m "$msg"

    local commit_hash
    commit_hash="$(git -C "$REPO_ROOT" rev-parse HEAD)"

    # Update manifest with commit hash
    if [[ -f "$MANIFEST_FILE" ]]; then
        sed -i "s/\"commit_after\": \"PENDING\"/\"commit_after\": \"${commit_hash}\"/" "$MANIFEST_FILE"
        git -C "$REPO_ROOT" add -- "PUBLISH_MANIFEST.json"
        git -C "$REPO_ROOT" commit --amend --no-edit
    fi

    # Update report
    if [[ -f "$REPORT_FILE" ]]; then
        sed -i "s/^## Commit$/## Commit\n\n\`${commit_hash}\`/" "$REPORT_FILE"
    fi

    log_ok "Committed: ${commit_hash}"
}

###############################################################################
# Git push
###############################################################################
git_push() {
    local branch
    branch="$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD)"
    local remote="origin"

    log_info "Pushing to ${remote}/${branch}..."

    if git -C "$REPO_ROOT" push "$remote" "$branch" 2>&1; then
        log_ok "Push succeeded"

        # Update report
        if [[ -f "$REPORT_FILE" ]]; then
            sed -i "s/^## Push Status$/## Push Status\n\n**SUCCESS** â€” pushed to ${remote}\/${branch}/" "$REPORT_FILE"
        fi
    else
        local commit_hash
        commit_hash="$(git -C "$REPO_ROOT" rev-parse HEAD)"
        echo ""
        echo "============================================"
        echo "  PUSH FAILED"
        echo "============================================"
        echo "REMOTE:       ${remote}"
        echo "BRANCH:       ${branch}"
        echo "COMMIT:       ${commit_hash}"
        echo "LOCAL STATUS: commit preserved locally"
        echo "============================================"
        echo ""
        echo "The commit is intact. Resolve the push issue and retry:"
        echo "  git push ${remote} ${branch}"

        if [[ -f "$REPORT_FILE" ]]; then
            sed -i "s/^## Push Status$/## Push Status\n\n**FAILED** â€” commit preserved locally at \`${commit_hash}\`/" "$REPORT_FILE"
        fi

        return 1
    fi
}

###############################################################################
# Final verification
###############################################################################
final_verification() {
    log_info "Running final verification..."

    echo ""
    echo "--- git status ---"
    git -C "$REPO_ROOT" status --short
    echo ""
    echo "--- git log -1 ---"
    git -C "$REPO_ROOT" log -1 --oneline
    echo ""
    echo "--- git remote -v ---"
    git -C "$REPO_ROOT" remote -v
    echo ""

    # Verify all added files exist
    local missing=0
    for f in "${FILES_ADDED[@]+"${FILES_ADDED[@]}"}"; do
        if [[ ! -e "${REPO_ROOT}/${f}" ]]; then
            log_error "MISSING after publication: ${f}"
            missing=1
        fi
    done

    if [[ "$missing" -eq 1 ]]; then
        halt_publication "Post-publication verification failed: files missing" "" "" "" "Check file system and re-run"
    fi

    log_ok "Final verification passed"
}

###############################################################################
# Clean inbox after successful publication
###############################################################################
clean_inbox() {
    if [[ ${#FILES_ADDED[@]} -eq 0 ]]; then
        return
    fi

    log_info "Cleaning successfully published files from .inbox/..."

    while IFS= read -r -d '' src_file; do
        local relpath="${src_file#${INBOX}/}"
        if printf '%s' "$relpath" | grep -q '^conflicts/'; then
            continue
        fi

        local dest_relpath
        dest_relpath="$(classify_file "$relpath")"
        dest_relpath="$(printf '%s' "$dest_relpath" | sed 's|/\+|/|g; s|^\./||')"

        local dest_file="${REPO_ROOT}/${dest_relpath}"
        if [[ -e "$dest_file" ]]; then
            local src_hash dest_hash
            src_hash="$(compute_sha256 "$src_file")"
            dest_hash="$(compute_sha256 "$dest_file")"
            if [[ "$src_hash" == "$dest_hash" ]]; then
                rm -- "$src_file"
            fi
        fi
    done < <(find "$INBOX" -type f -print0 2>/dev/null | sort -z)

    # Remove empty directories in inbox (but not .inbox itself or conflicts)
    find "$INBOX" -mindepth 1 -type d -not -path "${CONFLICT_DIR}" -not -path "${CONFLICT_DIR}/*" -empty -delete 2>/dev/null || true

    log_ok "Inbox cleaned"
}

###############################################################################
# --status command
###############################################################################
show_status() {
    echo "=== Repository Publication Status ==="
    echo ""
    echo "Repository: $(git -C "$REPO_ROOT" remote get-url origin 2>/dev/null || echo "local")"
    echo "Branch:     $(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")"
    echo "HEAD:       $(git -C "$REPO_ROOT" rev-parse --short HEAD 2>/dev/null || echo "none")"
    echo ""

    if [[ -d "$INBOX" ]]; then
        local inbox_count
        inbox_count="$(find "$INBOX" -type f ! -path "${CONFLICT_DIR}/*" 2>/dev/null | wc -l)"
        inbox_count="$(printf '%s' "$inbox_count" | tr -d '[:space:]')"
        echo "Inbox:      ${inbox_count} file(s) pending"

        if [[ -d "$CONFLICT_DIR" ]]; then
            local conflict_count
            conflict_count="$(find "$CONFLICT_DIR" -type f 2>/dev/null | wc -l)"
            conflict_count="$(printf '%s' "$conflict_count" | tr -d '[:space:]')"
            echo "Conflicts:  ${conflict_count} file(s)"
        fi
    else
        echo "Inbox:      not created (.inbox/ does not exist)"
    fi

    echo ""
    echo "Working tree:"
    git -C "$REPO_ROOT" status --short
    echo ""

    if [[ -f "$MANIFEST_FILE" ]]; then
        echo "Last manifest: $(date -r "$MANIFEST_FILE" 2>/dev/null || echo "exists")"
    else
        echo "Last manifest: none"
    fi
}

###############################################################################
# --manifest command
###############################################################################
show_manifest() {
    if [[ -f "$MANIFEST_FILE" ]]; then
        cat "$MANIFEST_FILE"
    else
        echo "No manifest found. Run ./publish.sh to generate one."
    fi
}

###############################################################################
# --help
###############################################################################
show_help() {
    cat <<'HELP_EOF'
publish.sh â€” Deterministic Repository Publisher

USAGE
  ./publish.sh              Scan .inbox/, classify, organize, verify, commit, push
  ./publish.sh --dry-run    Show classification plan without modifying repository
  ./publish.sh --status     Display repository and inbox state
  ./publish.sh --manifest   Display the current publication manifest (JSON)
  ./publish.sh --help       Show this help

WORKFLOW
  1. Place completed artifacts into .inbox/
  2. Run ./publish.sh (or --dry-run to preview)
  3. Publisher discovers, classifies, and copies files to canonical locations
  4. SHA-256 hashes verified after every copy
  5. Only publication files are staged (not unrelated working-tree changes)
  6. Deterministic commit message generated from manifest
  7. Push to configured remote

COLLISION HANDLING
  If a destination file already exists:
    - Identical content: no-op (idempotent)
    - Different content: source copy placed in .inbox/conflicts/ with hash report

CLASSIFICATION
  Files are classified by extension, directory context, and content domain:
    *.rs     -> rust/         *.lean   -> lean/
    *.py     -> src/          *.hs     -> haskell/
    *.ts     -> frontend/     *.adb    -> ada/
    *.md     -> docs/         *.svg    -> assets/
    *.json   -> config-or-data/
    (and many more â€” see classify_file() in script)

  Braid-related files route to braid/ subdirectories.
  Mathematics files route to mathematics/ subdirectories.
  Formal verification files route to their proof system directories.

PATH SAFETY
  Rejects paths containing "../" or absolute path escapes.
  Never executes incoming files.

OUTPUTS
  PUBLISH_MANIFEST.json   Machine-readable publication record
  PUBLISH_REPORT.md       Human-readable publication summary
HELP_EOF
}

###############################################################################
# MAIN
###############################################################################
main() {
    # Parse arguments
    case "${1:-}" in
        --dry-run)
            DRY_RUN=1
            MODE="dry-run"
            ;;
        --status)
            show_status
            exit 0
            ;;
        --manifest)
            show_manifest
            exit 0
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        "")
            ;; # default: full publish
        *)
            log_error "Unknown option: $1"
            echo "Run ./publish.sh --help for usage."
            exit 1
            ;;
    esac

    echo "============================================"
    echo "  REPOSITORY PUBLISHER"
    if [[ "$DRY_RUN" -eq 1 ]]; then
        echo "  MODE: DRY RUN"
    else
        echo "  MODE: PUBLISH"
    fi
    echo "============================================"
    echo ""

    # Step 1: Discover
    discover_files

    # Step 2: Git safety check
    if [[ "$DRY_RUN" -eq 0 ]]; then
        git_safety_check
    fi

    # Step 3: Process (classify, resolve, check collisions, hash, copy)
    process_inbox

    if [[ "$DRY_RUN" -eq 1 ]]; then
        echo ""
        echo "============================================"
        echo "  DRY RUN COMPLETE â€” no changes made"
        echo "============================================"
        exit 0
    fi

    # Step 4: Generate manifest and report
    generate_manifest
    generate_report

    # Step 5: Stage
    if ! git_stage; then
        log_info "Nothing new to publish."
        echo ""
        echo "============================================"
        echo "  NO CHANGES â€” nothing to commit"
        echo "============================================"
        exit 0
    fi

    # Step 6: Commit
    git_commit

    # Step 7: Push
    git_push || true

    # Step 8: Final verification
    final_verification

    # Step 9: Clean inbox
    clean_inbox

    echo ""
    echo "============================================"
    echo "  PUBLICATION COMPLETE"
    echo "============================================"
}

main "$@"
