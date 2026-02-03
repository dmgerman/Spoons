--- === ClipboardTool ===
---
--- Keep a history of the clipboard for text entries and manage the entries with a context menu
---
--- Originally based on TextClipboardHistory.spoon by Diego Zamboni with additional functions provided by a context menu
--- and on [code by VFS](https://github.com/VFS/.hammerspoon/blob/master/tools/clipboard.lua), but with many changes and some contributions and inspiration from [asmagill](https://github.com/asmagill/hammerspoon-config/blob/master/utils/_menus/newClipper.lua).
---
--- Download: [https://github.com/Hammerspoon/Spoons/raw/master/Spoons/ClipboardTool.spoon.zip](https://github.com/Hammerspoon/Spoons/raw/master/Spoons/ClipboardTool.spoon.zip)
---
--- ## Password Detection
---
--- This spoon includes automatic detection and hiding of password-like entries in the clipboard
--- history. When enabled (`hide_passwords = true`), sensitive entries are displayed as
--- `[hidden - N chars]` instead of showing their actual content. The detection uses a 3-step
--- algorithm to minimize false positives while catching real passwords:
---
--- ### Step 1: Allowlist Check (`passNotInAllowlist`)
--- Immediately allows (does NOT mask) strings matching these patterns:
--- * UUIDs (e.g., `550e8400-e29b-41d4-a716-446655440000`)
--- * ULIDs (26 characters, Crockford Base32)
--- * Hex hashes (exactly 32, 40, or 64 hex characters for MD5/SHA1/SHA256)
--- * Base64 with padding (length multiple of 4, ends with `=`)
--- * Pure numbers or decimals
--- * ISO timestamps/dates (e.g., `2024-01-15`, `2024-01-15T10:30:00Z`)
--- * IP addresses (IPv4 and IPv6)
--- * URLs (contains `://`)
--- * Filenames (contains `/` or ends with `.extension`)
--- * Strings with more than `password_max_newlines` newlines
---
--- ### Step 2: Structural Filter (`passHasStructure`)
--- Only considers a string as potentially password-like if ALL of:
--- * Length >= `password_min_length` (default 8)
--- * Contains no spaces
--- * Not mostly (>=70%) digits
--- * Not mostly (>=70%) hex characters
--- * Contains at least 2 of: lowercase, uppercase, digits, symbols
---
--- ### Step 3: Entropy Check (`passHighEntropy`)
--- Finally applies Shannon entropy threshold:
--- * Entropy >= `password_entropy_threshold` (default 3.5 bits/char)
---
--- Only strings that pass ALL three steps are masked. This approach eliminates most false
--- positives (URLs, UUIDs, hashes, filenames) while still catching high-entropy passwords.
---
--- ### Reveal Controls
--- While the chooser is open:
--- * `Cmd-R`: Toggle reveal for the currently selected item only
--- * `Shift-Cmd-R`: Toggle reveal for ALL password-like items

local obj={}
obj.__index = obj

-- Metadata
obj.name = "ClipboardTool"
obj.version = "0.8"
obj.author = "Alfred Schilken <alfred@schilken.de>"
obj.homepage = "https://github.com/Hammerspoon/Spoons"
obj.license = "MIT - https://opensource.org/licenses/MIT"

local getSetting = function(label, default) return hs.settings.get(obj.name.."."..label) or default end
local setSetting = function(label, value)   hs.settings.set(obj.name.."."..label, value); return value end

--- ClipboardTool.frequency
--- Variable
--- Speed in seconds to check for clipboard changes. If you check too frequently, you will degrade performance, if you check sparsely you will loose copies. Defaults to 0.8.
obj.frequency = 0.8

--- ClipboardTool.hist_size
--- Variable
--- How many items to keep on history. Defaults to 100
obj.hist_size = 100

--- ClipboardTool.max_entry_size
--- Variable
--- maximum size of a text entry
obj.max_entry_size = 4990

--- ClipboardTool.max_size
--- Variable
--- Whether to check the maximum size of an entry. Defaults to `false`.
obj.max_size = getSetting('max_size', false)

--- ClipboardTool.show_copied_alert
--- Variable
--- If `true`, show an alert when a new item is added to the history, i.e. has been copied.
obj.show_copied_alert = true

--- ClipboardTool.honor_ignoredidentifiers
--- Variable
--- If `true`, check the data identifiers set in the pasteboard and ignore entries which match those listed in `ClipboardTool.ignoredIdentifiers`. The list of identifiers comes from http://nspasteboard.org. Defaults to `true`
obj.honor_ignoredidentifiers = true

--- ClipboardTool.paste_on_select
--- Variable
--- Whether to auto-type the item when selecting it from the menu. Can be toggled on the fly from the chooser. Defaults to `false`.
obj.paste_on_select = getSetting('paste_on_select', false)

--- ClipboardTool.logger
--- Variable
--- Logger object used within the Spoon. Can be accessed to set the default log level for the messages coming from the Spoon.
obj.logger = hs.logger.new('ClipboardTool')

--- ClipboardTool.ignoredIdentifiers
--- Variable
--- Types of clipboard entries to ignore, see http://nspasteboard.org. Code from https://github.com/asmagill/hammerspoon-config/blob/master/utils/_menus/newClipper.lua.
---
--- Notes:
---  * Default value (don't modify unless you know what you are doing):
--- ```
---  {
---     ["de.petermaurer.TransientPasteboardType"] = true, -- Transient : Textpander, TextExpander, Butler
---     ["com.typeit4me.clipping"]                 = true, -- Transient : TypeIt4Me
---     ["Pasteboard generator type"]              = true, -- Transient : Typinator
---     ["com.agilebits.onepassword"]              = true, -- Confidential : 1Password
---     ["org.nspasteboard.TransientType"]         = true, -- Universal, Transient
---     ["org.nspasteboard.ConcealedType"]         = true, -- Universal, Concealed
---     ["org.nspasteboard.AutoGeneratedType"]     = true, -- Universal, Automatic
---  }
--- ```
obj.ignoredIdentifiers = {
   ["de.petermaurer.TransientPasteboardType"] = true, -- Transient : Textpander, TextExpander, Butler
   ["com.typeit4me.clipping"]                 = true, -- Transient : TypeIt4Me
   ["Pasteboard generator type"]              = true, -- Transient : Typinator
   ["com.agilebits.onepassword"]              = true, -- Confidential : 1Password
   ["org.nspasteboard.TransientType"]         = true, -- Universal, Transient
   ["org.nspasteboard.ConcealedType"]         = true, -- Universal, Concealed
   ["org.nspasteboard.AutoGeneratedType"]     = true, -- Universal, Automatic
}

--- ClipboardTool.deduplicate
--- Variable
--- Whether to remove duplicates from the list, keeping only the latest one. Defaults to `true`.
obj.deduplicate = true

--- ClipboardTool.hide_passwords
--- Variable
--- Whether to hide password-like entries in the chooser display. Defaults to `true`.
obj.hide_passwords = true

--- ClipboardTool.password_entropy_threshold
--- Variable
--- Minimum Shannon entropy (bits per character) to consider a string password-like. Defaults to 3.5.
--- Only applied after allowlist and structural checks pass.
obj.password_entropy_threshold = 3.5

--- ClipboardTool.password_min_length
--- Variable
--- Minimum length for a string to be considered password-like. Defaults to 8.
obj.password_min_length = 8

--- ClipboardTool.password_max_newlines
--- Variable
--- Maximum number of newlines for a string to be considered password-like. Defaults to 1.
obj.password_max_newlines = 1

--- ClipboardTool.show_in_menubar
--- Variable
--- Whether to show a menubar item to open the clipboard history. Defaults to `true`
obj.show_in_menubar = true

--- ClipboardTool.menubar_title
--- Variable
--- String to show in the menubar if `ClipboardTool.show_in_menubar` is `true`. Defaults to `"\u{1f4cb}"`, which is the [Unicode clipboard character](https://codepoints.net/U+1F4CB)
obj.menubar_title   = "\u{1f4cb}"

--- ClipboardTool.display_max_length
--- Variable
--- Number of characters to which each clipboard item will be truncated, when displaying in the menu. This only truncates in display, the full content will be used for searching and for pasting.
obj.display_max_length = 200

----------------------------------------------------------------------

-- Internal variable - Chooser/menu object
obj.selectorobj = nil
-- Internal variable - Cache for focused window to work around the current window losing focus after the chooser comes up
obj.prevFocusedWindow = nil
-- Internal variable - Timer object to look for pasteboard changes
obj.timer = nil
-- Internal variable - Whether to reveal ALL password-like entries (toggled by Shift-Cmd-R)
obj.revealPasswords = false
-- Internal variable - Index of single item to reveal (set by Cmd-R)
obj.revealedItemIndex = nil
-- Internal variable - Hotkey for revealing current item (Cmd-R)
obj.revealCurrentHotkey = nil
-- Internal variable - Hotkey for revealing all items (Shift-Cmd-R)
obj.revealAllHotkey = nil

local pasteboard = require("hs.pasteboard") -- http://www.hammerspoon.org/docs/hs.pasteboard.html
local hashfn   = require("hs.hash").MD5

-- Constants for password detection
local MOSTLY_THRESHOLD = 0.70  -- 70% threshold for "mostly digits" or "mostly hex"
local PASSWORD_SYMBOLS = "[!@#$%%%^&*()%-_=+%[%]{}|;:',.<>?/\\`~\"]"

-- Calculate Shannon entropy (bits per character) for a string
local function calculateEntropy(str)
   if not str or #str == 0 then return 0 end

   local freq = {}
   local len = #str
   for i = 1, len do
      local char = str:sub(i, i)
      freq[char] = (freq[char] or 0) + 1
   end

   local entropy = 0
   for _, count in pairs(freq) do
      local p = count / len
      entropy = entropy - p * math.log(p) / math.log(2)
   end

   return entropy
end

-- Step 1: Check if string is NOT in the allowlist (returns true if could be password)
-- Allowlist includes: UUIDs, ULIDs, hex hashes, Base64, numbers, timestamps, IPs, URLs, filenames
local function passNotInAllowlist(str, maxNewlines)
   if not str then return false end

   local len = #str

   -- Check newlines - if too many, it's not a password
   local newline_count = 0
   for _ in str:gmatch("\n") do
      newline_count = newline_count + 1
   end
   if newline_count > maxNewlines then
      return false
   end

   -- UUID: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
   if str:match("^[0-9a-fA-F]?[0-9a-fA-F]?[0-9a-fA-F]?[0-9a-fA-F]?[0-9a-fA-F]?[0-9a-fA-F]?[0-9a-fA-F]?[0-9a-fA-F]%-[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]%-[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]%-[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]%-[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]$") then
      return false
   end

   -- ULID: 26 characters, Crockford Base32 (0-9, A-Z excluding I, L, O, U)
   if len == 26 and str:match("^[0-9A-HJKMNP-TV-Z]+$") then
      return false
   end

   -- Hex hashes: exactly 32 (MD5), 40 (SHA1), or 64 (SHA256) hex characters
   if (len == 32 or len == 40 or len == 64) and str:match("^[0-9a-fA-F]+$") then
      return false
   end

   -- Base64 with padding: ends with = or ==, length multiple of 4, valid chars
   if len % 4 == 0 and str:match("=+$") and str:match("^[A-Za-z0-9+/]+=*$") then
      return false
   end

   -- Pure numbers or decimals (including negative)
   if str:match("^%-?[0-9]+%.?[0-9]*$") then
      return false
   end

   -- ISO timestamps/dates: 2024-01-15, 2024-01-15T10:30:00, etc.
   if str:match("^%d%d%d%d%-%d%d%-%d%d") then
      return false
   end

   -- IPv4 address
   if str:match("^%d+%.%d+%.%d+%.%d+$") then
      return false
   end

   -- IPv6 address (simplified: contains multiple colons and hex)
   if str:match("^[0-9a-fA-F:]+$") and str:match(":.*:") then
      return false
   end

   -- URLs: contains ://
   if str:match("://") then
      return false
   end

   -- Filenames: contains / (path) or ends with .extension
   if str:match("/") then
      return false
   end
   if str:match("%.[a-zA-Z0-9]+$") and not str:match("%s") then
      return false
   end

   -- Not in allowlist - could be a password
   return true
end

-- Step 2: Check if string has password-like structure (returns true if could be password)
-- Requirements: length >= 8, no spaces, not mostly digits, not mostly hex, has 2+ char types
local function passHasStructure(str, minLength)
   if not str then return false end

   local len = #str

   -- Length check
   if len < minLength then
      return false
   end

   -- No spaces allowed
   if str:match("%s") then
      return false
   end

   -- Count character types
   local digitCount = 0
   local hexCount = 0
   local hasLower = false
   local hasUpper = false
   local hasDigit = false
   local hasSymbol = false

   for i = 1, len do
      local char = str:sub(i, i)
      if char:match("[0-9]") then
         digitCount = digitCount + 1
         hexCount = hexCount + 1
         hasDigit = true
      elseif char:match("[a-f]") then
         hexCount = hexCount + 1
         hasLower = true
      elseif char:match("[A-F]") then
         hexCount = hexCount + 1
         hasUpper = true
      elseif char:match("[a-z]") then
         hasLower = true
      elseif char:match("[A-Z]") then
         hasUpper = true
      elseif char:match(PASSWORD_SYMBOLS) then
         hasSymbol = true
      end
   end

   -- Not mostly digits
   if digitCount / len >= MOSTLY_THRESHOLD then
      return false
   end

   -- Not mostly hex
   if hexCount / len >= MOSTLY_THRESHOLD then
      return false
   end

   -- Must have at least 2 character types
   local charTypes = 0
   if hasLower then charTypes = charTypes + 1 end
   if hasUpper then charTypes = charTypes + 1 end
   if hasDigit then charTypes = charTypes + 1 end
   if hasSymbol then charTypes = charTypes + 1 end

   if charTypes < 2 then
      return false
   end

   -- Passes structural checks - could be a password
   return true
end

-- Step 3: Check if string has high entropy (returns true if could be password)
local function passHighEntropy(str, threshold)
   if not str then return false end
   local entropy = calculateEntropy(str)
   return entropy >= threshold
end

-- Main function: Check if a string looks like a password using 3-step detection
local function looksLikePassword(str, settings)
   if not str then return false end

   -- Step 1: Check allowlist (UUIDs, URLs, hashes, etc.)
   if not passNotInAllowlist(str, settings.max_newlines) then
      return false
   end

   -- Step 2: Check structural requirements
   if not passHasStructure(str, settings.min_length) then
      return false
   end

   -- Step 3: Check entropy threshold
   if not passHighEntropy(str, settings.entropy_threshold) then
      return false
   end

   -- Passes all checks - likely a password
   return true
end

-- Keep track of last change counter
local last_change = nil;
-- Array to store the clipboard history
local clipboard_history = nil

-- Internal function - persist the current history so it survives across restarts
function _persistHistory()
   setSetting("items",clipboard_history)
end

--- ClipboardTool:togglePasteOnSelect()
--- Method
--- Toggle the value of `ClipboardTool.paste_on_select`
---
--- Parameters:
---  * None
function obj:togglePasteOnSelect()
   self.paste_on_select = setSetting("paste_on_select", not self.paste_on_select)
   hs.notify.show("ClipboardTool", "Paste-on-select is now " .. (self.paste_on_select and "enabled" or "disabled"), "")
end

function obj:toggleMaxSize()
   self.max_size = setSetting("max_size", not self.max_size)
   hs.notify.show("ClipboardTool", "Max Size is now " .. (self.max_size and "enabled" or "disabled"), "")
end

--- ClipboardTool:revealCurrentPassword()
--- Method
--- Reveal only the currently selected password-like entry (bound to Cmd-R)
---
--- Parameters:
---  * None
function obj:revealCurrentPassword()
   if self.selectorobj then
      local currentRow = self.selectorobj:selectedRow()
      if currentRow and currentRow > 0 then
         -- Toggle: if already revealing this row, hide it; otherwise reveal it
         if self.revealedItemIndex == currentRow then
            self.revealedItemIndex = nil
         else
            self.revealedItemIndex = currentRow
         end
         self.selectorobj:refreshChoicesCallback()
         self.selectorobj:selectedRow(currentRow)
      end
   end
end

--- ClipboardTool:toggleRevealAllPasswords()
--- Method
--- Toggle revealing of ALL password-like entries in the chooser (bound to Shift-Cmd-R)
---
--- Parameters:
---  * None
function obj:toggleRevealAllPasswords()
   self.revealPasswords = not self.revealPasswords
   self.revealedItemIndex = nil  -- Clear single-item reveal when toggling all
   if self.selectorobj then
      local currentRow = self.selectorobj:selectedRow()
      self.selectorobj:refreshChoicesCallback()
      if currentRow and currentRow > 0 then
         self.selectorobj:selectedRow(currentRow)
      end
   end
end

-- Internal method - process the selected item from the chooser. An item may invoke special actions, defined in the `actions` variable.
function obj:_processSelectedItem(value)
   -- Disable reveal hotkeys and reset reveal state when chooser closes
   if self.revealCurrentHotkey then
      self.revealCurrentHotkey:disable()
   end
   if self.revealAllHotkey then
      self.revealAllHotkey:disable()
   end
   self.revealPasswords = false
   self.revealedItemIndex = nil

   local actions = {
      none = function() end,
      clear = hs.fnutils.partial(self.clearAll, self),
      toggle_paste_on_select = hs.fnutils.partial(self.togglePasteOnSelect, self),
      toggle_max_size = hs.fnutils.partial(self.toggleMaxSize, self),
   }
   if self.prevFocusedWindow ~= nil then
      self.prevFocusedWindow:focus()
   end
   if value and type(value) == "table" then
      if value.action and actions[value.action] then
         actions[value.action](value)
      elseif value.text then
         if value.type == "text" then
            pasteboard.setContents(value.data)
         elseif value.type == "image" then
            pasteboard.writeObjects(hs.image.imageFromURL(value.data))
         end
--         self:pasteboardToClipboard(value.text)
         if (self.paste_on_select) then
            hs.eventtap.keyStroke({"cmd"}, "v")
         end
      end
      last_change = pasteboard.changeCount()
   end
end

--- ClipboardTool:clearAll()
--- Method
--- Clears the clipboard and history
---
--- Parameters:
---  * None
function obj:clearAll()
   pasteboard.clearContents()
   clipboard_history = {}
   _persistHistory()
   last_change = pasteboard.changeCount()
end

--- ClipboardTool:clearLastItem()
--- Method
--- Clears the last added to the history
---
--- Parameters:
---  * None
function obj:clearLastItem()
   table.remove(clipboard_history, 1)
   _persistHistory()
   last_change = pasteboard.changeCount()
end

-- Internal method: deduplicate the given list, and restrict it to the history size limit
function obj:dedupe_and_resize(list)
   local res={}
   local hashes={}
   for i,v in ipairs(list) do
      if #res < self.hist_size then
         local hash=hashfn(v.content)
         if (not self.deduplicate) or (not hashes[hash]) then
            table.insert(res, v)
            hashes[hash]=true
         end
      end
   end
   return res
end

--- ClipboardTool:pasteboardToClipboard(item)
--- Method
--- Add the given string to the history
---
--- Parameters:
---  * item - string to add to the clipboard history
---
--- Returns:
---  * None
function obj:pasteboardToClipboard(item_type, item)
   table.insert(clipboard_history, 1, {type=item_type, content=item})
   clipboard_history = self:dedupe_and_resize(clipboard_history)
   _persistHistory() -- updates the saved history
end

-- Internal method: actions of the context menu, special paste
function obj:pasteAllWithDelimiter(row, delimiter)
  if self.prevFocusedWindow ~= nil then
      self.prevFocusedWindow:focus()
   end
   print("pasteAllWithTab row:" .. row)
   for ix = row, 1, -1 do
     local entry = clipboard_history[ix]
     print("pasteAllWithTab ix:" .. ix .. ":" .. entry)
--      pasteboard.setContents(entry)
--      os.execute("sleep 0.2")
--      hs.eventtap.keyStroke({"cmd"}, "v")
       hs.eventtap.keyStrokes(entry.content)
--      os.execute("sleep 0.2")
      hs.eventtap.keyStrokes(delimiter)
--      os.execute("sleep 0.2")
   end
end

-- Internal method: actions of the context menu, delete or rearrange of clips
function obj:manageClip(row, action)
    print("manageClip row:" .. row .. ",action:" .. action)
    if action == 0 then
      table.remove (clipboard_history, row)
    elseif action == 2 then
      	local i = 1
        local j = row
        while i < j do
          clipboard_history[i], clipboard_history[j] = clipboard_history[j], clipboard_history[i]
          i = i + 1
          j = j - 1
        end
    else
      local value = clipboard_history[row]
      local new = row + action
      if new < 1 then new = 1 end
      if new < row then
        table.move(clipboard_history, new, row - 1, new + 1)
      else
        table.move(clipboard_history, row + 1, new, row)
      end
      clipboard_history[new] = value
    end
    self.selectorobj:refreshChoicesCallback()
end

-- Internal method:
function obj:_showContextMenu(row)
  print("_showContextMenu row:" .. row)
  point = hs.mouse.getAbsolutePosition()
  local menu = hs.menubar.new(false)
  local menuTable = {
       { title = "Alle Schnipsel mit Tab einfügen", fn = hs.fnutils.partial(self.pasteAllWithDelimiter, self, row, "\t") },
       { title = "Alle Schnipsel mit Zeilenvorschub einfügen", fn = hs.fnutils.partial(self.pasteAllWithDelimiter, self, row, "\n") },
       { title = "-" },
       { title = "Eintrag entfernen",   fn = hs.fnutils.partial(self.manageClip, self, row, 0) },
       { title = "Eintrag an erste Stelle",   fn = hs.fnutils.partial(self.manageClip, self, row, -100)  },
       { title = "Eintrag nach oben",   fn = hs.fnutils.partial(self.manageClip, self, row, -1)  },
       { title = "Eintrag nach unten",   fn = hs.fnutils.partial(self.manageClip, self, row, 1) },
       { title = "Tabelle invertieren",   fn = hs.fnutils.partial(self.manageClip, self, row, 2) },
       { title = "-" },
       { title = "disabled item", disabled = true },
       { title = "checked item", checked = true },
   }
  menu:setMenu(menuTable)
  menu:popupMenu(point)
  print(hs.inspect(point))
end

-- Internal function - fill in the chooser options, including the control options
function obj:_populateChooser(query)
   query = query:lower()
   menuData = {}
   local passwordSettings = {
      entropy_threshold = self.password_entropy_threshold,
      min_length = self.password_min_length,
      max_newlines = self.password_max_newlines,
   }
   for k,v in pairs(clipboard_history) do
      if (v.type == "text" and (query == "" or v.content:lower():find(query))) then
         local displayText = string.sub(v.content, 0, obj.display_max_length)
         local isPasswordLike = self.hide_passwords and looksLikePassword(v.content, passwordSettings)
         local rowIndex = #menuData + 1  -- This item's position in the chooser

         -- Hide if password-like, unless revealing all OR revealing this specific item
         local shouldReveal = self.revealPasswords or (self.revealedItemIndex == rowIndex)
         if isPasswordLike and not shouldReveal then
            displayText = "[hidden - " .. #v.content .. " chars]"
         end

         table.insert(menuData, { text = displayText,
                                  data = v.content,
                                  type = v.type,
                                  isPasswordLike = isPasswordLike})
      elseif (v.type == "image") then
         table.insert(menuData, { text = "《Image data》",
                                  type = v.type,
                                  data = v.content,
                                  image = hs.image.imageFromURL(v.content)})
      end
   end
   if #menuData == 0 then
      table.insert(menuData, { text="",
                               subText="《Clipboard is empty》",
                               action = 'none',
                               image = hs.image.imageFromName('NSCaution')})
   else
      table.insert(menuData, { text="《Clear Clipboard History》",
                               action = 'clear',
                               image = hs.image.imageFromName('NSTrashFull') })
   end
   table.insert(menuData, {
                   text="《" .. (self.paste_on_select and "Disable" or "Enable") .. " Paste-on-select》",
                   action = 'toggle_paste_on_select',
                   image = (self.paste_on_select and hs.image.imageFromName('NSSwitchEnabledOn') or hs.image.imageFromName('NSSwitchEnabledOff'))
   })
   table.insert(menuData, {
                   text="《" .. (self.max_size and "Disable" or "Enable") .. " max size " .. self.max_entry_size .. "》",
                   action = 'toggle_max_size',
                   image = (self.max_size and hs.image.imageFromName('NSSwitchEnabledOn') or hs.image.imageFromName('NSSwitchEnabledOff'))
   })
   self.logger.df("Returning menuData = %s", hs.inspect(menuData))
   return menuData
end

--- ClipboardTool:shouldBeStored()
--- Method
--- Verify whether the pasteboard contents matches one of the values in `ClipboardTool.ignoredIdentifiers`
---
--- Parameters:
---  * None
function obj:shouldBeStored()
   -- Code from https://github.com/asmagill/hammerspoon-config/blob/master/utils/_menus/newClipper.lua
   local goAhead = true
   for i,v in ipairs(hs.pasteboard.pasteboardTypes()) do
      if self.ignoredIdentifiers[v] then
         goAhead = false
         break
      end
   end
   if goAhead then
      for i,v in ipairs(hs.pasteboard.contentTypes()) do
         if self.ignoredIdentifiers[v] then
            goAhead = false
            break
         end
      end
   end
   return goAhead
end

-- Internal method:
function obj:reduceSize(text)
  print(#text .. " ? " .. tostring(max_entry_size))
  local endingpos = 3000
  local lastLowerPos = 3000
  repeat
    lastLowerPos = endingpos
    _, endingpos = string.find(text, "\n\n", endingpos+1)
    print("endingpos:" .. endingpos)
  until endingpos > obj.max_entry_size
  return string.sub(text, 1, lastLowerPos)
end


--- ClipboardTool:checkAndStorePasteboard()
--- Method
--- If the pasteboard has changed, we add the current item to our history and update the counter
---
--- Parameters:
---  * None
function obj:checkAndStorePasteboard()
   now = pasteboard.changeCount()
   if (now > last_change) then
      if (not self.honor_ignoredidentifiers) or self:shouldBeStored() then
         current_clipboard = pasteboard.getContents()
         self.logger.df("current_clipboard = %s", tostring(current_clipboard))
         if (current_clipboard == nil) and (pasteboard.readImage() ~= nil) then
            current_clipboard = pasteboard.readImage()
            self:pasteboardToClipboard("image", current_clipboard:encodeAsURLString())
            if self.show_copied_alert then
                hs.alert.show("Copied image")
            end
            self.logger.df("Adding image (hashed) %s to clipboard history clipboard", hashfn(current_clipboard:encodeAsURLString()))
         elseif current_clipboard ~= nil then
           local size = #current_clipboard
           if obj.max_size and size > obj.max_entry_size then
             local answer = hs.dialog.blockAlert("Clipboard", "The maximum size of " .. obj.max_entry_size .. " was exceeded.", "Copy partially", "Copy all", "NSCriticalAlertStyle")
              print("answer: " .. answer)
              if answer == "Copy partially" then
                current_clipboard = self:reduceSize(current_clipboard)
                size = #current_clipboard
                end
            end
            if self.show_copied_alert then
                hs.alert.show("Copied " .. size .. " chars")
            end
            self.logger.df("Adding %s to clipboard history", current_clipboard)
            self:pasteboardToClipboard("text", current_clipboard)
         else
            self.logger.df("Ignoring nil clipboard content")
         end
      else
         self.logger.df("Ignoring pasteboard entry because it matches ignoredIdentifiers")
      end
      last_change = now
   end
end

--- ClipboardTool:start()
--- Method
--- Start the clipboard history collector
---
--- Parameters:
---  * None
function obj:start()
   obj.logger.level = 0
   clipboard_history = self:dedupe_and_resize(getSetting("items", {})) -- If no history is saved on the system, create an empty history
   last_change = pasteboard.changeCount() -- keeps track of how many times the pasteboard owner has changed // Indicates a new copy has been made
   self.selectorobj = hs.chooser.new(hs.fnutils.partial(self._processSelectedItem, self))
   self.selectorobj:choices(hs.fnutils.partial(self._populateChooser, self, ""))
   self.selectorobj:queryChangedCallback(function(query)
      self.selectorobj:choices(hs.fnutils.partial(self._populateChooser, self, query))
   end)
   self.selectorobj:rightClickCallback(hs.fnutils.partial(self._showContextMenu, self))
   -- Create hotkeys for password reveal (disabled by default, enabled when chooser is shown)
   -- Cmd-R: reveal only the currently selected item
   self.revealCurrentHotkey = hs.hotkey.new({"cmd"}, "r", function()
      self:revealCurrentPassword()
   end)
   -- Shift-Cmd-R: toggle reveal ALL password-like items
   self.revealAllHotkey = hs.hotkey.new({"cmd", "shift"}, "r", function()
      self:toggleRevealAllPasswords()
   end)
   --Checks for changes on the pasteboard. Is it possible to replace with eventtap?
   self.timer = hs.timer.new(self.frequency, hs.fnutils.partial(self.checkAndStorePasteboard, self))
   self.timer:start()
   if self.show_in_menubar then
      self.menubaritem = hs.menubar.new()
         :setTitle(obj.menubar_title)
         :setClickCallback(hs.fnutils.partial(self.toggleClipboard, self))
   end
end

--- ClipboardTool:showClipboard()
--- Method
--- Display the current clipboard list in a chooser
---
--- Parameters:
---  * None
function obj:showClipboard()
   if self.selectorobj ~= nil then
      self.selectorobj:refreshChoicesCallback()
      self.prevFocusedWindow = hs.window.focusedWindow()
      -- Enable reveal hotkeys while chooser is visible
      if self.revealCurrentHotkey then
         self.revealCurrentHotkey:enable()
      end
      if self.revealAllHotkey then
         self.revealAllHotkey:enable()
      end
      self.selectorobj:show()
   else
      hs.notify.show("ClipboardTool not properly initialized", "Did you call ClipboardTool:start()?", "")
   end
end

--- ClipboardTool:toggleClipboard()
--- Method
--- Show/hide the clipboard list, depending on its current state
---
--- Parameters:
---  * None
function obj:toggleClipboard()
   if self.selectorobj:isVisible() then
      self.selectorobj:hide()
      -- Disable reveal hotkeys and reset reveal state when hiding
      if self.revealCurrentHotkey then
         self.revealCurrentHotkey:disable()
      end
      if self.revealAllHotkey then
         self.revealAllHotkey:disable()
      end
      self.revealPasswords = false
      self.revealedItemIndex = nil
   else
      self:showClipboard()
   end
end

--- ClipboardTool:bindHotkeys(mapping)
--- Method
--- Binds hotkeys for ClipboardTool
---
--- Parameters:
---  * mapping - A table containing hotkey objifier/key details for the following items:
---   * show_clipboard - Display the clipboard history chooser
---   * toggle_clipboard - Show/hide the clipboard history chooser
function obj:bindHotkeys(mapping)
   local def = {
      show_clipboard = hs.fnutils.partial(self.showClipboard, self),
      toggle_clipboard = hs.fnutils.partial(self.toggleClipboard, self),
   }
   hs.spoons.bindHotkeysToSpec(def, mapping)
   obj.mapping = mapping
end

return obj

