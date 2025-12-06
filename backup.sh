#!/bin/bash
cd /home/kimji/auto-backup

############################################
#            함수 선언부 (먼저 필요)
############################################

show_recent() {
    echo "📌 최근 백업 로그 5개"
    echo "----------------------------------"

    LOG_FILE="logs/backup.log"

    if [ ! -f "$LOG_FILE" ]; then
        echo "⚠ 백업 로그 파일이 존재하지 않습니다."
        exit 0
    fi

    # START 지점 찾기
    mapfile -t STARTS < <(grep -n "AUTO *BACKUP *START" "$LOG_FILE" | awk -F: '{print $1}')
    # END 지점 찾기
    mapfile -t ENDS < <(grep -n "AUTO *BACKUP *END" "$LOG_FILE" | awk -F: '{print $1}')

    if [ ${#STARTS[@]} -eq 0 ]; then
        echo "⚠ 기록된 백업 로그가 없습니다."
        exit 0
    fi

    COUNT=${#STARTS[@]}
    echo "총 $COUNT개의 백업 중 최근 5개를 출력합니다."
    echo ""

    # 최근 5개만 출력
    for ((i = COUNT - 1; i >= COUNT - 5 && i >= 0; i--)); do
        S=${STARTS[$i]}
        E=${ENDS[$i]}

        echo "===== #$((i+1)) 번째 백업 기록 ====="
        sed -n "${S},${E}p" "$LOG_FILE"
        echo ""
    done
}

############################################
#          명령 모드 처리 (함수 아래에 위치)
############################################

if [ "$1" = "recent" ]; then
    show_recent
    exit 0
fi

############################################
#           백업 기능 시작
############################################

# 필수 폴더 생성
REQUIRED_DIRS=("logs" "reports" "scripts" "notes")
for DIR in "${REQUIRED_DIRS[@]}"; do
    if [ ! -d "$DIR" ]; then
        mkdir -p "$DIR"
        echo "[INFO] 폴더 생성: $DIR"
    fi
done

LOG_DIR="logs"
LOG_FILE="$LOG_DIR/backup.log"
TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")

echo "[$TIMESTAMP] ==== AUTO BACKUP START ====" >> "$LOG_FILE"

# 변경사항 체크
STATUS=$(git status --porcelain)
if [ -z "$STATUS" ]; then
    echo "[$TIMESTAMP] 변경 사항 없음. 백업 종료." | tee -a "$LOG_FILE"
    exit 0
fi

# 변경 로그 생성
./generate_report.sh

# Git add → commit
git add .
git commit -m "Auto Backup : $TIMESTAMP" >> "$LOG_FILE" 2>&1
if [ $? -ne 0 ]; then
    echo "[$TIMESTAMP] Commit 실패" | tee -a "$LOG_FILE"
    exit 1
fi

echo "[$TIMESTAMP] Commit 완료" >> "$LOG_FILE"

# pull → 충돌 시 stash 자동 처리
git pull --rebase >> "$LOG_FILE" 2>&1
if [ $? -ne 0 ]; then
    echo "[$TIMESTAMP] Pull 충돌 → 자동 stash 적용" | tee -a "$LOG_FILE"
    git stash >> "$LOG_FILE"
    git pull --rebase >> "$LOG_FILE"
    git stash pop >> "$LOG_FILE"
fi

# push
git push >> "$LOG_FILE" 2>&1
if [ $? -eq 0 ]; then
    echo "[$TIMESTAMP] Push 성공" | tee -a "$LOG_FILE"
else
    echo "[$TIMESTAMP] Push 실패" | tee -a "$LOG_FILE"
fi

echo "[$TIMESTAMP] ==== AUTO BACKUP END ====" >> "$LOG_FILE"
echo ""
