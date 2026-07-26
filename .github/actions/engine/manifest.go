package main

import (
	"crypto/sha256"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
	"time"
)

type ArchInput struct {
	Name string `json:"name"`
}

type ArchitectureConfig struct {
	Release       string      `json:"release"`
	Architectures []ArchInput `json:"architectures"`
}

type PackageInfo struct {
	Package string `json:"package"`
	File    string `json:"file"`
	Sha256  string `json:"sha256"`
	Size    int64  `json:"size"`
}

type ArchOutput struct {
	Name     string        `json:"name"`
	Packages []PackageInfo `json:"packages"`
}

type ManifestOutput struct {
	Release       string       `json:"release"`
	GeneratedAt   string       `json:"generated_at"`
	DownloadBase  string       `json:"download_base"`
	Architectures []ArchOutput `json:"architectures"`
}

func calculateSHA256(filePath string) (string, error) {
	file, err := os.Open(filePath)
	if err != nil {
		return "", err
	}
	defer file.Close()

	hash := sha256.New()
	if _, err := io.Copy(hash, file); err != nil {
		return "", err
	}
	return fmt.Sprintf("%x", hash.Sum(nil)), nil
}

func GenerateManifest(archConfigPath, outputDir, owVersion string) error {
	configData, err := os.ReadFile(archConfigPath)
	if err != nil {
		return fmt.Errorf("❌ Failed to read arch config : %w", err)
	}

	var config ArchitectureConfig
	if err := json.Unmarshal(configData, &config); err != nil {
		return fmt.Errorf("❌ Failed to unmarshal arch config : %w", err)
	}

	repo := os.Getenv("GITHUB_REPOSITORY")
	if repo == "" {
		repo = "Chamroosh98/DayPass"
	}
	cdnBaseUrl := fmt.Sprintf("https://cdn.jsdelivr.net/gh/%s@packages/v%s", repo, owVersion)

	manifest := ManifestOutput{
		Release:       config.Release,
		GeneratedAt:   time.Now().UTC().Format(time.RFC3339),
		DownloadBase:  cdnBaseUrl,
		Architectures: []ArchOutput{},
	}

	for _, arch := range config.Architectures {
		archDir := filepath.Join(outputDir, arch.Name)
		archOut := ArchOutput{
			Name:     arch.Name,
			Packages: []PackageInfo{},
		}

		if _, err := os.Stat(archDir); os.IsNotExist(err) {
			fmt.Printf("⚠️ Directory not found : %s (Skipping ...)\n", archDir)
			manifest.Architectures = append(manifest.Architectures, archOut)
			continue
		}

		err := filepath.WalkDir(archDir, func(path string, d os.DirEntry, err error) error {
			if err != nil || d.IsDir() {
				return err
			}

			fileName := d.Name()
			loweredName := strings.ToLower(fileName)

			var pkgName string
			if strings.HasSuffix(loweredName, ".apk") {
				pkgName = strings.TrimSuffix(fileName, ".apk")
			} else if strings.HasSuffix(loweredName, ".ipk") {
				pkgName = strings.TrimSuffix(fileName, ".ipk")
			} else {
				return nil
			}

			fileInfo, err := d.Info()
			if err != nil {
				return fmt.Errorf("❌ Failed to get file info for [%s] : [%w]", path, err)
			}

			sha, err := calculateSHA256(path)
			if err != nil {
				return fmt.Errorf("❌ Failed to calculate sha256 for [%s] : [%w]", path, err)
			}

			archOut.Packages = append(archOut.Packages, PackageInfo{
				Package: pkgName,
				File:    fmt.Sprintf("%s/%s", arch.Name, fileName),
				Sha256:  sha,
				Size:    fileInfo.Size(),
			})

			return nil
		})

		if err != nil {
			return fmt.Errorf("❌ Error while walking directory %s: %w", archDir, err)
		}

		manifest.Architectures = append(manifest.Architectures, archOut)
		fmt.Printf("✅ Manifest for OpenWrt v%s [%s] generated (%d packages)\n", owVersion, arch.Name, len(archOut.Packages))
	}

	finalManifestPath := filepath.Join(outputDir, "manifest.json")
	finalJson, err := json.MarshalIndent(manifest, "", "  ")
	if err != nil {
		return fmt.Errorf("❌ Failed to marshal final manifest : %w", err)
	}

	return os.WriteFile(finalManifestPath, finalJson, 0644)
}