-- ReaScript Name: Import Zoom Folders (Tr1-6)
-- Description: Scans ZOOMxxxx folders, places Tr1-6 WAVs on tracks in order.
-- Author: Copilot (GPT-5.1-Codex-Max)
-- Version: 1.1
-- Usage: Run script, choose the root folder that contains the ZOOMxxxx subfolders (e.g. .../SONIDO/MULTI/FOLDER01).
-- Notes: Items for each ZOOM folder are placed at the same start time; folders are laid out sequentially.

local EXT_SECTION = "ZOOM_IMPORT"
local EXT_KEY = "ROOT"

local TRACKS = {
  { name = "Tr1", variants = { "tr1" } },
  { name = "Tr2", variants = { "tr2" } },
  { name = "Tr3", variants = { "tr3", "trlr" } },
  { name = "Tr4", variants = { "tr4" } },
  { name = "Tr5", variants = { "tr5" } },
  { name = "Tr6", variants = { "tr6" } },
}

local function msg(text)
  reaper.ShowConsoleMsg(tostring(text) .. "\n")
end

local function ensure_track(name, index)
  local track = reaper.GetTrack(0, index)
  if not track then
    reaper.InsertTrackAtIndex(index, true)
    track = reaper.GetTrack(0, index)
  end
  reaper.GetSetMediaTrackInfo_String(track, "P_NAME", name, true)
  return track
end

local function list_zoom_folders(root)
  local folders = {}
  local i = 0
  while true do
    local dir = reaper.EnumerateSubdirectories(root, i)
    if not dir then break end
    if dir:match("^ZOOM%d+$") then
      folders[#folders + 1] = dir
    end
    i = i + 1
  end
  table.sort(folders)
  return folders
end

local function find_file(base_dir, folder, variants)
  local path = base_dir .. "/" .. folder
  local found = {}
  local j = 0
  while true do
    local f = reaper.EnumerateFiles(path, j)
    if not f then break end
    local lower = f:lower()
    for _, v in ipairs(variants) do
      if lower:match("_" .. v .. "%.[wav]+$") then
        found[#found + 1] = f
        break
      end
    end
    j = j + 1
  end
  table.sort(found)
  if #found == 0 then return nil end
  return path .. "/" .. found[1]
end

local function insert_item(track, filepath, pos)
  local src = reaper.PCM_Source_CreateFromFileEx(filepath, false)
  if not src then
    msg("Could not load / Didn't find: " .. filepath)
    return 0
  end
  local src_len = reaper.GetMediaSourceLength(src)
  local item = reaper.AddMediaItemToTrack(track)
  reaper.SetMediaItemInfo_Value(item, "D_POSITION", pos)
  reaper.SetMediaItemInfo_Value(item, "D_LENGTH", src_len)
  local take = reaper.AddTakeToMediaItem(item)
  reaper.SetMediaItemTake_Source(take, src)
  local name = filepath:match("([^/\\]+)$")
  if name then name = name:gsub("%.[^%.]+$", "") end
  if name and name ~= "" then
    reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", name, true)
  end
  reaper.UpdateItemInProject(item)
  return src_len
end

local function browse_for_folder(default)
  if not default then default = "" end
  if reaper.JS_Dialog_BrowseForFolder then
    local ok, path = reaper.JS_Dialog_BrowseForFolder("Select Zoom root folder", default, "")
    if ok == 0 then return nil end
    return path
  elseif reaper.BR_Win32_SelectFolder then
    return reaper.BR_Win32_SelectFolder("Select Zoom root folder", default)
  end
  return nil
end

local function prompt_root()
  local default = reaper.GetExtState(EXT_SECTION, EXT_KEY)
  if default == "" then
    default = reaper.GetProjectPath(0)
  end
  local picked = browse_for_folder(default)
  if picked and picked ~= "" then
    picked = picked:gsub("\\", "/")
    reaper.SetExtState(EXT_SECTION, EXT_KEY, picked, true)
    return picked
  end

  local ok, ret = reaper.GetUserInputs("Import Zoom folders", 1, "Root folder (contains ZOOMxxxx)", default)
  if not ok or ret == "" then return nil end
  ret = ret:gsub("\\", "/")
  reaper.SetExtState(EXT_SECTION, EXT_KEY, ret, true)
  return ret
end

local function main()
  reaper.Undo_BeginBlock()
  reaper.ClearConsole()

  local root = prompt_root()
  if not root then return end

  local folders = list_zoom_folders(root)
  if #folders == 0 then
    msg("No ZOOMxxxx folders found in " .. root)
    return
  end

  -- Pre-scan to determine which tracks actually have files and cache paths per folder.
  local track_active = {}
  local folder_data = {}
  for _, folder in ipairs(folders) do
    local entry = { name = folder, files = {} }
    for i, def in ipairs(TRACKS) do
      local f = find_file(root, folder, def.variants)
      if f then
        entry.files[i] = f
        track_active[i] = true
      end
    end
    folder_data[#folder_data + 1] = entry
  end

  local tracks = {}
  local track_pos = 0
  for i, def in ipairs(TRACKS) do
    if track_active[i] then
      tracks[i] = ensure_track(def.name, track_pos)
      track_pos = track_pos + 1
    end
  end

  if track_pos == 0 then
    msg("No matching Tr1-6 files found in any ZOOM folder.")
    return
  end

  local pos = 0.0
  for _, entry in ipairs(folder_data) do
    local max_len = 0.0
    for i, _ in ipairs(TRACKS) do
      local tr = tracks[i]
      local f = entry.files[i]
      if tr and f then
        max_len = math.max(max_len, insert_item(tr, f, pos))
      end
    end

    pos = pos + max_len
  end

  reaper.UpdateArrange()
  reaper.Undo_EndBlock("Import Zoom folders", -1)
  msg("Done. Imported " .. tostring(#folders) .. " folders.")
end

main()
