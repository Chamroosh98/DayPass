package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	"path/filepath"
	"strings"
	"time"
)

func SendTelegramNotification(
	botToken, chatID, version, buildNum, actor, repo, releaseType string,
) {
	if botToken == "" || chatID == "" {
		fmt.Println("⚠️ Telegram credentials not provided. Skipping notification!")
		return
	}

	isRelease := releaseType == "release" || releaseType == "main" || releaseType == "stable"

	var tagFormat string
	var msgHeader string
	var installURL string
	var btnEmoji string
	var mergedDir string

	if isRelease {
		tagFormat = fmt.Sprintf("%s-%s", version, buildNum)
		msgHeader = "🚀 *New Stable DayPass Release!*"
		installURL = "https://Chamroosh98.github.io/DayPass/install.sh"
		btnEmoji = "📦 "
		mergedDir = "merged-release"
	} else {
		tagFormat = fmt.Sprintf("%s-beta-%s", version, buildNum)
		msgHeader = "🧪 *New Beta DayPass Ready!*"
		installURL = "https://Chamroosh98.github.io/DayPass/dev/install.sh"
		btnEmoji = "🧪 "
		mergedDir = "merged-beta"
	}

	var keyboard [][]InlineKeyboardButton

	zipMatches, _ := filepath.Glob("build-artifacts/DayPass_*.zip")
	mergedMatches, _ := filepath.Glob(fmt.Sprintf("%s/DayPass_*.zip", mergedDir))
	zipMatches = append(zipMatches, mergedMatches...)

	seenFiles := make(map[string]bool)

	for _, zipPath := range zipMatches {
		actualFileName := filepath.Base(zipPath)

		if seenFiles[actualFileName] {
			continue
		}
		seenFiles[actualFileName] = true

		btnLabel := strings.TrimPrefix(actualFileName, "DayPass_")
		btnLabel = strings.TrimSuffix(btnLabel, ".zip")

		downloadURL := fmt.Sprintf("https://github.com/%s/releases/download/%s/%s", repo, tagFormat, actualFileName)

		btn := InlineKeyboardButton{
			Text: btnEmoji + btnLabel,
			URL:  downloadURL,
		}
		keyboard = append(keyboard, []InlineKeyboardButton{btn})
	}

	if len(keyboard) == 0 {
		fmt.Printf("⚠️ No zip artifacts found in build-artifacts/ or %s/\n", mergedDir)
	}

	msgText := fmt.Sprintf(
		"%s\n\n🏷️ *Version :* `%s`\n🛠️ *Build :* `%s`\n👤 *By :* `%s`\n\n⚡ *Installer :*\n`wget -O- %s | sh`",
		msgHeader, tagFormat, buildNum, actor, installURL,
	)

	payload := TelegramMessage{
		ChatID:                chatID,
		Text:                  msgText,
		ParseMode:             "Markdown",
		ReplyMarkup:           InlineKeyboardMarkup{InlineKeyboard: keyboard},
		DisableWebPagePreview: true,
	}

	jsonPayload, err := json.Marshal(payload)
	if err != nil {
		fmt.Printf("❌ Failed to marshal Telegram payload: [%v]\n", err)
		return
	}

	apiURL := fmt.Sprintf("https://api.telegram.org/bot%s/sendMessage", botToken)
	req, err := http.NewRequest("POST", apiURL, bytes.NewBuffer(jsonPayload))
	if err != nil {
		fmt.Printf("❌ Failed to create Telegram request : [%v]\n", err)
		return
	}
	req.Header.Set("Content-Type", "application/json")

	client := &http.Client{Timeout: 10 * time.Second}
	resp, err := client.Do(req)

	if err == nil && resp.StatusCode == http.StatusOK {
		fmt.Println("✅ Dynamic Telegram notification sent successfully!")
		resp.Body.Close()
	} else {
		if err != nil {
			fmt.Printf("❌ Telegram API Network Error : [%v]\n", err)
		} else {
			fmt.Printf("❌ Telegram API Refused with Status : [%s]\n", resp.Status)
			resp.Body.Close()
		}
	}
}