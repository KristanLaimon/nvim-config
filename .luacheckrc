std = "luajit"
max_line_length = false

globals = {
	"vim",

	"krsnvim",
	"cli",
	"terminal",
	"fs",
	"console",
	"fetch",
	"import",
	"describe",
	"test",
	"expect",
	"it",
	"setTimeout",
	"clearTimeout",
	"setInterval",
	"clearInterval",

	"Neotree_Toggle",
	"Neotree_Refresh",
	"Neotree_Create_File",
	"Neotree_Create_Folder",
	"Neotree_Smart_Quit",
	"Smart_Close_Buffer",
	"AddOpenedFolder",
	"Is_File_Deleted",
	"BufferCleaner",
	"BunDap",
	"CapsLock",
	"CommandPalette",
	"ColorschemePreview",
	"ContextHelp",
	"DapBreakpoints",
	"DevServer",
	"DotnetCreator",
	"FileExplorer",
	"FontManager",
	"GitCenter",
	"ImageViewer",
	"InputModal",
	"LaunchCmp",
	"LaunchProfiles",
	"NugetManager",
	"PhpToolsModal",
	"ProjectTasks",
	"SmartCheck",
	"TailwindOrganizer",
	"TerminalManager",
	"TypeInjector",
	"Wsl",
	"Workspaces",
	"FindFilesGitignore",
	"FindFilesNoIgnore",
	"OpenFolderPicker",
	"OpenRecentProjects",

	"koreader",
	"Device",
	"Screen",
	"UIManager",
	"Widget",
	"Geom",
	"Event",
	"logger",
	"_",
	"T",
	"G_reader_settings",
	"G_defaults",
	"love",

	"krs_testing",
}

files["run_me.lua"] = {
	ignore = {
		"121", -- setting read-only field (os.exit patching in safe_dofile)
		"212/_.*", -- unused argument (the 'choice' param in cli.menu callback)
	},
}

files["schemas-langs/**"] = {
	ignore = {
		"211",  -- unused local variable
		"212",  -- unused argument
		"213",  -- unused loop variable
		"311",  -- value assigned but never used
		"411",  -- redefining variable
		"412",  -- redefining argument
		"431",  -- redefining global
	},
}
