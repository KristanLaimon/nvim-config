---@meta
-- KOReader E-Book Reader Global Types Definition
-- Injected dynamically by KRS Type Injector
--
-- Schema version: KOReader v2026.07.2-38-g694c1c8b7 (see package.json in
-- this folder; bump it whenever this file is regenerated against a newer
-- KOReader checkout).
--
-- SCOPE NOTE: real KOReader plugin code almost never touches a bare global
-- for Device/Screen/UIManager/logger/etc. -- every file does
-- `local Device = require("device")`, `local Screen =
-- require("device").screen`, `local UIManager = require("ui/uimanager")`,
-- `local logger = require("logger")`, `local _ = require("gettext")`
-- (verified against koreader/frontend/pluginloader.lua and this project's
-- own src/*.lua). The globals below exist purely so ad-hoc snippets that
-- reference these names directly still get completion; they do NOT make
-- `require("device")` itself typed, since this schema is a hand-written
-- stub, not the real annotated source tree. The only genuine bare globals
-- KOReader sets (no `local`, in reader.lua) are `G_reader_settings` and
-- `G_defaults`, added below.

---@class koreader.device
---@field hasKeys boolean Whether physical keys/buttons are available
---@field isTouch boolean Whether touch input is supported
---@field screen Screen Screen display object reference
---@field input table Input handler reference
---@field power table Power management reference
---@field model string Device model identifier
---@field display table Display hardware driver
---@field isKindle fun(): boolean Check if running on Amazon Kindle
---@field isKobo fun(): boolean Check if running on Kobo e-Reader
---@field isPocketBook fun(): boolean Check if running on PocketBook
---@field isAndroid fun(): boolean Check if running on Android OS
---@field isDesktop fun(): boolean Check if running in desktop emulator mode
---@field getPowerDevice fun(): table Get power device controller
---@field hasHWBackKey fun(): boolean Check if hardware back key exists

---@class koreader.ui
---@field uimanager UIManager Global UI manager singleton
---@field widget Widget Base widget component
---@field geometry Geom Geometry utilities module
---@field font table Font handling and typesetting module
---@field render table Canvas rendering module
---@field tappable table Tappable widget mixin module
---@field menu table Menu widget module
---@field dialog table Dialog widget module
---@field notification table Notification overlay module
---@field infomessage table Info message widget module

---@class koreader.view
---@field readerui table Reader core UI controller
---@field document table Active document model
---@field readerview table Main reader view widget
---@field readerfooter table Reader status footer widget
---@field pagedocument table Page-based document view
---@field epubdocument table EPUB document view engine
---@field pdfdocument table PDF document view engine

---@class koreader.event
---@field Event Event Event object constructor
---@field Gesture table Gesture event types
---@field Key table Key code constants
---@field Touch table Touch event data
---@field Tap table Tap gesture data
---@field Swipe table Swipe gesture data
---@field Hold table Touch hold event data

---@class koreader.dispatcher
---@field register fun(action: string, handler: fun(...: any): any): nil Register an action handler
---@field dispatch fun(action: string, ...: any): any Dispatch an action by name
---@field unregister fun(action: string): nil Unregister an action handler
---@field send fun(event: Event): nil Send event to dispatcher
---@field broadcast fun(event: Event): nil Broadcast event to all subscribers

---@class koreader.logger
---@field debug fun(...: any): nil Log debug message
---@field info fun(...: any): nil Log info message
---@field warn fun(...: any): nil Log warning message
---@field err fun(...: any): nil Log error message
---@field dbg fun(...: any): nil Log verbose debug trace
---@field p fun(...: any): nil Pretty-print log object
---@field format fun(fmt: string, ...: any): string Format string helper
---@field setLogLevel fun(level: string|number): nil Set global log verbosity level

---@class Screen
---@field w integer Screen width in pixels
---@field h integer Screen height in pixels
---@field getWidth fun(self: Screen): integer Get screen width
---@field getHeight fun(self: Screen): integer Get screen height
---@field refresh fun(self: Screen, mode?: string, x?: integer, y?: integer, w?: integer, h?: integer): nil Trigger e-ink refresh
---@field clear fun(self: Screen): nil Clear screen buffer
---@field getScreenMode fun(self: Screen): string Get screen rotation/mode
---@field toggleInvert fun(self: Screen): nil Toggle night/inverted mode
---@field dither fun(self: Screen): nil Apply dithering to buffer

---@class UIManager
---@field show fun(self: UIManager, widget: Widget): nil Display a widget modal or view
---@field close fun(self: UIManager, widget: Widget): nil Close an open widget view
---@field nextTick fun(self: UIManager, callback: fun()): nil Schedule callback on next event loop tick
---@field scheduleIn fun(self: UIManager, delay: number, callback: fun()): table Schedule callback after delay in seconds
---@field unschedule fun(self: UIManager, handle: table): nil Cancel scheduled callback
---@field getActiveWidget fun(self: UIManager): Widget Get current focused widget
---@field handleEvent fun(self: UIManager, event: Event): boolean Dispatch event through widget tree
---@field broadcastEvent fun(self: UIManager, event: Event): nil Broadcast event to all active widgets

---@class Widget
---@field dimen Geom Widget bounding box geometry
---@field new fun(self: Widget, o?: table): Widget Create new widget instance
---@field paintTo fun(self: Widget, bb: table, x: integer, y: integer): nil Render widget to screen buffer
---@field handleEvent fun(self: Widget, event: Event): boolean Process incoming UI event
---@field getSize fun(self: Widget): Geom Get widget layout bounds
---@field layout fun(self: Widget, width: integer, height: integer): nil Calculate widget layout

---@class Geom
---@field x integer X coordinate
---@field y integer Y coordinate
---@field w integer Width dimension
---@field h integer Height dimension
---@field new fun(self: Geom, o?: {x?: integer, y?: integer, w?: integer, h?: integer}): Geom Create geometry rectangle
---@field intersect fun(self: Geom, g: Geom): Geom Calculate intersection bounds
---@field contains fun(self: Geom, x: integer, y: integer): boolean Test point containment
---@field copy fun(self: Geom): Geom Clone geometry object

---@class Event
---@field args any Event payload data
---@field new fun(type: string, ...: any): Event Create new event instance

---@class Device : koreader.device
---@class logger : koreader.logger

---@class koreader
---@field device koreader.device Hardware and device capabilities
---@field ui koreader.ui UI toolkit and widget framework
---@field view koreader.view Reader view and document engines
---@field event koreader.event Event models and gesture handling
---@field dispatcher koreader.dispatcher Event and action dispatcher
---@field logger koreader.logger Logging utilities
koreader = koreader or {}

---@type Device
Device = Device or {}

---@type Screen
Screen = Screen or {}

---@type UIManager
UIManager = UIManager or {}

---@type Widget
Widget = Widget or {}

---@type Geom
Geom = Geom or {}

---@type Event
Event = Event or {}

---@type logger
logger = logger or {}

---@type fun(msg: string): string
_ = _ or function(msg)
	return msg
end

---@type fun(msg: string): string
T = T or function(msg)
	return msg
end

---@class LuaSettings
---@field readSetting fun(self: LuaSettings, key: string, default?: any): any Read a stored value, or `default` when absent
---@field saveSetting fun(self: LuaSettings, key: string, value: any): LuaSettings Store a value under `key`
---@field delSetting fun(self: LuaSettings, key: string): LuaSettings Remove a stored value
---@field has fun(self: LuaSettings, key: string): boolean Whether `key` is present
---@field hasNot fun(self: LuaSettings, key: string): boolean Whether `key` is absent
---@field isTrue fun(self: LuaSettings, key: string): boolean Whether `key` is present and truthy
---@field isFalse fun(self: LuaSettings, key: string): boolean Whether `key` is present and falsy
---@field nilOrTrue fun(self: LuaSettings, key: string): boolean Whether `key` is absent or truthy
---@field nilOrFalse fun(self: LuaSettings, key: string): boolean Whether `key` is absent or falsy
---@field toggle fun(self: LuaSettings, key: string): LuaSettings Flip a boolean setting
---@field child fun(self: LuaSettings, key: string): LuaSettings Get/create a nested settings table
---@field flush fun(self: LuaSettings): LuaSettings Persist to disk
---@field close fun(self: LuaSettings): nil Flush and release the file handle

--- Real bare global (no `local` in reader.lua): per-document/global reader settings store.
---@type LuaSettings
G_reader_settings = G_reader_settings or {}

--- Real bare global (no `local` in reader.lua): app-wide defaults store (`defaults.lua`/`defaults.persistent.lua`).
---@type LuaSettings
G_defaults = G_defaults or {}
