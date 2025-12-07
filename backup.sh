#!/bin/bash

# ================================================
# 자동 백업 시스템 (CRON 안정화 버전)
# ================================================

# 🔥 실행 기준 디렉토리 정의 (절대경로)
BASE="/home/kimji/auto-backup"

SOURCE_DIR="$BASE/source"
BACKUP_DIR="$BASE/backup"
LOG_DIR="$BASE/logs"
REPORT_DIR="$BASE/reports"

LOGFILE="$LOG_DIR/backup.log"
LOCKFILE="/tmp/auto_backup.lock"

mkdir -p "$SOURCE_DIR" "$BACKUP_DIR" "$LOG_DIR" "$REPORT_DIR"


# -------------------------------------------------
# Slack Webhook (환경변수 또는 하드코딩 가능)
# -------------------------------------------------
if [ -z "$SLACK_WEBHOOK_URL" ]; then
    SLACK_WEBHOOK_URL="https://hooks.slack.com/services/여기에_본인_WEBHOOK_URL"
fi


# -------------------------------------------------
# 🔒 중복 실행 방지
# -------------------------------------------------
if [ -e "$LOCKFILE" ]; then
    echo "[WARN] 이미 실행 중입니다."
    exit 1
fi
touch "$LOCKFILE"


# -------------------------------------------------
# 🧽 종료 시 lock 파일 제거
# -------------------------------------------------
cleanup() {
    rm -f "$LOCKFILE"
}
trap cleanup EXIT



# -------------------------------------------------
# 📝 로그 기록 함수
# -------------------------------------------------
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOGFILE"
}



# -------------------------------------------------
# 📤 Slack 성공 메시지 함수
# -------------------------------------------------
notify_slack_success() {
    TIME="$1"
    FILES="$2"
    REPORT="$3"

    curl -X POST -H "Content-Type: application/json" \
        --data "{
  \"blocks\": [
    {
      \"type\": \"header\",
      \"text\": { \"type\": \"plain_text\", \"text\": \"✅ 자동 백업 성공!\", \"emoji\": true }
    },
    {
      \"type\": \"section\",
      \"fields\": [
        { \"type\": \"mrkdwn\", \"text\": \"*🗓 시간:*\n$TIME\" }
      ]
    },
    {
      \"type\": \"section\",
      \"text\": { \"type\": \"mrkdwn\", \"text\": \"*📄 변경된 파일 목록:*\n$FILES\" }
    },
    {
      \"type\": \"section\",
      \"text\": { \"type\": \"mrkdwn\", \"text\": \"📘 *보고서:* $REPORT\" }
    }
  ]
}" \
    "$SLACK_WEBHOOK_URL" > /dev/null 2>&1
}



# -------------------------------------------------
# 1️⃣ 백업 실행
# -------------------------------------------------
run_backup() {
    log "==== AUTO BACKUP START ===="

    # 1) rsync 실행
    CHANGED_TEXT=$(rsync -av --itemize-changes --delete "$SOURCE_DIR/" "$BACKUP_DIR/" 2>&1)

    # 보고서 파일 저장
    REPORT_FILE="$REPORT_DIR/backup_$(date '+%Y-%m-%d_%H-%M-%S').txt"
    echo "$CHANGED_TEXT" > "$REPORT_FILE"

    # 2) rsync 성공 여부
    if [ $? -eq 0 ]; then
        log "백업 진행: 성공"
        echo "$CHANGED_TEXT" >> "$LOGFILE"
    else
        log "백업 진행: 실패"
        echo "$CHANGED_TEXT" >> "$LOGFILE"
        log "==== AUTO BACKUP END ===="
        return
    fi


    # 3) 🔥 GitHub 자동 커밋 & 푸시
    cd "$BACKUP_DIR"

    # Git 저장소 초기화 되어 있지 않다면 자동 생성
    if [ ! -d ".git" ]; then
        git init
        git branch -M main
        git remote add origin https://github.com/imjiwonk/auto-git-backup-script.git
    fi

    git add .

    # 변경사항 없는 경우 체크
    if git diff --cached --quiet; then
        FILES="'(변경 없음)'"
    else
        git commit -m "Auto Backup: $(date '+%Y-%m-%d %H:%M:%S')"
        git push -u origin main
        FILES=$(echo "$CHANGED_TEXT" | grep -E "^(>f|cd)" | awk '{print "- " $NF}')
    fi


    # 4) Slack 알림
    notify_slack_success "$(date '+%Y-%m-%d %H:%M:%S')" "$FILES" "$REPORT_FILE"

    log "==== AUTO BACKUP END ===="
}


# -------------------------------------------------
# 2️⃣ 최근 로그 5개 출력
# -------------------------------------------------
show_recent() {
    echo "📌 최근 백업 로그 5개"
    echo "--------------------------------------"

    mapfile -t END_LINES < <(grep -n "AUTO BACKUP END" "$LOGFILE" | tail -n 5)

    TOTAL=${#END_LINES[@]}
    echo "총 $TOTAL개의 정상 종료된 백업 중 최근 5개:"
    echo ""

    COUNT=0

    for entry in "${END_LINES[@]}"; do
        END_LINE=$(echo "$entry" | cut -d: -f1)

        START_LINE=$(sed -n "1,${END_LINE}p" "$LOGFILE" \
            | grep -n "AUTO BACKUP START" \
            | tail -n 1 | cut -d: -f1)

        COUNT=$((COUNT + 1))

        echo "#$COUNT | 로그 범위: ($START_LINE ~ $END_LINE)"
        echo "--------------------------------------"
        sed -n "${START_LINE},${END_LINE}p" "$LOGFILE"
        echo ""
    done
}



# -------------------------------------------------
# 실행 모드
# -------------------------------------------------
case "$1" in
    "run")
        run_backup
        ;;
    "recent")
        show_recent
        ;;
    *)
        echo "사용법:"
        echo "  ./backup.sh run      → 즉시 백업 실행"
        echo "  ./backup.sh recent   → 최근 5개 로그 보기"
        ;;
esac

exit 0
