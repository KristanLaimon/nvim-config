return {
	dir = require("krs.core.lazyspec").for_module(),
	name = "krs_installer",
	cmd = {
		"LanguageManager",
		"KrsLanguageManager",
		"LanguageTooling",
		"KrsInstallDependencies",
		"KrsInstaller",
		"KrsSetup",
		"KrsSystemSetup",
		"KrsInstallSystemDependencies",
		"KrsInstallAgy",
		"AgyInstall",
		"InstallAgy",
		"KrsInstallClaude",
		"ClaudeInstall",
		"InstallClaude",
		"KrsInstallAll",
		"MasonInstallAll",
		"KrsSetupStatus",
		"KrsHealthCheck",
		"KrsSetupReset",
	},
	config = function()
		require("krs.core.installer").init()
	end,
}
