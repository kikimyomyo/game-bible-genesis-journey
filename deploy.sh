#!/usr/bin/env bash
# 기묘한 학습게임 배포 스크립트 (스테이징 화이트리스트 방식)
# 사용법: bash <게임-폴더>/deploy.sh <게임-폴더명> [--dry-run]
# 예:    bash bible-genesis-journey/deploy.sh bible-genesis-journey
#        bash bible-genesis-journey/deploy.sh bible-genesis-journey --dry-run   (검증만, 배포 없음)
#
# 전제 조건:
#   - gh CLI 로그인 완료 (gh auth status)
#   - wrangler 설치 및 cloudflare 로그인 (npx wrangler login)
#   - <게임-폴더명>/ 디렉터리 존재 + index.html, config.js 완성됨
#
# 배포 스테이징: wrangler는 git 추적 여부와 무관하게 디스크를 통째로 올린다
# (.assetsignore도 이 환경에서 미동작 확인됨). 배포 대상만 화이트리스트로
# 골라 임시 디렉터리에 모은 뒤 그 디렉터리를 올린다.
# --dry-run: 스테이징 단계까지만 수행하고 종료 (git/wrangler 호출 없음).

set -euo pipefail

GAME="${1:-}"
DRY_RUN=0
for arg in "$@"; do
  [[ "$arg" == "--dry-run" ]] && DRY_RUN=1
done

if [[ -z "$GAME" ]]; then
  echo "사용법: bash <게임-폴더>/deploy.sh <게임-폴더명> [--dry-run]"
  exit 1
fi

HUB="$(cd "$(dirname "$0")/.." && pwd)"
GAME_DIR="$HUB/$GAME"

if [[ ! -d "$GAME_DIR" ]]; then
  echo "폴더 없음: $GAME_DIR"
  exit 1
fi

echo "▶ 공통 JS 복사 (_shared/*.js → 게임 폴더)"
for src in "$HUB/_shared/"*.js; do
  [[ -f "$src" ]] || continue
  cp "$src" "$GAME_DIR/$(basename "$src")"
  echo "   · $(basename "$src")"
done

# assets_manifest.txt → _shared/{assets,content} 에서 게임 폴더로 복사
# 규약:
#   - src 경로는 _shared/ 기준 (예: assets/bible/12sons/*.png, content/bible/characters/*.json)
#   - dst 경로는 게임 폴더 내 assets/ 기준 (예: images/, data/characters/)
MANIFEST="$GAME_DIR/assets_manifest.txt"
if [[ -f "$MANIFEST" ]]; then
  echo "▶ assets_manifest 적용 (_shared/ → $GAME/assets)"
  while IFS= read -r line; do
    line="${line%%#*}"
    line="$(echo "$line" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
    [[ -z "$line" ]] && continue
    src_pat="$(echo "$line" | awk '{print $1}')"
    dst_rel="$(echo "$line" | awk '{print $2}')"
    [[ -z "$src_pat" || -z "$dst_rel" ]] && continue
    # 하위 호환: 'assets/' 또는 'content/' 로 시작 안 하면 'assets/' 접두 자동 추가
    if [[ "$src_pat" != assets/* && "$src_pat" != content/* ]]; then
      src_pat="assets/$src_pat"
    fi
    dst_dir="$GAME_DIR/assets/$dst_rel"
    for f in $HUB/_shared/$src_pat; do
      [[ -e "$f" ]] || continue
      if [[ "$dst_rel" == */ || ! "$dst_rel" == *.* ]]; then
        mkdir -p "$dst_dir"
        cp "$f" "$dst_dir/"
      else
        mkdir -p "$(dirname "$dst_dir")"
        cp "$f" "$dst_dir"
      fi
    done
    echo "   · $src_pat → assets/$dst_rel"
  done < "$MANIFEST"
fi

# 엔드포인트를 config.js에 주입 (PLACEHOLDER 치환)
ENDPOINT_FILE="$HUB/_shared/endpoint.txt"
ENDPOINT="$(grep -v '^#' "$ENDPOINT_FILE" | grep -v '^$' | head -1)"
if [[ "$ENDPOINT" == *PLACEHOLDER* ]]; then
  echo "⚠ _shared/endpoint.txt가 PLACEHOLDER 상태입니다. Apps Script URL로 교체해야 기록이 됩니다."
else
  perl -i -pe "s|https://script.google.com/macros/s/PLACEHOLDER/exec|$ENDPOINT|g" "$GAME_DIR/config.js"
  echo "✓ endpoint 주입 완료"
fi

# ── 배포 스테이징 (화이트리스트 방식) ────────────────────────────
# 참조되지 않는 개발용 산출물(Manim 중간파일·구버전 PNG·개인 경로가 담긴
# 설정 파일 등)이 라이브에 노출되는 것을 막기 위해, 배포 대상만 골라
# 임시 디렉터리에 모은다.

is_excluded() {
  case "$1" in
    *.py|*__pycache__*|*.pyc|*media/*|*audio_tts*|*_runtime_config.json|*_old_png*|*.wav|\
    deploy.sh|*/deploy.sh|assets_manifest.txt|*/assets_manifest.txt|_dl.sh|*/_dl.sh|\
    .gitignore|*/.gitignore|.DS_Store|*/.DS_Store|.git|.git/*|*/.git|*/.git/*|\
    .wrangler|.wrangler/*|*/.wrangler|*/.wrangler/*|*node_modules*|learning_data.json|*/learning_data.json)
      return 0 ;;
  esac
  return 1
}

STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/deploy-${GAME}.XXXXXX")"
trap 'rm -rf "$STAGING_DIR"' EXIT

stage_ref() {
  # $1 = GAME_DIR 기준 상대경로
  local rel="$1"
  is_excluded "$rel" && return 0
  local src="$GAME_DIR/$rel"
  [[ -f "$src" ]] || return 0
  local dst="$STAGING_DIR/$rel"
  mkdir -p "$(dirname "$dst")"
  cp -p "$src" "$dst"
}

# 1) 항상 포함
for f in index.html config.js tts.js sfx.js recorder.js; do
  [[ -f "$GAME_DIR/$f" ]] && stage_ref "$f"
done

# 2) assets/ 하위 전체 — 단 제외 패턴은 빼고
if [[ -d "$GAME_DIR/assets" ]]; then
  rsync -a \
    --exclude='*.py' --exclude='__pycache__/' --exclude='*.pyc' \
    --exclude='media/' --exclude='audio_tts/' --exclude='_runtime_config.json' \
    --exclude='_old_png/' --exclude='*.wav' --exclude='.DS_Store' \
    --exclude='.git/' --exclude='.wrangler/' --exclude='node_modules/' \
    --exclude='joseph-scenes/03-dreams.png' \
    "$GAME_DIR/assets/" "$STAGING_DIR/assets/"
fi

# 3) index.html이 실제 참조하는 파일 ("./경로.확장자" 형태를 grep으로 추출)
HTML_REFS=()
while IFS= read -r line; do
  [[ -n "$line" ]] && HTML_REFS+=("$line")
done < <(perl -ne 'while (/[\x27"]\.\/([^\x27"]+\.[A-Za-z0-9]+)[\x27"]/g) { print "$1\n"; }' "$GAME_DIR/index.html" 2>/dev/null | sort -u)

if [[ ${#HTML_REFS[@]} -gt 0 ]]; then
  for rel in "${HTML_REFS[@]}"; do
    stage_ref "$rel"
  done
fi

# 4) 참조된 루트급 JSON 안의 상대경로도 한 단계 더 추적 (최소 2단계)
if [[ ${#HTML_REFS[@]} -gt 0 ]]; then
  for rel in "${HTML_REFS[@]}"; do
    [[ "$rel" == *.json ]] || continue
    [[ "$rel" == assets/* ]] && continue
    json_src="$GAME_DIR/$rel"
    [[ -f "$json_src" ]] || continue
    NESTED=()
    while IFS= read -r line; do
      [[ -n "$line" ]] && NESTED+=("$line")
    done < <(perl -ne 'while (/"[A-Za-z0-9_]+"\s*:\s*"([^"]+\.[A-Za-z0-9]+)"/g) { print "$1\n"; }' "$json_src" 2>/dev/null | sort -u)
    if [[ ${#NESTED[@]} -gt 0 ]]; then
      for nrel in "${NESTED[@]}"; do
        if [[ -f "$GAME_DIR/$nrel" ]]; then
          stage_ref "$nrel"
        elif [[ -f "$GAME_DIR/assets/$nrel" ]]; then
          stage_ref "assets/$nrel"
        fi
      done
    fi
  done
fi

# ── 스테이징 요약 ────────────────────────────────────────────────
human_size() {
  awk -v b="$1" 'BEGIN {
    split("B KB MB GB TB", u, " "); i = 1
    while (b >= 1024 && i < 5) { b /= 1024; i++ }
    printf "%.1f%s", b, u[i]
  }'
}

INCLUDED_COUNT=$(find "$STAGING_DIR" -type f | wc -l | tr -d ' ')
INCLUDED_BYTES=$(find "$STAGING_DIR" -type f -exec stat -f%z {} + 2>/dev/null | awk '{s+=$1} END {print s+0}')
TOTAL_COUNT=$(find "$GAME_DIR" -type f | wc -l | tr -d ' ')
TOTAL_BYTES=$(find "$GAME_DIR" -type f -exec stat -f%z {} + 2>/dev/null | awk '{s+=$1} END {print s+0}')
EXCLUDED_COUNT=$((TOTAL_COUNT - INCLUDED_COUNT))
EXCLUDED_BYTES=$((TOTAL_BYTES - INCLUDED_BYTES))

echo ""
echo "▶ 배포 스테이징 요약: $GAME"
echo "   포함: ${INCLUDED_COUNT}개 파일, $(human_size "$INCLUDED_BYTES")"
echo "   제외: ${EXCLUDED_COUNT}개 파일, $(human_size "$EXCLUDED_BYTES")"

if [[ "$DRY_RUN" == "1" ]]; then
  echo ""
  echo "   포함 파일 목록:"
  (cd "$STAGING_DIR" && find . -type f | sed 's#^\./##' | sort) | sed 's/^/     - /'
  echo ""
  echo "✓ --dry-run: 스테이징까지만 수행함. git/wrangler 호출 없음."
  exit 0
fi

cd "$GAME_DIR"

# git init (처음 배포 시)
if [[ ! -d .git ]]; then
  echo "▶ git 저장소 초기화"
  git init -b main >/dev/null
  echo "node_modules/" > .gitignore
fi

git add -A
git commit -m "deploy: $GAME" --allow-empty >/dev/null

# GitHub repo (없으면 생성)
REPO_NAME="game-$GAME"
if ! gh repo view "$REPO_NAME" >/dev/null 2>&1; then
  echo "▶ GitHub repo 생성: $REPO_NAME"
  gh repo create "$REPO_NAME" --public --source=. --remote=origin --push
else
  echo "▶ GitHub push"
  git push origin main
fi

# Cloudflare Pages 프로젝트 (없으면 생성, 이미 있으면 무시)
echo "▶ Cloudflare Pages 프로젝트 확인/생성: $REPO_NAME"
npx wrangler pages project create "$REPO_NAME" --production-branch=main 2>&1 | grep -v "already exists" || true

# Cloudflare Pages 배포 (스테이징 디렉터리만 업로드)
echo "▶ Cloudflare Pages 배포 (스테이징: $STAGING_DIR)"
npx wrangler pages deploy "$STAGING_DIR" --project-name="$REPO_NAME" --branch=main --commit-dirty=true

echo ""
echo "✅ 배포 완료"
echo "   프로젝트: $REPO_NAME"
echo "   프로덕션 URL: https://$REPO_NAME.pages.dev"
