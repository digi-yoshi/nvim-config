-- caa.nvim: mkmk / mkrtv / mkGetPreq とビルド結果の quickfix 回収
--
-- 対象WSは workspace.lua が現在バッファから自動判定する。
-- mkmk は cwd (=ワークスペースルート) + ターゲット指定でスコープが決まる。
-- mkrtv / mkGetPreq は毎ビルド不要のため独立コマンドにしている。
--
-- quickfix 回収の仕組み:
--   常駐ターミナルには過去の出力が混在するため「このビルドの出力」を切り出す。
--   送信前にバッファ行数を記録し、mkmk の後に echo ===CAA_EXIT===%errorlevel% を
--   別行で送る (同一行に & で繋ぐと %errorlevel% が実行前に展開される cmd の罠がある)。
--   マーカー検出後、記録位置以降の行だけを errorformat でパースする。

local term = require("caa.terminal")
local ws = require("caa.workspace")

local M = {}

local uv = vim.uv or vim.loop
local api = vim.api

local MARKER = "===CAA_EXIT==="

local build_state = {
  running = false,
  timer = nil,
  last_target = {}, -- norm(root) -> 直近ターゲット
}

-- cl.exe のコンパイルエラー / LNK リンクエラー / mkmk 自体のエラーを拾う
local EFM = table.concat({
  "%f(%l): fatal %trror C%n: %m",
  "%f(%l) : fatal %trror C%n: %m",
  "%f(%l): %trror C%n: %m",
  "%f(%l) : %trror C%n: %m",
  "%f(%l): %tarning C%n: %m",
  "%f(%l) : %tarning C%n: %m",
  "%.%#fatal %trror LNK%n: %m",
  "%.%#%trror LNK%n: %m",
  "mkmk-ERROR: %m",
  "#%.%#make-ERROR: %m",
}, ",")

local function notify(msg, level)
  vim.notify(msg, level or vim.log.levels.INFO, { title = "CAA" })
end

local function resolve_root()
  local root = ws.resolve()
  if not root then
    notify("CAAワークスペースが見つからない (Install_config_win_b64 をマーカーに探索した)", vim.log.levels.ERROR)
  end
  return root
end

---------------------------------------------------------------------------
-- ビルドスコープの導出
---------------------------------------------------------------------------

-- 現在バッファのパスから mkmk ターゲットを導出する。
-- WS/FW/Mod 配下 (Imakefile.mk あり) → "FW/Mod"、モジュール外だがFW配下 → "FW"、WS外 → nil
local function buffer_target(root)
  local file = api.nvim_buf_get_name(0)
  if file == "" then
    return nil
  end
  local nf, nws = ws.norm(file), ws.norm(root)
  if nf:sub(1, #nws + 1) ~= nws .. "\\" then
    return nil
  end
  local rel = file:sub(#nws + 2)
  local parts = vim.split(rel, "[\\/]", { trimempty = true })
  local fw, mod = parts[1], parts[2]
  if fw and mod and uv.fs_stat(table.concat({ root, fw, mod, "Imakefile.mk" }, "\\")) then
    return fw .. "/" .. mod
  end
  if fw and uv.fs_stat(table.concat({ root, fw, "IdentityCard" }, "\\")) then
    return fw
  end
  return nil
end

---------------------------------------------------------------------------
-- quickfix 回収
---------------------------------------------------------------------------

local function is_diag(line)
  return line:find(": error C", 1, true)
    or line:find(": warning C", 1, true)
    or line:find(": fatal error C", 1, true)
    or line:find("error LNK", 1, true)
    or line:find("mkmk-ERROR", 1, true)
    or line:find("make-ERROR", 1, true)
end

local function finish_build(t, start_line, marker_line, code, target)
  local lines = api.nvim_buf_get_lines(t.buf, start_line, marker_line, false)
  local diags = vim.tbl_filter(is_diag, lines)
  vim.fn.setqflist({}, " ", { title = "CAA build " .. target, lines = diags, efm = EFM })
  local err, warn = 0, 0
  for _, item in ipairs(vim.fn.getqflist()) do
    if item.valid == 1 then
      if item.type == "w" then
        warn = warn + 1
      else
        err = err + 1
      end
    end
  end
  if code == 0 and err == 0 then
    local w = warn > 0 and ("  (警告 " .. warn .. "件)") or ""
    notify("ビルド成功: " .. target .. w)
  elseif err > 0 then
    notify(("ビルド失敗: %s  エラー%d件 / 警告%d件 (exit %d)"):format(target, err, warn, code), vim.log.levels.ERROR)
    vim.cmd("copen")
  else
    -- exit≠0 だが解析可能な行なし (mkGetPreq未実行、環境不備など)
    notify(("ビルド失敗: %s (exit %d)。ターミナルの出力を確認して"):format(target, code), vim.log.levels.ERROR)
  end
end

local function stop_timer()
  if build_state.timer then
    build_state.timer:stop()
    build_state.timer:close()
    build_state.timer = nil
  end
end

local function poll_build(t, start_line, target, timeout_ms)
  local waited = 0
  build_state.timer = uv.new_timer()
  build_state.timer:start(
    500,
    500,
    vim.schedule_wrap(function()
      if not build_state.timer then
        return
      end
      if not api.nvim_buf_is_valid(t.buf) then
        stop_timer()
        build_state.running = false
        return
      end
      local lines = api.nvim_buf_get_lines(t.buf, start_line, -1, false)
      for i, line in ipairs(lines) do
        local code = line:match("^" .. MARKER .. "(%-?%d+)")
        if code then
          stop_timer()
          build_state.running = false
          finish_build(t, start_line, start_line + i - 1, tonumber(code), target)
          return
        end
      end
      waited = waited + 500
      if waited >= timeout_ms then
        stop_timer()
        build_state.running = false
        notify("ビルド完了マーカーを検出できず打ち切り。ターミナルを確認して", vim.log.levels.WARN)
      end
    end)
  )
end

---------------------------------------------------------------------------
-- 公開API
---------------------------------------------------------------------------

-- scope: nil=現在バッファのモジュール (判定不能なら前回ターゲット) / "all" / "FW" / "FW/Mod"
function M.build(scope, config)
  if build_state.running then
    notify("前のビルドがまだ走ってる", vim.log.levels.WARN)
    return
  end
  if term.cnext_running() then
    notify("CATIA (CNEXT) 起動中はビルドしない (DLLロックで失敗する)。閉じてからもう一回", vim.log.levels.WARN)
    return
  end
  local root = resolve_root()
  if not root then
    return
  end
  local target = scope
  if not target then
    target = buffer_target(root) or build_state.last_target[ws.norm(root)]
    if not target then
      notify("スコープを判定できない (WS外のバッファ)。:CaaBuild all か FW/Mod 指定で", vim.log.levels.WARN)
      return
    end
  end
  term.with("build", false, false, config, root, function(t)
    if build_state.running then
      notify("前のビルドがまだ走ってる", vim.log.levels.WARN)
      return
    end
    local jobs = config.jobs or (uv.available_parallelism and uv.available_parallelism()) or 4
    local flags = table.concat(config.build_flags, " ")
    local cmd
    if target == "all" then
      cmd = ("mkmk -a -jobs %d %s"):format(jobs, flags)
    else
      cmd = ("mkmk -jobs %d %s %s"):format(jobs, flags, target)
    end
    build_state.last_target[ws.norm(root)] = target
    build_state.running = true
    local start_line = api.nvim_buf_line_count(t.buf)
    term.send(t, cmd)
    term.send(t, "echo " .. MARKER .. "%errorlevel%")
    notify(("ビルド開始: %s (%s)"):format(target, vim.fn.fnamemodify(root, ":t")))
    poll_build(t, start_line, target, config.timeout_ms)
  end)
end

-- ランタイム資源 (アイコン / .dic / NLS 等) のコピー。リソースを触ったときだけ必要
function M.rtv(config)
  if build_state.running then
    notify("ビルド中は待って", vim.log.levels.WARN)
    return
  end
  if term.cnext_running() then
    notify("CATIA (CNEXT) 起動中はランタイムビューを更新しない。閉じてからもう一回", vim.log.levels.WARN)
    return
  end
  local root = resolve_root()
  if not root then
    return
  end
  term.with("build", true, false, config, root, function(t)
    term.send(t, "mkrtv")
  end)
end

-- prerequisites のサーチパス定義。mkGetPreq -p が Install_config_win_b64 に永続化する。
-- 値の優先順: 明示引数 (:CaaGetPreq <path>) > Install_config の2行目 (既存WSの再実行)。
-- どちらも無い未初期化WSでは引数なしの mkGetPreq を流す (結果はターミナルで確認)
function M.getpreq(config, path)
  if build_state.running then
    notify("ビルド中は待って", vim.log.levels.WARN)
    return
  end
  local root = resolve_root()
  if not root then
    return
  end
  local prereq = (path and path ~= "") and path or ws.read_prereq(root)
  term.with("build", true, false, config, root, function(t)
    if prereq then
      term.send(t, ('mkGetPreq -p "%s"'):format(prereq))
    else
      term.send(t, "mkGetPreq")
    end
  end)
end

return M
