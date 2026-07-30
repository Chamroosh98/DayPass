package main

import (
	"archive/zip"
	"crypto/sha256"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"path/filepath"
)

func copyFile(src, dst string) error {
	srcStat, err1 := os.Stat(src)
	dstStat, err2 := os.Stat(dst)

	if err1 == nil && err2 == nil && os.SameFile(srcStat, dstStat) {
		return nil
	}

	in, err := os.Open(src)
	if err != nil {
		return err
	}
	defer in.Close()

	out, err := os.Create(dst)
	if err != nil {
		return err
	}
	defer out.Close()

	_, err = io.Copy(out, in)
	return err
}

func main() {
	workspace := os.Getenv("GITHUB_WORKSPACE")
	if workspace != "" {
		os.Chdir(workspace)
	}

	botToken := os.Getenv("INPUT_TELEGRAM_BOT_TOKEN")
	chatID := os.Getenv("INPUT_TELEGRAM_CHAT_ID")
	version := os.Getenv("INPUT_VERSION")
	buildNum := os.Getenv("INPUT_BUILD_NUMBER")
	actor := os.Getenv("INPUT_ACTOR")
	repo := os.Getenv("GITHUB_REPOSITORY")
	releaseType := os.Getenv("INPUT_RELEASE_TYPE")

	versions := []string{"24", "25"}

	fmt.Println("🦫 Go Engine Active & Merging Multi-Version Matrix Artifacts ...")
	os.MkdirAll("build-artifacts", 0755)

	for _, ver := range versions {
		archConfigFile := fmt.Sprintf("config/architectures_%s.json", ver)
		if _, err := os.Stat(archConfigFile); os.IsNotExist(err) {
			continue
		}

		fmt.Printf("\n⚙️ Processing OpenWrt Version [%s] ...\n", ver)

		configData, err := os.ReadFile(archConfigFile)
		if err != nil {
			fmt.Printf("❌ Failed to read arch config [%s]: %v\n", archConfigFile, err)
			continue
		}

		var archConfig ArchConfig
		if err := json.Unmarshal(configData, &archConfig); err != nil {
			fmt.Printf("❌ Failed to parse config [%s]: %v\n", archConfigFile, err)
			continue
		}

		verOutputDir := fmt.Sprintf("manifest-workspace/v%s", ver)

		// Unzip matrix outputs
		for _, arch := range archConfig.Architectures {
			destDir := fmt.Sprintf("%s/%s", verOutputDir, arch.Name)
			os.MkdirAll(destDir, 0755)

			matches, _ := filepath.Glob(fmt.Sprintf("merged-beta/DayPass_OW%s_%s_*.zip", ver, arch.Name))
			if len(matches) == 0 {
				matches, _ = filepath.Glob(fmt.Sprintf("merged-release/DayPass_OW%s_%s_*.zip", ver, arch.Name))
			}

			if len(matches) > 0 {
				zipFile := matches[0]
				fmt.Printf("📦 Extracting matrix artifact : [%s]\n", zipFile)

				r, err := zip.OpenReader(zipFile)
				if err != nil {
					fmt.Printf("❌ Error opening zip [%s] : [%v]\n", zipFile, err)
					continue
				}

				for _, f := range r.File {
					if filepath.Base(f.Name) == "index.json" {
						continue
					}

					fpath := filepath.Join(destDir, f.Name)
					if f.FileInfo().IsDir() {
						os.MkdirAll(fpath, os.ModePerm)
						continue
					}
					os.MkdirAll(filepath.Dir(fpath), os.ModePerm)

					func() {
						outFile, err := os.OpenFile(fpath, os.O_WRONLY|os.O_CREATE|os.O_TRUNC, f.Mode())
						if err != nil {
							return
						}
						defer outFile.Close()
						rc, err := f.Open()
						if err != nil {
							return
						}
						defer rc.Close()
						io.Copy(outFile, rc)
					}()
				}
				r.Close()
			}
		}

		// Generate Manifest per Version
		fmt.Printf("🧠 Compiling Manifest for v%s ...\n", ver)
		if err := GenerateManifest(archConfigFile, verOutputDir, ver); err != nil {
			fmt.Printf("❌ Error generating manifest for v%s: %v\n", ver, err)
		}

		// Isolating Manifest for Pages
		targetVerArtifactDir := fmt.Sprintf("build-artifacts/v%s", ver)
		os.MkdirAll(targetVerArtifactDir, 0755)
		copyFile(filepath.Join(verOutputDir, "manifest.json"), filepath.Join(targetVerArtifactDir, "manifest.json"))

		// اگر نسخه 25 بود، به عنوان نسخه Root هم کپی می‌کنیم
		if ver == "25" {
			copyFile(filepath.Join(verOutputDir, "manifest.json"), "build-artifacts/manifest.json")
		}
	}

	// Calculate SHA256 Hashes
	zipMatches, _ := filepath.Glob("merged-*/DayPass_v*.zip")
	for _, zipFile := range zipMatches {
		func() {
			f, err := os.Open(zipFile)
			if err != nil {
				return
			}
			defer f.Close()
			h := sha256.New()
			io.Copy(h, f)
			fileSHA := fmt.Sprintf("%x", h.Sum(nil))
			shaFileName := filepath.Base(zipFile) + ".sha256"

			os.WriteFile("build-artifacts/"+shaFileName, []byte(fileSHA+"  "+filepath.Base(zipFile)+"\n"), 0644)
		}()
	}

	// Compile Core Install Script
	if err := generateInstallScript("build-artifacts/install.sh"); err != nil {
		fmt.Printf("❌ Failed to compile install.sh : [%v]\n", err)
	}

	fmt.Println("\n📊 Checking Final Release Assets Structure :")
	filepath.Walk("build-artifacts", func(path string, info os.FileInfo, err error) error {
		if err == nil && !info.IsDir() {
			fmt.Printf("📦 [%s] -> %.2f KB\n", path, float64(info.Size())/1024.0)
		}
		return nil
	})

	// Telegram Notification
	SendTelegramNotification(botToken, chatID, version, buildNum, actor, repo, releaseType)
}