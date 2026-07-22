-- caa.nvim: WSごとの RADE/TCKプロファイル選択の永続化と、環境注入batの自動生成
--
-- 仕組み:
--   - setup({ rade = { B424 = [[C:\...]], ... } }) にマシン上のRADE一覧を登録しておく
--   - WSごとの「どのRADE・どのプロファイルを使うか」は、初回のターミナル起動時に
--     vim.ui.select で選ばせ、stdpath("data")/caa/workspaces.json に保持する
--   - 選択が決まると、tck_init + tck_profile を呼ぶ環境注入batを同じディレクトリに
--     自動生成する (手書きの env_script は不要)。batは resolve のたびに再生成される
--     ため、setup の rade パスを変えても追従する
--   - 選び直しは :CaaProfile! (init.lua が M.select を呼び直す)

local ws = require("caa.workspace")

local M = {}

local uv = vim.uv or vim.loop

local function notify(msg, level)
  vim.notify(msg, level or vim.log.levels.INFO, { title = "CAA" })
end

local function data_dir()
  return vim.fs.joinpath(vim.fn.stdpath("data"), "caa")
end

function M.store_path()
  return vim.fs.joinpath(data_dir(), "workspaces.json")
end

local function load_store()
  local f = io.open(M.store_path(), "r")
  if not f then
    return {}
  end
  local text = f:read("*a")
  f:close()
  local ok, data = pcall(vim.json.decode, text)
  return (ok and type(data) == "table") and data or {}
end

local function save_store(store)
  vim.fn.mkdir(data_dir(), "p")
  local f = io.open(M.store_path(), "w")
  if not f then
    notify("保存に失敗: " .. M.store_path(), vim.log.levels.ERROR)
    return
  end
  f:write(vim.json.encode(store))
  f:close()
end

-- そのWSの保存済み選択 ({ root, rade, profile }) を返す。無ければ nil
function M.get(root)
  return load_store()[ws.norm(root)]
end

function M.set(root, rade_key, profile)
  local store = load_store()
  store[ws.norm(root)] = { root = root, rade = rade_key, profile = profile }
  save_store(store)
end

function M.clear(root)
  local store = load_store()
  store[ws.norm(root)] = nil
  save_store(store)
end

-- WSごとの環境注入batのパス (nvim-data 配下。WSには何も置かない)
function M.bat_path(root)
  return vim.fs.joinpath(data_dir(), "env_" .. ws.norm(root):gsub("[^%w]", "_") .. ".bat")
end

local function tck_init_bat(rade_path)
  return rade_path .. "\\win_b64\\code\\command\\tck_init.bat"
end

-- 環境注入batを(再)生成してパスを返す
local function write_env_bat(root, rade_path, profile)
  vim.fn.mkdir(data_dir(), "p")
  local lines = {
    "@echo off",
    "rem caa.nvim generated - do not edit (:CaaProfile! で再生成される)",
    "rem mojibake mitigation for cl.exe messages",
    "chcp 65001 >nul",
    "set VSLANG=1033",
    ('call "%s"'):format(tck_init_bat(rade_path)),
    ('call "%s\\win_b64\\TCK\\command\\tck_profile.bat" %s'):format(rade_path, profile),
    ("echo [CAA] env ready: %s"):format(profile),
    "@echo on",
  }
  local p = M.bat_path(root)
  local f = io.open(p, "w")
  if not f then
    notify("batの生成に失敗: " .. p, vim.log.levels.ERROR)
    return nil
  end
  f:write(table.concat(lines, "\r\n") .. "\r\n")
  f:close()
  return p
end

-- tck_list で登録済みプロファイル名を列挙して cb(names) を呼ぶ。
-- tck_init を先に通す必要があるため、一時batにまとめて cmd /c で実行する
-- (引数内の && と引用符のネストを cmd に安全に渡すため文字列連結はしない)
local function list_profiles(rade_path, cb)
  vim.fn.mkdir(data_dir(), "p")
  local tmp = vim.fs.joinpath(data_dir(), "tck_list_tmp.bat")
  local f = io.open(tmp, "w")
  if not f then
    cb({})
    return
  end
  f:write(table.concat({
    "@echo off",
    ('call "%s" >nul 2>&1'):format(tck_init_bat(rade_path)),
    ('call "%s\\win_b64\\TCK\\command\\tck_list.bat"'):format(rade_path),
  }, "\r\n") .. "\r\n")
  f:close()
  vim.system({ "cmd", "/c", tmp }, { text = true }, vim.schedule_wrap(function(res)
    os.remove(tmp)
    -- 出力は「<プロファイル名> <付随トークン...>」の行が並ぶ。先頭トークンを候補にする
    local names = {}
    for line in (res.stdout or ""):gmatch("[^\r\n]+") do
      local first = line:match("^%s*(%S+)")
      if first then
        table.insert(names, first)
      end
    end
    cb(names)
  end))
end

-- 対話選択フロー: RADE選択 → tck_list → プロファイル選択 → 保存 → bat生成 → cb(bat)
function M.select(config, root, cb)
  local keys = vim.tbl_keys(config.rade or {})
  table.sort(keys)
  if #keys == 0 then
    notify("setup({ rade = { ... } }) にRADEインストール先を登録して", vim.log.levels.ERROR)
    return
  end
  vim.ui.select(keys, {
    prompt = "RADE を選択: " .. vim.fn.fnamemodify(root, ":t"),
    format_item = function(k)
      return k .. "  (" .. config.rade[k] .. ")"
    end,
  }, function(key)
    if not key then
      return -- キャンセル
    end
    local rade_path = config.rade[key]
    if not uv.fs_stat(tck_init_bat(rade_path)) then
      notify("tck_init.bat が見つからない: " .. tck_init_bat(rade_path), vim.log.levels.ERROR)
      return
    end
    notify("tck_list でプロファイル一覧を取得中…")
    list_profiles(rade_path, function(profiles)
      local function finish(profile)
        if not profile or profile == "" then
          return -- キャンセル
        end
        M.set(root, key, profile)
        local bat = write_env_bat(root, rade_path, profile)
        if bat then
          notify(("選択を保存した: %s / %s"):format(key, profile))
          cb(bat)
        end
      end
      if #profiles > 0 then
        vim.ui.select(profiles, { prompt = "TCKプロファイルを選択" }, finish)
      else
        vim.ui.input({ prompt = "tck_list に失敗。プロファイル名を手入力: " }, finish)
      end
    end)
  end)
end

-- 環境注入batを解決して cb(bat_path) を呼ぶ。保存済みなら bat を再生成して即継続、
-- 未選択なら初回の対話選択フローに入る
function M.resolve(config, root, cb)
  local saved = M.get(root)
  if not saved then
    M.select(config, root, cb)
    return
  end
  local rade_path = (config.rade or {})[saved.rade]
  if not rade_path then
    notify(
      ("保存済みのRADEキー '%s' が setup の rade に無い。:CaaProfile! で選び直して"):format(saved.rade),
      vim.log.levels.ERROR
    )
    return
  end
  local bat = write_env_bat(root, rade_path, saved.profile)
  if bat then
    cb(bat)
  end
end

return M
