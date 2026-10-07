package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"path/filepath"
	"strings"
	"time"
)

// Public Telegram channel (bot must be an administrator).
// https://t.me/Chamroosh98
const telegramChannelChatID = "@Chamroosh98"

func SendTelegramNotification(
	botToken, chatID, version, buildNum, actor, repo, releaseType string,
) {
	if botToken == "" {
		fmt.Println("⚠️ Telegram bot token not provided. Skipping notification!")
		return
	}

	isRelease := releaseType == "release" || releaseType == "main" || releaseType == "stable"

	var tagFormat string
	var msgHeader string
	var installURL string
	var btnEmoji string
	var mergedDir string

	if isRelease {
		tagFormat = version
		msgHeader = "🚀 *New Stable DayPass Release!*"
		installURL = "https://Chamroosh98.github.io/DayPass/install.sh"
		btnEmoji = "📦 "
		mergedDir = "merged-release"
	} else {
		tagFormat = fmt.Sprintf("%s-beta", version)
		msgHeader = "🧪 *New Beta DayPass Ready!*"
		installURL = "https://Chamroosh98.github.io/DayPass/beta/install.sh"
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
		"%s\n\n🏷️ *Version :* `%s`\n🛠️ *Build :* `%s`\n👤 *By :* `%s`\n\n⚡ *Installer :*\n`wget -qO- %s | sh`",
		msgHeader, tagFormat, buildNum, actor, installURL,
	)

	destinations := uniqueTelegramDestinations(chatID, telegramChannelChatID)
	if len(destinations) == 0 {
		fmt.Println("⚠️ No Telegram destinations configured. Skipping notification!")
		return
	}

	ok := 0
	for _, dest := range destinations {
		if sendTelegramMessage(botToken, dest, msgText, keyboard) {
			ok++
		}
	}

	if ok == len(destinations) {
		fmt.Println("✅ Dynamic Telegram notification sent successfully!")
	} else if ok == 0 {
		fmt.Println("❌ Telegram notification failed for all destinations!")
	} else {
		fmt.Printf("⚠️ Telegram notification sent to %d/%d destinations!\n", ok, len(destinations))
	}
}

func uniqueTelegramDestinations(ids ...string) []string {
	seen := make(map[string]bool)
	var out []string
	for _, id := range ids {
		id = strings.TrimSpace(id)
		if id == "" {
			continue
		}
		key := strings.ToLower(id)
		if seen[key] {
			continue
		}
		seen[key] = true
		out = append(out, id)
	}
	return out
}

func sendTelegramMessage(botToken, chatID, text string, keyboard [][]InlineKeyboardButton) bool {
	payload := TelegramMessage{
		ChatID:                chatID,
		Text:                  text,
		ParseMode:             "Markdown",
		ReplyMarkup:           InlineKeyboardMarkup{InlineKeyboard: keyboard},
		DisableWebPagePreview: true,
	}

	jsonPayload, err := json.Marshal(payload)
	if err != nil {
		fmt.Printf("❌ Failed to marshal Telegram payload for [%s]: [%v]\n", chatID, err)
		return false
	}

	apiURL := fmt.Sprintf("https://api.telegram.org/bot%s/sendMessage", botToken)
	req, err := http.NewRequest("POST", apiURL, bytes.NewBuffer(jsonPayload))
	if err != nil {
		fmt.Printf("❌ Failed to create Telegram request for [%s]: [%v]\n", chatID, err)
		return false
	}
	req.Header.Set("Content-Type", "application/json")

	client := &http.Client{Timeout: 10 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		fmt.Printf("❌ Telegram API network error for [%s]: [%v]\n", chatID, err)
		return false
	}
	defer resp.Body.Close()

	body, _ := io.ReadAll(io.LimitReader(resp.Body, 2048))
	if resp.StatusCode == http.StatusOK {
		fmt.Printf("✅ Telegram notification sent to [%s]!\n", chatID)
		return true
	}

	fmt.Printf("❌ Telegram API refused [%s] with status [%s]: %s\n", chatID, resp.Status, strings.TrimSpace(string(body)))
	return false
}
