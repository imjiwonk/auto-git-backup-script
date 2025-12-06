#!/bin/bash

# ========== 색상 ==========
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
BLUE="\e[36m"
RESET="\e[0m"

BACKUP_PATH="/home/kimji/auto-backup/backup.sh"
CRON_LOG="/home/kimji/auto-backup/cron.log"

# ========== 화면 클리어 ==========
clear

echo -e "${BLUE}"
echo "╔══════════════════════════════════════════╗"
echo "║        🚀 자동 백업 주기 설정 메뉴        ║"
echo "╚══════════════════════════════════════════╝"
echo -e "${RESET}"

echo -e "${YELLOW}원하는 백업 실행 주기를 선택하세요:${RESET}"
echo ""
echo -e "${GREEN} 1) 5분마다 실행"
echo -e " 2) 10분마다 실행"
echo -e " 3) 30분마다 실행"
echo -e " 4) 1시간마다 실행"
echo -e "${RED} 5) Cron 설정 해제"
echo -e "${RESET}"
echo "----------------------------------------------"

# ========== 올바른 입력 받을 때까지 반복 ==========
while true; do
    read -p "번호를 입력하세요 → " choice

    case $choice in
        1)
            schedule="*/5 * * * *"
            break
            ;;
        2)
            schedule="*/10 * * * *"
            break
            ;;
        3)
            schedule="*/30 * * * *"
            break
            ;;
        4)
            schedule="0 */1 * * *"
            break
            ;;
        5)
            crontab -r
            echo -e "${RED}[INFO] 모든 cron 설정이 삭제되었습니다.${RESET}"
            exit 0
            ;;
        *)
            echo -e "${RED}잘못된 선택입니다. 다시 입력해주세요.${RESET}"
            ;;
    esac
done

# ========== 기존 백업 cron 제거 후 새 설정 기록 ==========
(
crontab -l 2>/dev/null | grep -v "auto-backup/backup.sh"
echo "$schedule $BACKUP_PATH >> $CRON_LOG 2>&1"
) | crontab -

# ========== 애니메이션 효과 ==========
echo ""
echo -ne "${BLUE}설정을 적용하는 중."
sleep 0.5
echo -ne "."
sleep 0.5
echo -ne "."
sleep 0.5
echo -e "${RESET}"

# ========== 완료 메시지 ==========
echo ""
echo -e "${GREEN}✔ 새로운 자동 백업 주기가 성공적으로 설정되었습니다!${RESET}"
echo ""
echo -e "${YELLOW}📌 적용된 주기:   ${GREEN}$schedule${RESET}"
echo -e "${YELLOW}📌 실행 파일:     ${GREEN}$BACKUP_PATH${RESET}"
echo ""
echo -e "확인하려면 아래 명령을 실행하세요:"
echo -e "${BLUE}crontab -l${RESET}"
echo ""
