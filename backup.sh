#!/bin/bash
cd /home/kimji/auto-backup

# ===============================
#  Slack 알림 함수 (환경 변수 사용)
# ===============================
WEBHOOK_URL="$SLACK_WEBHOOK_URL"

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
    echo "📌 최근 백업 로그 5개"
    echo "----------------------------------"

    LOG_FILE="logs/backup.log"

    # START, END 라인 번호 읽기
    mapfile -t STARTS < <(grep -n "AUTO BACKUP START" "$LOG_FILE" | awk -F: '{print $1}')
    mapfile -t ENDS   < <(grep -n "AUTO BACKUP END" "$LOG_FILE"   | awk -F: '{print $1}')

    if [ ${#STARTS[@]} -eq 0 ] || [ ${#ENDS[@]} -eq 0 ]; then
        echo "⚠ 기록된 백업 로그가 없습니다."
        exit 0
    fi

    # START와 END 매칭 (END < START인 경우, END 재조정)
    valid_starts=()
    valid_ends=()

    end_idx=0
    for s in "${STARTS[@]}"; do
        while [ $end_idx -lt ${#ENDS[@]} ] && [ "${ENDS[$end_idx]}" -lt "$s" ]; do
            ((end_idx++))
        done
        if [ $end_idx -lt ${#ENDS[@]} ]; then
            valid_starts+=("$s")
            valid_ends+=("${ENDS[$end_idx]}")
            ((end_idx++))
        fi
    done

    COUNT=${#valid_starts[@]}

    if [ $COUNT -eq 0 ]; then
        echo "⚠ 정상이었던 백업 기록이 없습니다."
        exit 0
    fi

    echo "총 $COUNT개의 정상 백업 중 최근 5개를 출력합니다."
    echo ""

    # 최근 5개만 출력
    for ((i = COUNT - 1; i >= COUNT - 5 && i >= 0; i--)); do
        S=${valid_starts[$i]}
        E=${valid_ends[$i]}

        echo "===== #$((i+1)) 번째 백업 기록 ====="
        sed -n "${S},${E}p" "$LOG_FILE"
        echo ""
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

LOG_FILE="logs/backup.log"
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
