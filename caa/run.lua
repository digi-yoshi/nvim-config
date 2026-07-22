-- caa.nvim: CATIA (CNEXT) 起動。対象WSは workspace.lua が現在バッファから自動判定する

local term = require("caa.terminal")
local ws = require("caa.workspace")

local M = {}

local function notify(msg, level)
  vim.notify(msg, level or vim.log.levels.INFO, { title = "CAA" })
end

function M.run(config)
  local root = ws.resolve()
  if not root then
    notify("CAAワークスペースが見つからない (Install_config_win_b64 をマーカーに探索した)", vim.log.levels.ERROR)
    return
  end
  vim.fn.mkdir("C:\\temp", "p") -- 公式仕様: Windows の mkrun は C:\temp 必須
  if term.cnext_running() then
    term.with("run", true, false, config, root, function() end)
    notify("CNEXT は既に起動してる", vim.log.levels.WARN)
    return
  end
  term.with("run", true, false, config, root, function(t)
    term.send(t, "set CNEXTOUTPUT=CONSOLE")
    term.send(t, 'mkrun -c "CNEXT"')
    notify("CATIA (CNEXT) 起動。トレースは run ターミナルに流れる")
  end)
end

return M
