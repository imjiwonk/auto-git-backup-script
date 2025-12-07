#!/bin/bash
cd /home/kimji/auto-backup

# ===============================
#  Slack 알림 함수 (환경 변수 사용)
# ===============================
WEBHOOK_URL="$SLACK_WEBHOOK_URL"

notify_slack_success() {
    TIME="$1"
    FILES="$2"
    REPORT="$3"

    if [ -z "$WEBHOOK_URL" ]; then
        echo "[INFO] SLACK_WEBHOOK_URL 없음 → Slack 알림 생략"
        return
    fi

    curl -X POST -H "Content-Type: application/json" \
        --data "{
  \"blocks\": [
    {
      \"type\": \"header\",
      \"text\": {
        \"type\": \"plain_text\",
        \"text\": \"✅ 자동 백업 성공!\",
        \"emoji\": true
      }
    },
    {
      \"type\": \"section\",
      \"fields\": [
        {
          \"type\": \"mrkdwn\",
          \"text\": \"*🗓 시간:*\n$TIME\"
        }
      ]
    },
    {
      \"type\": \"section\",
      \"text\": {
        \"type\": \"mrkdwn\",
        \"text\": \"*📄 변경된 파일 목록:*\n$FILES\"
      }
    },
    {
      \"type\": \"section\",
      \"text\": {
        \"type\": \"mrkdwn\",
        \"text\": \"📘 *보고서:* $REPORT\"
      }
    }
  ]
}" \
    "$WEBHOOK_URL"
}

notify_slack_fail() {
    REASON="$1"

    if [ -z "$WEBHOOK_URL" ]; then
        echo "[INFO] SLACK_WEBHOOK_URL 없음 → Slack 알림 생략"
        return
    fi

    curl -X POST -H "Content-Type: application/json" \
        --data "{
  \"blocks\": [
    {
      \"type\": \"header\",
      \"text\": {
        \"type\": \"plain_text\",
        \"text\": \"❌ 자동 백업 실패!\",
        \"emoji\": true
      }
    },
    {
      \"type\": \"section\",
      \"text\": {
        \"type\": \"mrkdwn\",
        \"text\": \"⚠ 실패 사유:\n$REASON\"
      }
    }
  ]
}" \
    "$WEBHOOK_URL"
}

# ===============================
#  최근 백업 로그 출력 기능
# ===============================
LOG_FILE="logs/backup.log"

show_recent() {
    echo "📌 최근 백업 로그 5개"
    echo "----------------------------------"

    mapfile -t STARTS < <(grep -n "AUTO BACKUP START" "$LOG_FILE" | awk -F: '{print $1}')
    mapfile -t ENDS < <(grep -n "AUTO BACKUP END" "$LOG_FILE" | awk -F: '{print $1}')

    if [ ${#STARTS[@]} -eq 0 ]; then
        echo "⚠ 기록된 백업 로그가 없습니다."
        exit 0
    fi

    COUNT=${#STARTS[@]}
    echo "총 $COUNT개의 정상적인 백업 중 최근 5개:"
    echo ""

    START_INDEX=$((COUNT > 5 ? COUNT - 5 : 0))

    for ((i = START_INDEX; i < COUNT; i++)); do
        S=${STARTS[$i]}
        E=${ENDS[$i]}

        BLOCK=$(sed -n "${S},${E}p" "$LOG_FILE")

        DATE=$(echo "$BLOCK" | grep -o "\[[0-9\-: ]\+\]" | head -n 1 | tr -d '[]')

        if echo "$BLOCK" | grep -q "Push 성공"; then
            STATUS="성공"
        elif echo "$BLOCK" | grep -q "변경 사항 없음"; then
            STATUS="없음"
        else
            STATUS="실패"
        fi

        CHANGE=$(echo "$BLOCK" | grep "files changed" | grep -o "[0-9]\+ files changed")
        [[ -z "$CHANGE" ]] && CHANGE="-"

        echo "#$((i+1)) | [$DATE] | $STATUS | $CHANGE"
    done
}

# -------------------------------
# 명령어 처리
# -------------------------------
if [ "$1" = "recent" ]; then
    show_recent
    exit 0
fi

# ===============================
# 필수 폴더 자동 생성
# ===============================
REQUIRED_DIRS=("logs" "reports" "scripts" "notes")

for DIR in "${REQUIRED_DIRS[@]}"; do
    if [ ! -d "$DIR" ]; then
        mkdir -p "$DIR"
        echo "[INFO] 폴더 생성: $DIR"
    fi
done

TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")

echo "[$TIMESTAMP] ==== AUTO BACKUP START ====" >> "$LOG_FILE"

# ===============================
#  Git 변경사항 확인
# ===============================
STATUS=$(git status --porcelain)

if [ -z "$STATUS" ]; then
    echo "[$TIMESTAMP] 변경 사항 없음. 백업 종료." | tee -a "$LOG_FILE"
    exit 0
fi

# ===============================
#  변경 로그 생성
# ===============================
REPORT_PATH=$(./generate_report.sh)
echo "변경 로그 생성 완료 → $REPORT_PATH"

# ===============================
#  변경 파일 목록 Slack용 포맷
# ===============================
CHANGED_FILES=$(git status --porcelain | awk '{print $2}')

FILE_LIST=""
while read -r FILE; do
    FILE_LIST="$FILE_LIST\n- $FILE"
done <<< "$CHANGED_FILES"

FILE_LIST_SLACK=$(echo -e "$FILE_LIST")

# ===============================
#  Commit 처리
# ===============================
git add .
git commit -m "Auto Backup : $TIMESTAMP" >> "$LOG_FILE" 2>&1

if [ $? -ne 0 ]; then
    echo "[$TIMESTAMP] Commit 실패" | tee -a "$LOG_FILE"
    notify_slack_fail "Commit 오류 발생"
    exit 1
fi

echo "[$TIMESTAMP] Commit 완료" >> "$LOG_FILE"

# ===============================
#  Pull (충돌 대비)
# ===============================
git pull --rebase >> "$LOG_FILE" 2>&1
if [ $? -ne 0 ]; then
    echo "[$TIMESTAMP] Pull 충돌 — stash 적용" | tee -a "$LOG_FILE"
    git stash >> "$LOG_FILE"
    git pull --rebase >> "$LOG_FILE"
    git stash pop >> "$LOG_FILE"
fi

# ===============================
#  Push
# ===============================
git push >> "$LOG_FILE" 2>&1

if [ $? -eq 0 ]; then
    echo "[$TIMESTAMP] Push 성공" | tee -a "$LOG_FILE"
    notify_slack_success "$TIMESTAMP" "$FILE_LIST_SLACK" "$REPORT_PATH"
else
    echo "[$TIMESTAMP] Push 실패" | tee -a "$LOG_FILE"
    notify_slack_fail "Push 오류"
fi

echo "[$TIMESTAMP] ==== AUTO BACKUP END ====" >> "$LOG_FILE"
echo ""
