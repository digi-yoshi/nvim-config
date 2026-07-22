-- caa.nvim: 常駐ターミナル管理 (ワークスペース × 種別ごとに1本)
--
-- 環境注入 (tck_init → tck_profile) はターミナル生成時に1回だけ。注入batは env.lua が
-- WSごとの保存済み選択から自動生成する (初回はここから対話選択フローに入る)。
-- 以後は生きている cmd セッションへコマンド文字列を送るだけなので、
-- 2回目以降のビルドに環境セットアップのコストはかからない。

local ws = require("caa.workspace")
local env = require("caa.env")

local M = {}

local api = vim.api

local terminals = {} -- key: kind .. "|" .. norm(root) -> { buf, job }

local function notify(msg, level)
  vim.notify(msg, level or vim.log.levels.INFO, { title = "CAA" })
end

local function key_of(kind, root)
  return kind .. "|" .. ws.norm(root)
end

local function term_alive(t)
  return t ~= nil and api.nvim_buf_is_valid(t.buf) and vim.fn.jobwait({ t.job }, 0)[1] == -1
end

local function open_window(buf, focus, height)
  local prev = api.nvim_get_current_win()
  vim.cmd("botright " .. height .. "split")
  api.nvim_win_set_buf(0, buf)
  if not focus then
    api.nvim_set_current_win(prev)
  end
end

local function create_term(kind, focus, config, root, env_bat)
  local prev = api.nvim_get_current_win()
  vim.cmd("botright " .. config.height .. "new")
  local buf = api.nvim_get_current_buf()
  local cmd = { "cmd", "/k", env_bat }
  local job
  if vim.fn.has("nvim-0.11") == 1 then
    job = vim.fn.jobstart(cmd, { term = true, cwd = root })
  else
    job = vim.fn.termopen(cmd, { cwd = root })
  end
  if job <= 0 then
    notify("ターミナル起動に失敗: " .. env_bat, vim.log.levels.ERROR)
    vim.cmd("close")
    return nil
  end
  vim.bo[buf].bufhidden = "hide"
  pcall(api.nvim_buf_set_name, buf, "caa://" .. kind .. "/" .. vim.fn.fnamemodify(root, ":t"))
  if not focus then
    api.nvim_set_current_win(prev)
  end
  terminals[key_of(kind, root)] = { buf = buf, job = job }
  return terminals[key_of(kind, root)]
end

-- 生きている端末を用意して cb(t) を呼ぶ。
-- 既存があれば同期で即継続。無ければ env 解決 (初回はRADE/プロファイル対話選択) を
-- 経て生成するため、cb は非同期に呼ばれることがある。
function M.with(kind, show, focus, config, root, cb)
  local t = terminals[key_of(kind, root)]
  if term_alive(t) then
    if show and vim.fn.bufwinid(t.buf) == -1 then
      open_window(t.buf, focus, config.height)
    end
    cb(t)
    return
  end
  env.resolve(config, root, function(env_bat)
    local created = create_term(kind, focus, config, root, env_bat)
    if created then
      cb(created)
    end
  end)
end

function M.send(t, line)
  vim.fn.chansend(t.job, line .. "\r")
end

function M.toggle(kind, config, root)
  kind = (kind == nil or kind == "") and "build" or kind
  local t = terminals[key_of(kind, root)]
  if term_alive(t) then
    local win = vim.fn.bufwinid(t.buf)
    if win ~= -1 then
      api.nvim_win_close(win, false)
    else
      open_window(t.buf, true, config.height)
    end
  else
    M.with(kind, true, true, config, root, function() end)
  end
end

-- 指定WSのターミナルを全部落とす (:CaaProfile! の選び直し時に使う)
function M.close_for(root)
  local suffix = "|" .. ws.norm(root)
  for key, t in pairs(terminals) do
    if key:sub(-#suffix) == suffix then
      pcall(vim.fn.jobstop, t.job)
      if api.nvim_buf_is_valid(t.buf) then
        pcall(api.nvim_buf_delete, t.buf, { force = true })
      end
      terminals[key] = nil
    end
  end
end

function M.cnext_running()
  local out = vim.fn.system('tasklist /FI "IMAGENAME eq CNEXT.exe" /NH')
  return out:find("CNEXT.exe", 1, true) ~= nil
end

return M
