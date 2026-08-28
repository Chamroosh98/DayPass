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
		"installer/init/globals.sh",
		"ui/lib/styles.sh",
		"ui/lib/box_utils.sh",
		"ui/lib/header.sh",
		"ui/lib/progress.sh",
		"ui/banner.sh",

		// 2. Low-Level System Detection & Package Management
		"installer/init/arch_detector.sh",
		"installer/pkg/manager.sh",

		// 3. Core System Modules
		"installer/init/zero_deps.sh",
		"modules/system/arch_check.sh",
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

		// 6. Proxy - Config Management
		"modules/proxy/config/config_storage.sh",
		"modules/proxy/config/subscription.sh",
		"modules/proxy/config/passwall_bridge.sh",
		"modules/proxy/config/config_manager.sh",

		// 7. Proxy - Other Modules
		"modules/proxy/routing.sh",
		"modules/proxy/node_balancer.sh",
		"modules/proxy/health_checker.sh",
		"modules/proxy/profile_manager.sh",
		
		// 8. Proxy - Cloudflare Clean IP
		"modules/proxy/cloudflare/core.sh",
		"modules/proxy/cloudflare/link_utils.sh",
		"modules/proxy/cloudflare/scanner.sh",
		"modules/proxy/cloudflare/applier.sh",
		"modules/proxy/cloudflare/menu.sh",

		// 9. Other Modules
		"modules/system/backup_restore.sh",
		"modules/system/maintenance.sh",
		"modules/service/service_manager.sh",

		// 10. Core Installer Logic & Package Processing
		"installer/init/install_core.sh",
		"modules/system/resource_checker.sh",
		"installer/pkg/resolver.sh",
		"installer/pkg/installer.sh",
		"installer/pkg/updater.sh",

		// 11. UI Components & Interactive Menus
		"ui/state.sh",
		"ui/menu/custom.sh",
		"ui/menu/mode.sh",
		"ui/menu/engine.sh",
		"ui/menu/language.sh",
		"ui/menu/geo.sh",
		"ui/review.sh",
		"ui/menu/passwall.sh",
		"ui/menu/network.sh",
		"ui/menu/proxy.sh",       
		"ui/menu/main.sh",
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