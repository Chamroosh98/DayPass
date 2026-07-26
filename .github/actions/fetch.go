package main

import (
	"archive/zip"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
)

type ArchConfig struct {
	Release       string `json:"release"`
	Architectures []struct {
		Name    string   `json:"name"`
		BaseURL string   `json:"base_url"`
		Feeds   []string `json:"feeds"`
	} `json:"architectures"`
}

type FeedIndex struct {
	Version      int               `json:"version"`
	Architecture string            `json:"architecture"`
	Packages     map[string]string `json:"packages"`
}

func zipDirectory(sourceDir, targetZip string) error {
	zipFile, err := os.Create(targetZip)
	if err != nil {
		return err
	}
	defer zipFile.Close()

	archive := zip.NewWriter(zipFile)
	defer archive.Close()

	return filepath.Walk(sourceDir, func(path string, info os.FileInfo, err error) error {
		if err != nil || info.IsDir() {
			return err
		}
		relPath, err := filepath.Rel(sourceDir, path)
		if err != nil {
			return err
		}
		file, err := os.Open(path)
		if err != nil {
			return err
		}
		defer file.Close()

		writer, err := archive.Create(relPath)
		if err != nil {
			return err
		}
		_, err = io.Copy(writer, file)
		return err
	})
}

func copyFile(src, dst string) error {
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

func downloadWithCurl(url, destPath string) error {
	cmd := exec.Command("curl", "--silent", "--show-error", "--location", "--fail", "-o", destPath, url)
	return cmd.Run()
}

func fileExists(path string) bool {
	info, err := os.Stat(path)
	if os.IsNotExist(err) {
		return false
	}
	return !info.IsDir() && info.Size() > 0
}

func main() {
	if len(os.Args) < 3 {
		fmt.Println("❌ Usage : go run fetch.go <architecture> <release_version> [release_type] [ow_version]")
		os.Exit(1)
	}
	targetArch := os.Args[1]
	releaseVersion := os.Args[2]

	releaseType := "release"
	if len(os.Args) > 3 && os.Args[3] != "" {
		releaseType = os.Args[3]
	}

	owVersion := "25"
	if len(os.Args) > 4 && os.Args[4] != "" {
		owVersion = os.Args[4]
	}

	configFile := fmt.Sprintf("config/architectures_%s.json", owVersion)
	if !fileExists(configFile) {
		// Fallback
		configFile = "config/architectures.json"
	}

	configData, err := os.ReadFile(configFile)
	if err != nil {
		fmt.Printf("❌ Failed to read arch config [%s]: %v\n", configFile, err)
		os.Exit(1)
	}

	var archConfig ArchConfig
	if err := json.Unmarshal(configData, &archConfig); err != nil {
		fmt.Printf("❌ Failed to parse json [%s]: %v\n", configFile, err)
		os.Exit(1)
	}

	persistentCacheDir := fmt.Sprintf(".cache/downloads/v%s/%s", owVersion, targetArch)
	baseDownloadDir := fmt.Sprintf("matrix-download/v%s/%s", owVersion, targetArch)
	zipWorkspaceDir := fmt.Sprintf("zip-workspace/v%s/%s", owVersion, targetArch)

	os.MkdirAll(persistentCacheDir, 0755)
	os.MkdirAll(baseDownloadDir, 0755)
	os.MkdirAll(zipWorkspaceDir, 0755)

	found := false
	for _, arch := range archConfig.Architectures {
		if arch.Name != targetArch {
			continue
		}
		found = true
		fmt.Printf("\n🗜️ Processing OpenWrt [%s] -> Arch [%s]\n", owVersion, targetArch)

		for _, feed := range arch.Feeds {
			feedCacheDir := filepath.Join(persistentCacheDir, feed)
			cdnOutputDir := baseDownloadDir                   
			zipFeedOutputDir := filepath.Join(zipWorkspaceDir, feed) 

			os.MkdirAll(feedCacheDir, 0755)
			os.MkdirAll(cdnOutputDir, 0755)
			os.MkdirAll(zipFeedOutputDir, 0755)

			feedURL := fmt.Sprintf("%s/%s", arch.BaseURL, feed)
			tempIndexPath := filepath.Join(feedCacheDir, "index.json")

			fmt.Printf("💰 Feed : %s\n", feed)
			if err := downloadWithCurl(feedURL+"/index.json", tempIndexPath); err != nil {
				fmt.Printf("❌ Failed to download index for [%s]\n", feed)
				continue
			}

			indexData, err := os.ReadFile(tempIndexPath)
			if err != nil {
				continue
			}

			var feedIdx FeedIndex
			if err := json.Unmarshal(indexData, &feedIdx); err != nil {
				fmt.Printf("⚠️ Formatting error on index [%s] : %v\n", feed, err)
				continue
			}

			cachedCount := 0
			downloadedCount := 0

			for pkgName, pkgVersion := range feedIdx.Packages {
				
				// detect extension in order to openwrt version
				pkgExt := ".apk"
				if owVersion == "24" {
					pkgExt = ".ipk"
				}

				apkFileName := fmt.Sprintf("%s-%s%s", pkgName, pkgVersion, pkgExt)


				cachePkgPath := filepath.Join(feedCacheDir, apkFileName)
				
				cdnPkgPath := filepath.Join(cdnOutputDir, apkFileName)
				zipPkgPath := filepath.Join(zipFeedOutputDir, apkFileName)
				
				pkgURL := fmt.Sprintf("%s/%s", feedURL, apkFileName)

				if !fileExists(cachePkgPath) {
					fmt.Printf("📥 Saved in Cache : [%-45s] ", apkFileName)
					if err := downloadWithCurl(pkgURL, cachePkgPath); err != nil {
						fmt.Println("❌ FAILED")
						os.Remove(cachePkgPath)
						continue
					} else {
						fmt.Println("✅ OK")
						downloadedCount++
					}
				} else {
					fmt.Printf("🔄 Cached : [%-45s]\n", apkFileName)
					cachedCount++
				}

				copyFile(cachePkgPath, cdnPkgPath)
				copyFile(cachePkgPath, zipPkgPath)
			}

			fmt.Printf("✅ Feed synchronized! (🔄 [%d] cached, 📥 [%d] downloaded)\n", cachedCount, downloadedCount)
		}
	}

	if !found {
		fmt.Printf("❌ Architecture [%s] not found in OpenWrt %s config\n", targetArch, owVersion)
		os.Exit(1)
	}

	var zipName string
	if releaseType == "release" || releaseType == "main" || releaseType == "stable" {
		zipName = fmt.Sprintf("DayPass_v%s_%s_%s.zip", owVersion, targetArch, releaseVersion)
	} else {
		zipName = fmt.Sprintf("DayPass_v%s_%s_%s_beta.zip", owVersion, targetArch, releaseVersion)
	}

	if err := zipDirectory(zipWorkspaceDir, zipName); err != nil {
		fmt.Printf("❌ Zipping failed : [%v]\n", err)
		os.Exit(1)
	}

	os.RemoveAll("zip-workspace")
	fmt.Printf("\n📦 Package created successfully : [%s]\n", zipName)
}