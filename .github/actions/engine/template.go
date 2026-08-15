package main

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

func generateInstallScript(outputFile string) error {
	fmt.Println("⌛ Processing Core Components with Go Engine for DayPass ...")
	
	branch := os.Getenv("GITHUB_REF_NAME")
	releaseType := os.Getenv("INPUT_RELEASE_TYPE")
	if branch == "" {
		branch = "beta" 
	}

	var scriptBuilder strings.Builder
	scriptBuilder.WriteString("#!/bin/sh\n\n")

	scriptBuilder.WriteString("###############################################################################\n")
	scriptBuilder.WriteString("# DayPass Installer (Auto-generated via Go Action)\n")
	scriptBuilder.WriteString("###############################################################################\n\n")

	scriptBuilder.WriteString("# Dynamic REPO_URL configuration\n")
	scriptBuilder.WriteString("if [ -z \"${REPO_URL:-}\" ]; then\n")
	if branch == "main" && releaseType != "beta" {
		scriptBuilder.WriteString("    REPO_URL=\"https://chamroosh98.github.io/DayPass\"\n")
	} else if releaseType == "beta" || branch == "beta" {
		scriptBuilder.WriteString("    REPO_URL=\"https://chamroosh98.github.io/DayPass/beta\"\n")
	} else {
		scriptBuilder.WriteString(fmt.Sprintf("    REPO_URL=\"https://chamroosh98.github.io/DayPass/%s\"\n", branch))
	}
	scriptBuilder.WriteString("fi\n")
	scriptBuilder.WriteString("export REPO_URL\n\n")

	// Cleaned & strict dependency-aware sourcing sequence
	installerFiles := []string{
		// 1. Core Globals, UI Base Libraries & Styles
		"installer/globals.sh",
		"ui/lib/styles.sh",
		"ui/lib/box_utils.sh",
		"ui/lib/header.sh",
		"ui/lib/progress.sh",
		"ui/banner.sh",

		// 2. Low-Level System Detection & Package Management
		"installer/arch_detector.sh",
		"installer/package_manager.sh",

		// 3. Core System Modules
		"modules/zero_deps.sh",
		"modules/version_check.sh",
		"modules/resource_monitor.sh",

		// 4. Network - Host
		"modules/network/host/network_info.sh",
		"modules/network/host/dns_fix.sh",
		"modules/network/host/lan_ip.sh",
		"modules/network/host/usb_wan.sh",
		"modules/network/host/wifi_wan.sh",
		"modules/network/host/wifi_ap.sh",
		"modules/network/host/load_balancer.sh",
		"modules/network/host/network_checker.sh",

		// 5. Network - Guest
		"modules/network/guest/network.sh",
		"modules/network/guest/qos.sh",

		// 6. Proxy Modules (New)
		"modules/proxy/config_manager.sh",
		"modules/proxy/routing.sh",
		"modules/proxy/node_balancer.sh",
		"modules/proxy/health_checker.sh",
		"modules/proxy/profile_manager.sh",

		// 7. Other Modules
		"modules/backup_restore.sh",
		"modules/maintenance.sh",
		"modules/service_manager.sh",

		// 8. Core Installer Logic & Package Processing
		"installer/install_core.sh",
		"installer/resource_checker.sh",
		"installer/package_resolver.sh",
		"installer/package_installer.sh",
		"installer/package_updater.sh",

		// 9. UI Components & Interactive Menus
		"ui/state.sh",
		"ui/menu_custom.sh",
		"ui/menu_mode.sh",
		"ui/engine_menu.sh",
		"ui/menu_language.sh",
		"ui/menu_geo.sh",
		"ui/review.sh",
		"ui/menu_package.sh",
		"ui/menu_network.sh",
		"ui/menu_proxy.sh",       
		"ui/main_menu.sh",
		"ui/installer_ui.sh",
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
			// Strip duplicate shebangs from individual modules
			if !strings.HasPrefix(line, "#!") {
				scriptBuilder.WriteString(line)
				scriptBuilder.WriteByte('\n')
			}
		}
		fmt.Printf("✅ [%s] appended dynamically!\n", filepath.Base(file))
	}

	// Cleaned Runtime Execution Pipeline
	scriptBuilder.WriteString(`

###############################################################################
# Runtime Execution Pipeline
###############################################################################
DEPLOYMENT_FAILED=0

# 1. Pre-flight connectivity check
network_check || exit 1

# 2. System environment discovery & version validation
check_version || exit 1
detect_system_architecture

# 3. Core dependency initialization => with delay (2 secs) to ensure system stability after installing the dnsmasq-full tool!
deploy_system_dependencies
sleep 2
initialize_installer

# 4. Optional Automatic UCI Config Backup
if command -v backup_configs >/dev/null 2>&1; then
    backup_configs
fi

# 5. Interactive UI Launch
clear
reset_state
main_menu

# 6. Clean Exit
echo
log_success "👋 DayPass session finished!"
exit 0

`)

	if err := os.MkdirAll(filepath.Dir(outputFile), 0755); err != nil {
		return err
	}
	return os.WriteFile(outputFile, []byte(scriptBuilder.String()), 0755)
}