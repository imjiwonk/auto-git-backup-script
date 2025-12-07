#!/bin/bash
cd /home/kimji/auto-backup
LOG_FILE="logs/backup.log"
# ===============================
#  Slack 알림 함수 (환경 변수 사용)
# ===============================
WEBHOOK_URL="$SLACK_WEBHOOK_URL"
CRON_LOG="/home/kimji/auto-backup/cron.log"

notify_slack() {
    MESSAGE="$1"

    if [ -z "$WEBHOOK_URL" ]; then
        echo "[INFO] SLACK_WEBHOOK_URL 없음 → Slack 알림 생략"
        return
    fi

    curl -X POST -H 'Content-type: application/json' \
        --data "{\"text\": \"$MESSAGE\"}" \
        "$WEBHOOK_URL" > /dev/null 2>&1
}

# ===============================
#  최근 백업 로그 출력 기능
# ===============================
show_recent() {
    if [[ ! -f "$LOG_FILE" ]]; then
        echo -e "[ERROR] 로그 파일이 없습니다: $LOG_FILE"
        exit 1
    fi

    echo "📌 최근 백업 로그 5개"
    echo "----------------------------------"

    # 전체 START 라인 번호 배열 가져오기
    mapfile -t STARTS < <(grep -n "AUTO BACKUP START" "$LOG_FILE" | awk -F: '{print $1}')

    TOTAL=${#STARTS[@]}
    if [[ $TOTAL -eq 0 ]]; then
        echo "백업 기록이 없습니다."
        exit 0
    fi

    # 최근 5개의 인덱스만 사용
    START_INDEX=$((TOTAL > 5 ? TOTAL - 5 : 0))

    for ((i=START_INDEX; i<TOTAL; i++)); do
        START_LINE=${STARTS[$i]}

        # END_LINE 계산 (마지막 블록인지 확인)
        if (( i == TOTAL - 1 )); then
            END_LINE=$(wc -l < "$LOG_FILE")
        else
            END_LINE=$(( STARTS[$i+1] - 1 ))
        fi

        # sed로 블록 추출
        BLOCK=$(sed -n "${START_LINE},${END_LINE}p" "$LOG_FILE")

        # 날짜 추출
        DATE=$(echo "$BLOCK" | grep -o "\[[0-9\-: ]\+\]" | head -n 1 | tr -d '[]')

        # 상태 판별
        if echo "$BLOCK" | grep -q "Push 성공"; then
            STATUS="성공"
        elif echo "$BLOCK" | grep -q "변경 사항 없음"; then
            STATUS="없음"
        else
            STATUS="실패"
        fi

        # 변경 파일 수
        CHANGED=$(echo "$BLOCK" | grep "files changed" | grep -o "[0-9]\+ files changed")
        [[ -z "$CHANGED" ]] && CHANGED="-"

        # 출력 번호는 총 개수 기준
        BLOCK_NUM=$(( i + 1 ))

        echo "#$BLOCK_NUM | [$DATE] | $STATUS | $CHANGED"
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

# ===============================
#  Commit 처리
# ===============================
git add .
git commit -m "Auto Backup : $TIMESTAMP" >> "$LOG_FILE" 2>&1

if [ $? -ne 0 ]; then
    echo "[$TIMESTAMP] Commit 실패" | tee -a "$LOG_FILE"
    notify_slack "❌ 자동 백업 실패 — Commit 오류 발생"
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
    notify_slack "✅ *자동 백업 성공!*
📅 시간: $TIMESTAMP
📄 변경된 파일 목록:$FILE_LIST
📘 보고서: $REPORT_PATH"
else
    echo "[$TIMESTAMP] Push 실패" | tee -a "$LOG_FILE"
    notify_slack "❌ 자동 백업 실패 (Push 오류)"
fi

echo "[$TIMESTAMP] ==== AUTO BACKUP END ====" >> "$LOG_FILE"
echo ""
