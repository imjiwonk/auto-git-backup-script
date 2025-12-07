#!/bin/bash

REPORT_DIR="reports"
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
REPORT_FILE="$REPORT_DIR/$TIMESTAMP-report.txt"

mkdir -p "$REPORT_DIR"

# Git 변경 사항 확인
STATUS=$(git status --porcelain)

if [ -z "$STATUS" ]; then
    echo "[$TIMESTAMP] 변경 사항 없음" > "$REPORT_FILE"
    exit 0
fi

echo "[$TIMESTAMP] Auto Backup Report" > "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

# 분류별 정리
ADDED=$(echo "$STATUS" | grep "^A " | awk '{print $2}')
MODIFIED=$(echo "$STATUS" | grep "^ M" | awk '{print $2}')
DELETED=$(echo "$STATUS" | grep "^ D" | awk '{print $2}')

# 출력 함수
write_section () {
    TITLE=$1
    CONTENT=$2
    if [ ! -z "$CONTENT" ]; then
        echo "$TITLE:" >> "$REPORT_FILE"
        echo "$CONTENT" | sed 's/^/  - /' >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
    fi
}

write_section "Added" "$ADDED"
write_section "Modified" "$MODIFIED"
write_section "Deleted" "$DELETED"

echo "변경 로그 생성 완료 → $REPORT_FILE"
