#!/bin/bash
cd /home/kimji/auto-backup

# -------------------------------------
# 최근 백업 로그 5개 출력
# -------------------------------------
if [[ "$1" == "recent" ]]; then
    echo "📌 최근 백업 로그 5개"
    echo "----------------------------------"

    # START 라인 번호 추출
    mapfile -t STARTS < <(grep -n "\=\=\=\= AUTO BACKUP START \=\=\=\=" "$LOG_FILE" | awk -F: '{print $1}')

    TOTAL=${#STARTS[@]}

    if (( TOTAL == 0 )); then
        echo "⚠ 기록된 백업 로그가 없습니다."
        exit 0
    fi

    # 최근 5개의 시작점만 사용
    COUNT=$(( TOTAL < 5 ? TOTAL : 5 ))

    echo "총 ${TOTAL}개의 백업 중 최근 ${COUNT}개를 출력합니다."
    echo ""

    for (( i=0; i<COUNT; i++ ))
    do
        INDEX=$(( TOTAL - i - 1 ))
        START_LINE=${STARTS[$INDEX]}

        # END 찾기
        END_LINE=$(sed -n "${START_LINE},\$p" "$LOG_FILE" | grep -n "AUTO BACKUP END" | head -n 1 | awk -F: '{print $1}')
        END_LINE=$(( START_LINE + END_LINE - 1 ))

        echo "===== #$((i+1)) 번째 백업 기록 ====="
        sed -n "${START_LINE},${END_LINE}p" "$LOG_FILE"
        echo ""
    done

    exit 0
fi


# --- 필수 폴더 자동 생성 ---
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

# 1. Git 변경사항 체크
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
#!/bin/bash

# --- 필수 폴더 자동 생성 ---
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

# 1. Git 변경사항 체크
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

