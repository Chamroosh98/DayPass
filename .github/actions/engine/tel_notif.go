package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	"path/filepath"
	"time"
)

func SendTelegramNotification(
	botToken, chatID, version, buildNum, actor, repo, releaseType string,
	architectures []FeedConfig,
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

	if isRelease {
		tagFormat = fmt.Sprintf("v%s-%s", version, buildNum)
		msgHeader = "🚀 *New Stable DayPass Release!*"
		installURL = "https://Chamroosh98.github.io/DayPass/install.sh"
		btnEmoji = "📦 "
	} else {
		tagFormat = fmt.Sprintf("v%s-beta-%s", version, buildNum)
		msgHeader = "🧪 *New Beta DayPass Ready!*"
		installURL = "https://Chamroosh98.github.io/DayPass/dev/install.sh"
		btnEmoji = "🧪 "
	}

	var keyboard [][]InlineKeyboardButton
	for _, arch := range architectures {
		// 1. Secarch in build-artifacts
		zipMatch, _ := filepath.Glob(fmt.Sprintf("build-artifacts/DayPass_%s_*.zip", arch.Name))
		
		// 2. Fallback : if the basic path doesn't exits, so search in : merged-beta
		if len(zipMatch) == 0 {
			zipMatch, _ = filepath.Glob(fmt.Sprintf("merged-beta/DayPass_%s_*.zip", arch.Name))
		}

		if len(zipMatch) > 0 {
			actualFileName := filepath.Base(zipMatch[0])
			
			// Create direct links from GitHub Release
			downloadURL := fmt.Sprintf("https://github.com/%s/releases/download/%s/%s", repo, tagFormat, actualFileName)

			btn := InlineKeyboardButton{
				Text: btnEmoji + arch.Name,
				URL:  downloadURL,
			}
			keyboard = append(keyboard, []InlineKeyboardButton{btn})
		} else {
			fmt.Printf("⚠️ No zip found for architecture: [%s]\n", arch.Name)
		}
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
		fmt.Printf("❌ Failed to create Telegram request: [%v]\n", err)
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