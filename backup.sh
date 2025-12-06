#!/bin/bash
cd /home/kimji/auto-backup

# ===============================
#  Slack 알림 함수
# ===============================
notify_slack() {
    MESSAGE="$1"

    # 실행 시점에 환경 변수 읽기
    WEBHOOK_URL="${SLACK_WEBHOOK_URL}"

    if [ -z "$WEBHOOK_URL" ]; then
        echo "[INFO] SLACK_WEBHOOK_URL 없음 → Slack 알림 생략"
        return
    fi

    # Slack에서 줄바꿈과 특수문자가 깨지지 않도록 printf 사용
    PAYLOAD=$(printf '{"text": "%s"}' "$MESSAGE")

    curl -X POST -H 'Content-type: application/json' \
        --data "$PAYLOAD" \
        "$WEBHOOK_URL" > /dev/null 2>&1
}

# ===============================
#  최근 백업 로그 보기 기능
# ===============================
show_recent() {
    echo "📌 최근 백업 로그 5개"
    echo "----------------------------------"

    LOG_FILE="logs/backup.log"

    mapfile -t STARTS < <(grep -n "AUTO BACKUP START" "$LOG_FILE" | awk -F: '{print $1}')
    mapfile -t ENDS < <(grep -n "AUTO BACKUP END" "$LOG_FILE" | awk -F: '{print $1}')

    if [ ${#STARTS[@]} -eq 0 ]; then
        echo "⚠ 기록된 백업 로그가 없습니다."
        exit 0
    fi

    COUNT=${#STARTS[@]}
    echo "총 $COUNT개의 백업 중 최근 5개 출력:"
    echo ""

    for ((i = COUNT - 1; i >= COUNT - 5 && i >= 0; i--)); do
        S=${STARTS[$i]}
        E=${ENDS[$i]}

        echo "===== #$((i+1)) 번째 백업 ====="
        sed -n "${S},${E}p" "$LOG_FILE"
        echo ""
    done
}

# recent 명령
if [ "$1" = "recent" ]; then
    show_recent
    exit 0
fi

# ===============================
# 필수 디렉토리 생성
# ===============================
mkdir -p logs reports scripts notes

LOG_FILE="logs/backup.log"
TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")

echo "[$TIMESTAMP] ==== AUTO BACKUP START ====" >> "$LOG_FILE"

# ===============================
# Git 변경 확인
# ===============================
STATUS=$(git status --porcelain)

if [ -z "$STATUS" ]; then
    echo "[$TIMESTAMP] 변경 사항 없음. 백업 종료." | tee -a "$LOG_FILE"
    exit 0
fi

# ===============================
# 변경 로그 생성
# ===============================
REPORT_PATH=$(./generate_report.sh)
echo "변경 로그 생성 완료 → $REPORT_PATH"

# ===============================
# Commit
# ===============================
git add .
git commit -m "Auto Backup : $TIMESTAMP" >> "$LOG_FILE" 2>&1

if [ $? -ne 0 ]; then
    echo "[$TIMESTAMP] Commit 실패" | tee -a "$LOG_FILE"
    notify_slack "❌ 자동 백업 실패 — Commit 오류 발생!"
    exit 1
fi

echo "[$TIMESTAMP] Commit 완료" >> "$LOG_FILE"

# ===============================
# Pull (rebase)
# ===============================
git pull --rebase >> "$LOG_FILE" 2>&1

if [ $? -ne 0 ]; then
    echo "[$TIMESTAMP] Pull 충돌 — stash 적용" | tee -a "$LOG_FILE"
    git stash >> "$LOG_FILE"
    git pull --rebase >> "$LOG_FILE"
    git stash pop >> "$LOG_FILE"
fi

# ===============================
# Push
# ===============================
git push >> "$LOG_FILE" 2>&1

if [ $? -eq 0 ]; then
    echo "[$TIMESTAMP] Push 성공" | tee -a "$LOG_FILE"
    notify_slack "✅ 자동 백업 성공!\n🕒 시간: $TIMESTAMP\n📄 변경 로그: $REPORT_PATH"
else
    echo "[$TIMESTAMP] Push 실패" | tee -a "$LOG_FILE"
    notify_slack "❌ 자동 백업 실패 — Push 오류 발생!"
fi

echo "[$TIMESTAMP] ==== AUTO BACKUP END ====" >> "$LOG_FILE"
echo ""
