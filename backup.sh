#!/bin/bash
cd /home/kimji/auto-backup

############################################
#            함수 선언부 (먼저 필요)
############################################

show_recent() {
    LOG_FILE="logs/backup.log"

    echo " "
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📌  최근 실제 백업(Commit 발생) 로그 5개"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo " "

    # START 위치 수집
    mapfile -t STARTS < <(grep -n "AUTO *BACKUP *START" "$LOG_FILE" | awk -F: '{print $1}')
    TOTAL_LINES=$(wc -l < "$LOG_FILE")

    committed_blocks=()

    # 각 블록 탐색하며 commit 여부 확인
    for ((i=0; i<${#STARTS[@]}; i++)); do
        S=${STARTS[$i]}

        # 블록 범위 계산
        if (( i + 1 < ${#STARTS[@]} )); then
            E=$((STARTS[$((i+1))] - 1))
        else
            E=$TOTAL_LINES
        fi

        BLOCK=$(sed -n "${S},${E}p" "$LOG_FILE")

        # Commit 있는 로그만 저장
        if echo "$BLOCK" | grep -q "Commit 완료"; then
            committed_blocks+=("$S,$E")
        fi
    done

    COUNT=${#committed_blocks[@]}

    if [ $COUNT -eq 0 ]; then
        echo "⚠ Commit 기록이 없습니다."
        return
    fi

    echo "총 $COUNT개의 Commit 백업 중 최근 5개 출력"
    echo " "

    # 최근 5개의 commit 블록 출력
    for ((i = COUNT - 1; i >= COUNT - 5 && i >= 0; i--)); do
        block="${committed_blocks[$i]}"
        S=$(echo "$block" | cut -d',' -f1)
        E=$(echo "$block" | cut -d',' -f2)

        BLOCK_CONTENT=$(sed -n "${S},${E}p" "$LOG_FILE")

        # 날짜 추출
        DATE=$(echo "$BLOCK_CONTENT" | head -1 | grep -oP '\[\K[0-9:\- ]+(?=\])')

        # Commit ID 추출
        COMMIT=$(echo "$BLOCK_CONTENT" | grep -oP "\[main \K[0-9a-f]+")

        # 변경 파일 요약
        CHANGES=$(echo "$BLOCK_CONTENT" | grep -oP "[0-9]+ insertions|\b[0-9]+ deletions" | paste -sd ", " -)

        # Report 파일명
        REPORT=$(echo "$BLOCK_CONTENT" | grep -oP "reports/[0-9\-_]+\.txt")

        # Push 상태
        PUSH=$(echo "$BLOCK_CONTENT" | grep "Push 성공" >/dev/null && echo "성공" || echo "실패")

        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "📦  백업 #$((i+1))   ($DATE)"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "✔ Commit ID : ${COMMIT:-알 수 없음}"
        echo "✔ 변경 사항 : ${CHANGES:-변경 정보 없음}"
        echo "✔ Report    : ${REPORT:-없음}"
        echo "✔ Push 결과 : $PUSH"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo " "
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
