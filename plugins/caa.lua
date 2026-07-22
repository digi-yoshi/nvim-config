-- CAA (CATIA RADE) 統合の配線。実体は lua/caa/ 配下
--
-- ここに書くのはマシン上のRADEインストール先の一覧だけ (マシン設定)。
-- WSごとの「どのRADE・どのTCKプロファイルを使うか」は初回のターミナル起動時に
-- 選択して nvim-data 側 (stdpath("data")/caa/workspaces.json) に保持される。
-- 確認: :CaaProfile / 選び直し: :CaaProfile!
-- prereq は各WSの Install_config_win_b64 から自動取得される。

require("caa").setup({
  rade = {
    B424 = [[C:\3DEXPERIENCE\B424_DevelopmentToolset]],
    B32 = [[C:\CATIA\B32_RADE]],
  },
})

return {
  { "folke/which-key.nvim", opts = { spec = { { "<leader>m", group = "CAA" } } } },
}
