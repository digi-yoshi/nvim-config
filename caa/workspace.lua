-- caa.nvim: CAAワークスペースの自動判定と Install_config の読み取り
--
-- WSルートの判定は Install_config_win_b64 (mkGetPreq が生成・永続化するファイル) を
-- マーカーに、現在バッファ → cwd の順で上方向探索する。build / run / clangd / terminal
-- すべてこのモジュール経由で対象WSを解決するため、複数WSをバッファ切り替えだけで扱える。

local M = {}

local uv = vim.uv or vim.loop
local api = vim.api

local MARKER = "Install_config_win_b64"

-- 直近に解決できたWSルート (WS外のバッファから叩かれたときのフォールバック)
M.last_root = nil

function M.norm(p)
  return (p:gsub("/", "\\"):gsub("\\+$", ""):lower())
end

-- 現在バッファ → cwd の順で Install_config_win_b64 を上方向探索してWSルートを返す
function M.find_root()
  local starts = {}
  local name = api.nvim_buf_get_name(0)
  if name ~= "" then
    table.insert(starts, vim.fs.dirname(name))
  end
  table.insert(starts, uv.cwd())
  for _, start in ipairs(starts) do
    local hit = vim.fs.find(MARKER, { upward = true, path = start })[1]
    if hit then
      local root = vim.fs.dirname(hit)
      M.last_root = root
      return root
    end
  end
end

-- find_root で見つからなければ直近のWSにフォールバック
function M.resolve()
  return M.find_root() or M.last_root
end

-- Install_config の2行目 = mkGetPreq -p が永続化した prereq 連結パス。
-- 未初期化WS (ファイル無し) では nil
function M.read_prereq(root)
  local f = io.open(root .. "\\" .. MARKER, "r")
  if not f then
    return nil
  end
  f:read("l") -- 1行目 ("<Install> compatible") は捨てる
  local line2 = f:read("l")
  f:close()
  if not line2 then
    return nil
  end
  line2 = vim.trim(line2)
  return line2 ~= "" and line2 or nil
end

return M
