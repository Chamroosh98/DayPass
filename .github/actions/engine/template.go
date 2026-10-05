package main

import (
	"bytes"
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
		"ui/banner.sh",
		"ui/lib/header.sh",
		"ui/lib/progress.sh",
		"ui/lib/help.sh",
		"ui/lib/nav.sh",

		// 2. Network — Host Bootstrap (proxy, Worker mirror, wizard)
		"modules/mirror/http_request.sh",
		"modules/network/relays/ssh/reverse_tunnel.sh",
		"modules/network/relays/cloudflare/worker.sh",
		"modules/network/relays/wizard.sh",

		// 3. Low-Level System Detection & Package Management
		"installer/init/arch_detector.sh",
		"installer/pkg/manager.sh",

		// 4. Core System Modules
		"installer/init/zero_deps.sh",
		"modules/system/arch_check.sh",

		// 5. Network - Host
		"modules/network/info/discover.sh",
		"modules/network/info/fetch.sh",
		"ui/menu/network_ip.sh",
		"modules/network/info/panel.sh",
		"modules/network/info/speed.sh",
		"modules/network/info/network_info.sh",
		"modules/network/dns/recovery.sh",
		"modules/network/interfaces/lan/lan_ip.sh",
		"modules/network/interfaces/usb/deps.sh",
		"modules/network/interfaces/usb/detect.sh",
		"modules/network/interfaces/usb/usb_wan.sh",
		"modules/network/interfaces/usb/restore.sh",
		"modules/network/interfaces/usb/dashboard.sh",
		"modules/network/interfaces/wan/wan_state.sh",
		"modules/network/interfaces/wifi/wifi_wan.sh",
		"modules/network/interfaces/wifi/wifi_ap.sh",
		"modules/network/routing/load_balancing/load_balancer.sh",
		"modules/network/connectivity/diagnostics/network_checker.sh",

		// 5b. Network - DNS Manager
		"modules/network/dns/core.sh",
		"modules/network/dns/modes/system.sh",
		"modules/network/dns/modes/secure.sh",
		"modules/network/dns/modes/tunnel.sh",
		"modules/network/dns/modes/hybrid.sh",
		"modules/network/dns/apply.sh",
		"modules/network/dns/ui/menu.sh",

		// 6. Network - Guest
		"modules/network/interfaces/guest/network.sh",
		"modules/network/qos/guest/qos.sh",

		// 7. Proxy - Config Management
		"modules/network/profiles/storage.sh",
		"modules/network/profiles/subscription.sh",
		"modules/network/transports/transport_bridge.sh",
		"modules/network/transports/drivers/core_common.sh",
		"modules/network/transports/drivers/passwall.sh",
		"modules/network/transports/drivers/singbox.sh",
		"modules/network/transports/drivers/xray.sh",
		"modules/network/transports/drivers/wireguard.sh",
		"modules/network/transports/drivers/openvpn.sh",
		"modules/network/profiles/manager.sh",

		// 8. Proxy - Other Modules
		"modules/network/routing/core.sh",
		"modules/network/balancing/node_balancer.sh",
		"modules/network/connectivity/checker/health_checker.sh",
		"modules/network/profiles/profile_manager.sh",

		// 9. Proxy - Cloudflare Clean IP
		"modules/network/relays/cloudflare/core.sh",
		"modules/network/relays/cloudflare/link_utils.sh",
		"modules/network/relays/cloudflare/scanner.sh",
		"modules/network/relays/cloudflare/applier.sh",
		"ui/menu/cf.sh",

		// 10. Other Modules
		"modules/system/backup_restore.sh",
		"ui/lib/banner.sh",
		"modules/system/banner.sh",
		"modules/system/maintenance.sh",
		"modules/service/service_manager.sh",

		// 11. Core Installer Logic & Package Processing
		"installer/init/install_core.sh",
		"modules/system/resource_checker.sh",
		"installer/pkg/resolver.sh",
		"installer/pkg/package_catalog.sh",
		"installer/pkg/profile_overview.sh",
		"installer/pkg/manifest_manager.sh",
		"installer/pkg/installer.sh",
		"installer/pkg/updater.sh",
		"installer/pkg/purge.sh",

		// 12. UI Components & Interactive Menus
		"ui/lib/state.sh",
		"ui/menu/custom.sh",
		"ui/menu/mode.sh",
		"ui/menu/engine.sh",
		"ui/menu/language.sh",
		"ui/menu/geo.sh",
		"ui/lib/review.sh",
		"ui/menu/packages.sh",
		"ui/menu/hardware.sh",
		"ui/menu/guest_network.sh",
		"ui/menu/proxy_engine.sh",
		"ui/menu/proxy.sh",
		"ui/menu/diagnostics.sh",
		"ui/menu/system.sh",
		"ui/menu/help.sh",
		"ui/menu/main.sh",
		"ui/lib/installer_ui.sh",
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

	// Embedded package profiles read by load_package_profiles in installer/pkg/resolver.sh
	profilesFile := "config/package_profiles.json"
	if data, err := os.ReadFile(profilesFile); err == nil {
		scriptBuilder.WriteString(fmt.Sprintf("\n# 📄 Source : %s (embedded)\n", filepath.Base(profilesFile)))
		scriptBuilder.WriteString("daypass_embedded_profiles()\n{\n    cat <<'DAYPASS_PROFILES_JSON'\n")
		scriptBuilder.Write(data)
		if len(data) > 0 && data[len(data)-1] != '\n' {
			scriptBuilder.WriteByte('\n')
		}
		scriptBuilder.WriteString("DAYPASS_PROFILES_JSON\n}\n")
		fmt.Printf("✅ [%s] embedded!\n", filepath.Base(profilesFile))
	} else {
		fmt.Printf("⚠️ Warning : File [%s] not found, skipping ...\n", profilesFile)
	}

	catalogFile := "config/package_catalog.json"
	if data, err := os.ReadFile(catalogFile); err == nil {
		scriptBuilder.WriteString(fmt.Sprintf("\n# 📄 Source : %s (embedded)\n", filepath.Base(catalogFile)))
		scriptBuilder.WriteString("daypass_embedded_catalog()\n{\n    cat <<'DAYPASS_CATALOG_JSON'\n")
		scriptBuilder.Write(data)
		if len(data) > 0 && data[len(data)-1] != '\n' {
			scriptBuilder.WriteByte('\n')
		}
		scriptBuilder.WriteString("DAYPASS_CATALOG_JSON\n}\n")
		fmt.Printf("✅ [%s] embedded!\n", filepath.Base(catalogFile))
	} else {
		fmt.Printf("⚠️ Warning : File [%s] not found, skipping ...\n", catalogFile)
	}

	// Embedded Cloudflare Worker mirror (config/worker.js). The menu tells
	// the user to paste this script in the Cloudflare dashboard editor.
	// cf-worker/worker.js is the same script, published for the browser
	// deploy button. Refuse the build if the two copies drift.
	mirrorFile := "config/worker.js"
	deployCopy := "cf-worker/worker.js"
	canon, err := os.ReadFile(mirrorFile)
	if err != nil {
		return fmt.Errorf("read %s: %w", mirrorFile, err)
	}
	deployed, err := os.ReadFile(deployCopy)
	if err != nil {
		return fmt.Errorf("read %s: %w", deployCopy, err)
	}
	if !bytes.Equal(canon, deployed) {
		return fmt.Errorf("%s drifted from %s — copy %s onto %s", deployCopy, mirrorFile, mirrorFile, deployCopy)
	}
	scriptBuilder.WriteString(fmt.Sprintf("\n# 📄 Source : %s (embedded)\n", filepath.Base(mirrorFile)))
	scriptBuilder.WriteString("daypass_embedded_worker_js()\n{\n    cat <<'DAYPASS_WORKER_JS'\n")
	scriptBuilder.Write(canon)
	if len(canon) > 0 && canon[len(canon)-1] != '\n' {
		scriptBuilder.WriteByte('\n')
	}
	scriptBuilder.WriteString("DAYPASS_WORKER_JS\n}\n")
	fmt.Printf("✅ [%s] embedded!\n", filepath.Base(mirrorFile))

	// Cleaned Runtime Execution Pipeline
	scriptBuilder.WriteString(`

###############################################################################
# Runtime Execution Pipeline
###############################################################################
DEPLOYMENT_FAILED=0

# 1. Pre-flight network bootstrap (skipped when a mirror or proxy is already set)
network_bootstrap_startup

# 2. Pre-flight connectivity check
network_check || exit 1

# 3. System environment discovery & version validation
check_version || exit 1
detect_system_architecture

# 4. Core dependency initialization => with delay (2 secs) to ensure system stability after installing the dnsmasq-full tool!
deploy_system_dependencies
initialize_installer

# 5. Optional Automatic UCI Config Backup
if command -v backup_configs >/dev/null 2>&1; then
    backup_configs
fi

# 6. Replace the OpenWrt SSH/console banner (/etc/banner)
if command -v system_banner_post_install >/dev/null 2>&1; then
    system_banner_post_install
fi

# 7. Interactive UI Launch
clear
reset_state
main_menu

# 8. Clean Exit
echo
log_success "👋 DayPass session finished!"
exit 0

`)

	if err := os.MkdirAll(filepath.Dir(outputFile), 0755); err != nil {
		return err
	}
	return os.WriteFile(outputFile, []byte(scriptBuilder.String()), 0755)
}
