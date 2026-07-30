package main

import (
	"crypto/sha256"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"regexp"
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
	Version string `json:"version"` // Explicit version field
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

// Extract base package name and version string safely
// Example: "luci-app-passwall2-26.7.16-r1.apk" -> pkg="luci-app-passwall2", ver="26.7.16-r1"
func parsePackageNameAndVersion(fileName string) (string, string) {
	cleanName := fileName
	for _, ext := range []string{".apk", ".ipk"} {
		if strings.HasSuffix(strings.ToLower(cleanName), ext) {
			cleanName = cleanName[:len(cleanName)-len(ext)]
			break
		}
	}

	// Regex pattern for Alpine/OpenWrt package naming standard: <name>-<version_revision>
	// Matches: (package-name)-(digits.*)
	re := regexp.MustCompile(`^(.+?)-(\d+.*)$`)
	matches := re.FindStringSubmatch(cleanName)

	if len(matches) == 3 {
		return matches[1], matches[2]
	}

	// Fallback if version pattern didn't match
	return cleanName, "Latest"
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

	releaseType := os.Getenv("INPUT_RELEASE_TYPE") 
	var cdnBaseUrl string

	if releaseType != "" {
		cdnBaseUrl = fmt.Sprintf("https://cdn.jsdelivr.net/gh/%s@packages/%s/v%s", repo, releaseType, owVersion)
	} else {
		cdnBaseUrl = fmt.Sprintf("https://cdn.jsdelivr.net/gh/%s@packages/v%s", repo, owVersion)
	}

	manifest := ManifestOutput{
		Release:       config.Release,
		GeneratedAt:   time.Now().UTC().Format(time.RFC3339),
		DownloadBase:  cdnBaseUrl,
		Architectures: []ArchOutput{},
	}

	for _, arch := range config.Architectures {
		archDir := filepath.Join(outputDir, fmt.Sprintf("v%s", owVersion), arch.Name)
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

			if !strings.HasSuffix(loweredName, ".apk") && !strings.HasSuffix(loweredName, ".ipk") {
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

			// Parse clean package name and version
			pkgName, pkgVersion := parsePackageNameAndVersion(fileName)

			archOut.Packages = append(archOut.Packages, PackageInfo{
				Package: pkgName,
				Version: pkgVersion,
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