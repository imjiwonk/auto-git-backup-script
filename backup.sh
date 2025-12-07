#!/bin/bash

# ================================================
# 자동 백업 시스템 (Git + Slack + Cron 안정 버전)
# ================================================

BASE="/home/kimji/auto-backup"

SOURCE_DIR="$BASE/source"
BACKUP_DIR="$BASE/backup"
LOG_DIR="$BASE/logs"
REPORT_DIR="$BASE/reports"

LOGFILE="$LOG_DIR/backup.log"
LOCKFILE="/tmp/auto_backup.lock"

mkdir -p "$SOURCE_DIR" "$BACKUP_DIR" "$LOG_DIR" "$REPORT_DIR"


# -------------------------------------------------
# Slack Webhook URL
# -------------------------------------------------
if [ -z "$SLACK_WEBHOOK_URL" ]; then
    SLACK_WEBHOOK_URL="https://hooks.slack.com/services/본인_URL"
fi


# -------------------------------------------------
# 중복 실행 방지
# -------------------------------------------------
if [ -e "$LOCKFILE" ]; then
    echo "[WARN] 이미 실행 중입니다."
    exit 1
fi
touch "$LOCKFILE"

cleanup() {
    rm -f "$LOCKFILE"
}
trap cleanup EXIT


# -------------------------------------------------
# 로그 출력 함수
# -------------------------------------------------
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOGFILE"
}


# -------------------------------------------------
# Slack 성공 메시지
# -------------------------------------------------
notify_slack_success() {
    TIME="$1"
    FILES="$2"
    REPORT="$3"

    curl -X POST -H "Content-Type: application/json" \
    --data "{
        \"text\": \"✅ 자동 백업 성공! 시간: $TIME\n변경된 파일:\n$FILES\n보고서: $REPORT\"
    }" \
    "$SLACK_WEBHOOK_URL" > /dev/null 2>&1
}


# -------------------------------------------------
# 🔧 Git 저장소 자동 초기화 & 동기화
# -------------------------------------------------
ensure_git_repo() {
    cd "$BACKUP_DIR"

    # .git 폴더 없으면 생성
    if [ ! -d ".git" ]; then
        log "Git 저장소가 없어 새로 초기화합니다."
        git init
        git branch -m main
        git remote add origin https://github.com/imjiwonk/auto-git-backup-script.git
    fi

    # 원격 저장소 존재 확인
    if git ls-remote origin &> /dev/null; then
        log "원격 저장소 연결 OK"
    else
        log "원격 저장소 오류! origin을 다시 설정합니다."
        git remote remove origin
        git remote add origin https://github.com/imjiwonk/auto-git-backup-script.git
    fi

    # 원격 브랜치 가져오기 (충돌나도 자동 병합)
    git pull origin main --allow-unrelated-histories --no-edit 2>/dev/null
}


# -------------------------------------------------
# 1️⃣ 백업 실행 함수
# -------------------------------------------------
run_backup() {
    log "==== AUTO BACKUP START ===="

    ensure_git_repo

    # rsync로 source → backup 복사
    CHANGED_TEXT=$(rsync -av --itemize-changes --delete "$SOURCE_DIR/" "$BACKUP_DIR/" 2>&1)

    REPORT_FILE="$REPORT_DIR/backup_$(date '+%Y-%m-%d_%H-%M-%S').txt"
    echo "$CHANGED_TEXT" > "$REPORT_FILE"

    if [ $? -ne 0 ]; then
        log "백업 실패"
        log "==== AUTO BACKUP END ===="
        return
    fi

    log "백업 진행: 성공"

    # 변경된 파일 목록 생성
    FILES=$(echo "$CHANGED_TEXT" | grep -E "^[*>c]" | sed 's/^/ - /')

    cd "$BACKUP_DIR"

    # Git 커밋 및 push
    if [ -n "$(git status --porcelain)" ]; then
        git add .
        git commit -m "Auto Backup: $(date '+%Y-%m-%d %H:%M:%S')"

        # push 실패하면 자동 pull 후 재시도
        if ! git push origin main; then
            log "push 실패 → 자동 pull 후 재시도"
            git pull origin main --allow-unrelated-histories --no-edit
            git push origin main
        fi

        log "GitHub 업로드 완료"
    else
        log "변경사항 없음 → GitHub 업로드 생략"
    fi

    notify_slack_success "$(date '+%Y-%m-%d %H:%M:%S')" "$FILES" "$REPORT_FILE"
    log "==== AUTO BACKUP END ===="
}


# -------------------------------------------------
# 최근 로그 보기
# -------------------------------------------------
show_recent() {
    echo "📌 최근 로그:"
    tail -n 50 "$LOGFILE"
}


# -------------------------------------------------
# 실행 모드
# -------------------------------------------------
case "$1" in
    "run") run_backup ;;
    "recent") show_recent ;;
    *) 
        echo "사용법:"
        echo "  ./backup.sh run     → 즉시 백업 실행"
        echo "  ./backup.sh recent  → 최근 로그 출력"
        ;;
esac

exit 0
