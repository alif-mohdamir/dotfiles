-- Pull in the wezterm API
local wezterm = require("wezterm")

-- This table will hold the configuration.
local config = {}

-- In newer versions of wezterm, use the config_builder which will
-- help provide clearer error messages
if wezterm.config_builder then
	config = wezterm.config_builder()
end

-- This is where you actually apply your config choices

-- For example, changing the color scheme:
config.color_scheme = "Tokyo Night"

local act = wezterm.action
config.keys = {
	{ key = "l", mods = "CMD|SHIFT", action = act.ActivateTabRelative(1) },
	{ key = "h", mods = "CMD|SHIFT", action = act.ActivateTabRelative(-1) },
	{ key = "j", mods = "CMD", action = act.ActivatePaneDirection("Down") },
	{ key = "k", mods = "CMD", action = act.ActivatePaneDirection("Up") },
	{ key = "h", mods = "CMD", action = act.ActivatePaneDirection("Left") },
	{ key = "l", mods = "CMD", action = act.ActivatePaneDirection("Right") },
	{ key = "x", mods = "CMD", action = act.CloseCurrentPane({ confirm = true }) },

	{ key = "|", mods = "CMD|SHIFT", action = act.SplitHorizontal({ domain = "CurrentPaneDomain" }) },
	{ key = "-", mods = "CMD|SHIFT", action = act.SplitVertical({ domain = "CurrentPaneDomain" }) },
	{ key = "D", mods = "CMD|SHIFT", action = act.ShowDebugOverlay },
}

-- and finally, return the configuration to wezterm
return config
