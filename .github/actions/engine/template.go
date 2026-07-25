package main

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

func generateInstallScript(outputFile string) error {
	fmt.Println("⌛ Processing Core Components with Go Engine ...")
	
	branch := os.Getenv("GITHUB_REF_NAME")
	if branch == "" {
		branch = "dev" 
	}

	var scriptBuilder strings.Builder
	scriptBuilder.WriteString("#!/bin/sh\n\n")
	// scriptBuilder.WriteString("#!/bin/sh\nset -eu\n\n")

	scriptBuilder.WriteString("###############################################################################\n")
	scriptBuilder.WriteString("# DayPass Installer (Auto-generated via Go Action)\n")
	scriptBuilder.WriteString("###############################################################################\n\n")

	scriptBuilder.WriteString("# Dynamic REPO_URL configuration\n")
	scriptBuilder.WriteString("if [ -z \"${REPO_URL:-}\" ]; then\n")
	if branch == "main" {
		scriptBuilder.WriteString("    REPO_URL=\"https://chamroosh98.github.io/DayPass\"\n")
	} else {
		scriptBuilder.WriteString(fmt.Sprintf("    REPO_URL=\"https://chamroosh98.github.io/DayPass/%s\"\n", branch))
	}
	scriptBuilder.WriteString("fi\n")
	scriptBuilder.WriteString("export REPO_URL\n\n")

	installerFiles := []string{
		// 1. Core Installer Logic
		"installer/network_checker.sh",
		"installer/package_manager.sh", 
		"installer/install_core.sh",
		"installer/package_deployer.sh",
		"installer/package_resolver.sh",

		// 2. UI Base Libraries & Styles
		"ui/lib/styles.sh",
		"ui/lib/box_utils.sh",
		"ui/lib/header.sh",
		"ui/lib/progress.sh",
		"ui/banner.sh",
		
		// 3. Hardware & System Modules
		"modules/zero_deps.sh",
		"modules/version_check.sh",
		"modules/system_info.sh",
		"modules/network_info.sh",
		"modules/resource_monitor.sh",
		"modules/dns_fix.sh",

		// 4. UI Components & Menus
		
		"ui/state.sh",
		"ui/menu_recommended.sh",
		"ui/menu_custom.sh",
		"ui/menu_mode.sh",
		"ui/engine_menu.sh",
		"ui/menu_language.sh",
		"ui/menu_geo.sh",
		"ui/review.sh",
		"ui/menu_package.sh",
		"ui/main_menu.sh",
	}

	for _, file := range installerFiles {
		data, err := os.ReadFile(file)
		if err != nil {
			fmt.Printf("⚠️ Warning : File [%s] not found, skipping ...\n", file)
			continue
		}
		
		scriptBuilder.WriteString(fmt.Sprintf("\n# 📄 Source : %s\n", filepath.Base(file)))
		lines := strings.Split(string(data), "\n")
		for _, line := range lines {
			
			if !strings.HasPrefix(line, "#!") {
				scriptBuilder.WriteString(line + "\n")
			}
		}
		fmt.Printf("✅ [%s] appended dynamically!\n", filepath.Base(file))
	}


	scriptBuilder.WriteString(`
###############################################################################
# Runtime Execution Pipeline
###############################################################################
DEPLOYMENT_FAILED=0

# 🔴🔴🔴🔴🔴🔴🔴 The execution order of the modules is important! 🔴🔴🔴🔴🔴🔴🔴
# ============= Checking network connection =============
network_check || exit 1

# ============= Installing requirements =================
deploy_system_dependencies

# Continue initialization
check_version
detect_arch
initialize_installer

# ============= Pre-TUI Smooth Transition =============
for i in 3 2 1; do
    printf "\r🚀 Launching DayPass Interactive UI in \033[1;33m%d\033[0m seconds... (Press \033[1;36m[Enter]\033[0m to skip) " "$i"
    if read -t 1 -r; then
        break
    fi
done

# Launching TUI Interface
clear
reset_state
main_menu

# Execution
deploy_targeted_packages

echo
echo "🎉 DayPass installation completed successfully! ;))"
exit 0
`)


	os.MkdirAll(filepath.Dir(outputFile), 0755)
	return os.WriteFile(outputFile, []byte(scriptBuilder.String()), 0755)
}