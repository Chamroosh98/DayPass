package main

import (
	"archive/zip"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"os"
	"path/filepath"
	"strings"
)

func stageHelpManuals(dest string) {
	helpDir := "help"
	if _, err := os.Stat(helpDir); err != nil {
		// Engine is sometimes started from .github/actions/engine without GITHUB_WORKSPACE.
		alt := filepath.Join("..", "..", "..", "help")
		if _, err2 := os.Stat(alt); err2 == nil {
			helpDir = alt
		}
	}

	entries, err := os.ReadDir(helpDir)
	if err != nil {
		log.Fatal(err)
	}

	if err := os.MkdirAll(dest, 0755); err != nil {
		log.Fatal(err)
	}

	staged := 0
	for _, entry := range entries {
		if entry.IsDir() || !strings.HasSuffix(entry.Name(), ".json") {
			continue
		}
		src := filepath.Join(helpDir, entry.Name())
		dst := filepath.Join(dest, entry.Name())
		if err := copyFile(src, dst); err != nil {
			log.Fatal(err)
		}
		staged++
	}

	fmt.Printf("✅ Staged [%d] help manuals into [%s]\n", staged, dest)
}

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

	_, err = io.Copy(out, in)
	return errors.Join(err, out.Close())
}

func extractPackages(src, dest, extension string) error {
	archive, err := zip.OpenReader(src)
	if err != nil {
		return err
	}
	defer archive.Close()
	count := 0
	for _, entry := range archive.File {
		if entry.FileInfo().IsDir() || !strings.HasSuffix(entry.Name, extension) {
			continue
		}
		if !filepath.IsLocal(entry.Name) || entry.UncompressedSize64 == 0 {
			return fmt.Errorf("invalid package %q in %s", entry.Name, src)
		}
		path := filepath.Join(dest, entry.Name)
		if err := os.MkdirAll(filepath.Dir(path), 0755); err != nil {
			return err
		}
		in, err := entry.Open()
		if err != nil {
			return err
		}
		out, err := os.OpenFile(path, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0644)
		if err != nil {
			in.Close()
			return err
		}
		_, err = io.Copy(out, in)
		if err = errors.Join(err, out.Close(), in.Close()); err != nil {
			return err
		}
		count++
	}
	if count == 0 {
		return fmt.Errorf("%s contains no %s packages", src, extension)
	}
	return nil
}

func must(err error) {
	if err != nil {
		log.Fatal(err)
	}
}

func main() {
	workspace := os.Getenv("GITHUB_WORKSPACE")
	if workspace != "" {
		must(os.Chdir(workspace))
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
	must(os.MkdirAll("build-artifacts", 0755))

	workspaceDir, err := os.MkdirTemp("", "daypass-manifests-")
	must(err)
	defer os.RemoveAll(workspaceDir)
	channel := "release"
	if releaseType == "beta" {
		channel = "beta"
	}
	var archives []string
	for _, ver := range versions {
		archConfigFile := fmt.Sprintf("config/architectures_%s.json", ver)
		configData, err := os.ReadFile(archConfigFile)
		must(err)
		var archConfig ArchConfig
		must(json.Unmarshal(configData, &archConfig))
		if len(archConfig.Architectures) == 0 {
			log.Fatalf("no architectures in %s", archConfigFile)
		}
		verOutputDir := filepath.Join(workspaceDir, "v"+ver)
		extension := ".apk"
		if ver == "24" {
			extension = ".ipk"
		}
		for _, arch := range archConfig.Architectures {
			pattern := fmt.Sprintf("merged-%s/DayPass_OW%s_%s_*.zip", channel, ver, arch.Name)
			matches, err := filepath.Glob(pattern)
			must(err)
			if len(matches) != 1 {
				log.Fatalf("expected one archive for %s, found %d", pattern, len(matches))
			}
			must(extractPackages(matches[0], filepath.Join(verOutputDir, arch.Name), extension))
			archives = append(archives, matches[0])
		}
		// Generate Manifest per Version
		fmt.Printf("🧠 Compiling Manifest for v%s ...\n", ver)
		if err := GenerateManifest(archConfigFile, verOutputDir, ver); err != nil {
			log.Fatal(err)
		}

		// Isolating Manifest for Pages
		targetVerArtifactDir := fmt.Sprintf("build-artifacts/v%s", ver)
		must(os.MkdirAll(targetVerArtifactDir, 0755))
		must(copyFile(filepath.Join(verOutputDir, "manifest.json"), filepath.Join(targetVerArtifactDir, "manifest.json")))

		// اگر نسخه 25 بود، به عنوان نسخه Root هم کپی می‌کنیم
		if ver == "25" {
			must(copyFile(filepath.Join(verOutputDir, "manifest.json"), "build-artifacts/manifest.json"))
		}
	}

	// Calculate SHA256 Hashes
	for _, archive := range archives {
		digest, err := calculateSHA256(archive)
		must(err)
		name := filepath.Base(archive)
		must(os.WriteFile(filepath.Join("build-artifacts", name+".sha256"), []byte(digest+"  "+name+"\n"), 0644))
	}
	// Compile Core Install Script
	if err := generateInstallScript("build-artifacts/install.sh"); err != nil {
		log.Fatal(err)
	}

	// Stage in-app manuals next to install.sh so Pages serves REPO_URL/help/<id>.json
	stageHelpManuals("build-artifacts/help")

	// Package profiles served as REPO_URL/config/package_profiles.json
	must(os.MkdirAll("build-artifacts/config", 0755))
	if err := copyFile("config/package_profiles.json", "build-artifacts/config/package_profiles.json"); err != nil {
		log.Fatal(err)
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
