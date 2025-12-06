#!/bin/bash

LOG_DIR="logs"
LOG_FILE="$LOG_DIR/backup.log"
TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")

mkdir -p "$LOG_DIR"

echo "[$TIMESTAMP] ==== AUTO BACKUP START ====" >> "$LOG_FILE"

# 1. 변경사항 체크
STATUS=$(git status --porcelain)

if [ -z "$STATUS" ]; then
    echo "[$TIMESTAMP] 변경 사항 없음. 백업 종료." | tee -a "$LOG_FILE"
    exit 0
fi

# 2. 변경 로그 생성
./generate_report.sh

# 3. Git add & commit
git add .
git commit -m "Auto Backup : $TIMESTAMP" >> "$LOG_FILE" 2>&1

if [ $? -ne 0 ]; then
    echo "[$TIMESTAMP] Commit 실패" | tee -a "$LOG_FILE"
    exit 1
fi

echo "[$TIMESTAMP] Commit 완료" >> "$LOG_FILE"

# 4. Git pull (충돌 대비)
git pull --rebase >> "$LOG_FILE" 2>&1

if [ $? -ne 0 ]; then
    echo "[$TIMESTAMP] Pull 충돌 → 자동 stash 적용" | tee -a "$LOG_FILE"
    git stash >> "$LOG_FILE"
    git pull --rebase >> "$LOG_FILE"
    git stash pop >> "$LOG_FILE"
fi

# 5. 원격 저장소로 push
git push >> "$LOG_FILE" 2>&1

if [ $? -eq 0 ]; then
    echo "[$TIMESTAMP] Push 성공" | tee -a "$LOG_FILE"
else
    echo "[$TIMESTAMP] Push 실패" | tee -a "$LOG_FILE"
fi

echo "[$TIMESTAMP] ==== AUTO BACKUP END ====" >> "$LOG_FILE"
echo ""
