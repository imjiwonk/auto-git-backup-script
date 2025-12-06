#!/bin/bash

SCRIPT_PATH="$(pwd)/backup.sh"

echo "현재 프로젝트 경로: $SCRIPT_PATH"

echo "Cron 등록 중..."
(
crontab -l
echo "*/10 * * * * $SCRIPT_PATH"
) | crontab -

echo "10분 간격 백업 cron 등록 완료!"
