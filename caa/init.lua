-- caa.nvim: CATIA CAA (RADE) のビルド/実行/clangd統合
--
-- 各機能はサブモジュールに分割している:
--   workspace.lua 現在バッファからのWS自動判定・Install_config 読み取り
--   env.lua       WSごとの RADE/プロファイル選択の永続化と環境注入batの自動生成
--   terminal.lua  常駐ターミナル管理 (WS × build/run ごとに1本)
--   build.lua     mkmk / mkrtv / mkGetPreq + quickfix回収
--   run.lua       CATIA (CNEXT) 起動
--   clangd.lua    .clangd 再生成 (Generate-Clangd.ps1 を実行)
-- このファイルは設定の保持・コマンド登録・キーマップ配線のみを担う。
--
-- 設定はマシン上のRADEインストール先の一覧だけ:
--
--   require("caa").setup({
--     rade = {
--       B424 = [[C:\3DEXPERIENCE\B424_DevelopmentToolset]],
--       B32  = [[C:\CATIA\B32_RADE]],
--     },
--   })
--
-- 対象WSは毎回、現在バッファ → cwd から Install_config_win_b64 を上方向探索して決まる。
-- WSごとの「どのRADE・どのTCKプロファイルを使うか」は初回のターミナル起動時に選択し、
-- stdpath("data")/caa/workspaces.json に保持される (WSには何も置かない)。
-- 確認は :CaaProfile、選び直しは :CaaProfile! (ターミナルも再起動される)。
-- prereq は Install_config_win_b64 の2行目から自動取得される。

local term = require("caa.terminal")
local build = require("caa.build")
local run = require("caa.run")
local clangd = require("caa.clangd")
local ws = require("caa.workspace")
local env = require("caa.env")

local M = {}

M.config = {
  rade = {}, -- 名前 -> RADEインストール先 (win_b64\code\command\tck_init.bat を持つ場所)
  jobs = nil, -- mkmk -jobs の並列数。nil なら論理コア数
  build_flags = { "-g" }, -- -g: デバッグ情報付き (公式仕様でリリースCRT使用のため製品DLLと混載可)
  height = 12, -- ターミナルウィンドウの高さ
  mappings = true, -- <leader>m 系のデフォルトキーマップを定義する
  timeout_ms = 20 * 60 * 1000, -- ビルド完了マーカー待ちの上限
}

local function notify(msg, level)
  vim.notify(msg, level or vim.log.levels.INFO, { title = "CAA" })
end

-- 公開API (コマンド/キーマップから呼ばれる)
function M.build(scope)
  build.build(scope, M.config)
end
function M.rtv()
  build.rtv(M.config)
end
function M.getpreq(path)
  build.getpreq(M.config, path)
end
function M.run()
  run.run(M.config)
end
function M.clangd_gen()
  clangd.generate()
end
function M.toggle(kind)
  local root = ws.resolve()
  if not root then
    notify("CAAワークスペースが見つからない", vim.log.levels.ERROR)
    return
  end
  term.toggle(kind, M.config, root)
end

-- 現在WSの RADE/プロファイル選択を表示する。reselect=true なら選び直して
-- そのWSのターミナルを再起動する
function M.profile(reselect)
  local root = ws.resolve()
  if not root then
    notify("CAAワークスペースが見つからない", vim.log.levels.ERROR)
    return
  end
  if not reselect then
    local saved = env.get(root)
    if saved then
      notify(
        ("WS: %s\nRADE: %s (%s)\nプロファイル: %s\n保存先: %s\n選び直すなら :CaaProfile!"):format(
          root,
          saved.rade,
          tostring((M.config.rade or {})[saved.rade]),
          saved.profile,
          env.store_path()
        )
      )
    else
      notify("このWSは未選択。初回のビルド/ターミナル起動時か :CaaProfile! で選択する")
    end
    return
  end
  env.select(M.config, root, function()
    term.close_for(root)
    term.with("build", true, false, M.config, root, function()
      notify("新しい環境でターミナルを起動し直した")
    end)
  end)
end

function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})

  vim.api.nvim_create_user_command("CaaBuild", function(a)
    M.build(a.args ~= "" and a.args or nil)
  end, { nargs = "?", desc = "CAA: mkmk (省略=カレントモジュール / all / FW/Mod)" })
  vim.api.nvim_create_user_command("CaaRtv", M.rtv, { desc = "CAA: mkrtv (ランタイム資源コピー)" })
  vim.api.nvim_create_user_command("CaaGetPreq", function(a)
    M.getpreq(a.args)
  end, { nargs = "?", desc = "CAA: mkGetPreq (省略=Install_configの現行値で再実行)" })
  vim.api.nvim_create_user_command("CaaRun", M.run, { desc = "CAA: CATIA (CNEXT) 起動" })
  vim.api.nvim_create_user_command("CaaClangd", M.clangd_gen, { desc = "CAA: .clangd 再生成 (Generate-Clangd.ps1)" })
  vim.api.nvim_create_user_command("CaaProfile", function(a)
    M.profile(a.bang)
  end, { bang = true, desc = "CAA: RADE/プロファイル選択の表示 (! で選び直し+ターミナル再起動)" })
  vim.api.nvim_create_user_command("CaaTerm", function(a)
    M.toggle(a.args)
  end, {
    nargs = "?",
    complete = function()
      return { "build", "run" }
    end,
    desc = "CAA: ターミナル表示切替",
  })

  if M.config.mappings then
    local function map(lhs, rhs, desc)
      vim.keymap.set("n", lhs, rhs, { desc = desc, silent = true })
    end
    map("<leader>mb", function()
      M.build()
    end, "CAA: build (現在のモジュール)")
    map("<leader>ma", function()
      M.build("all")
    end, "CAA: build all")
    map("<leader>mv", M.rtv, "CAA: mkrtv")
    map("<leader>mp", function()
      M.getpreq()
    end, "CAA: mkGetPreq")
    map("<leader>mr", M.run, "CAA: CATIA起動")
    map("<leader>mc", M.clangd_gen, "CAA: .clangd 再生成")
    map("<leader>mt", function()
      M.toggle("build")
    end, "CAA: buildターミナル")
    map("<leader>mT", function()
      M.toggle("run")
    end, "CAA: runターミナル")
  end
end

return M
