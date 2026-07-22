-- caa.nvim: .clangd 再生成
--
-- スクリプト本体はプラグイン同梱 (このファイルと同じディレクトリの Generate-Clangd.ps1)。
-- 対象WSは workspace.lua が現在バッファから自動判定する。env_script が要らないため
-- setup の workspaces に未登録のWSでも動く

local ws = require("caa.workspace")

local M = {}

local uv = vim.uv or vim.loop

local function notify(msg, level)
  vim.notify(msg, level or vim.log.levels.INFO, { title = "CAA" })
end

local function bundled_script()
  local src = debug.getinfo(1, "S").source:sub(2) -- この clangd.lua のパス
  return vim.fs.joinpath(vim.fs.dirname(src), "Generate-Clangd.ps1")
end

function M.generate()
  local root = ws.resolve()
  if not root then
    notify("CAAワークスペースが見つからない (Install_config_win_b64 をマーカーに探索した)", vim.log.levels.ERROR)
    return
  end
  local script = bundled_script()
  if not uv.fs_stat(script) then
    notify("同梱スクリプトが無い: " .. script, vim.log.levels.ERROR)
    return
  end
  -- powershell(5.1) は UTF-8(BOMなし) の日本語コメントを誤読するので pwsh 固定
  vim.system(
    { "pwsh", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", script, "-Workspace", root },
    { text = true, cwd = root },
    vim.schedule_wrap(function(res)
      if res.code ~= 0 then
        notify(("再生成失敗 (exit %d)\n%s"):format(res.code, res.stderr or ""), vim.log.levels.ERROR)
        return
      end
      local out = vim.trim(res.stdout or "")
      if #vim.lsp.get_clients({ name = "clangd" }) > 0 then
        -- 新しい .clangd を確実に読ませる
        pcall(function()
          vim.cmd("LspRestart clangd")
        end)
        out = out .. "\nclangd を再起動した"
      end
      notify(out)
    end)
  )
end

return M
