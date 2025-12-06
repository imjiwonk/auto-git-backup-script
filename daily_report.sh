#!/bin/bash
cd /home/kimji/auto-backup

LOG_FILE="logs/backup.log"
WEBHOOK_URL="$SLACK_WEBHOOK_URL"
TODAY=$(date +"%Y-%m-%d")

# Slack 알림 함수
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

# 통계 계산
TOTAL=$(grep "$TODAY" $LOG_FILE | grep "AUTO BACKUP START" | wc -l)
SUCCESS=$(grep "$TODAY" $LOG_FILE | grep "Push 성공" | wc -l)
NO_CHANGE=$(grep "$TODAY" $LOG_FILE | grep "변경 사항 없음" | wc -l)
FAILED=$(grep "$TODAY" $LOG_FILE | grep "Push 실패" | wc -l)

REPORT="📅 *일일 자동 백업 요약 ($TODAY)*

- 전체 실행 횟수: $TOTAL 회
- 변경 감지 및 백업 성공: $SUCCESS 회
- 변경 없음: $NO_CHANGE 회
- 실패: $FAILED 회
"

notify_slack "$REPORT"
echo "[$TODAY] 일일 요약 리포트 전송 완료!"
