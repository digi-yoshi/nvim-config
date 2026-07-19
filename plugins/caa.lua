-- CAA (CATIA RADE) 統合の配線。実体は lua/caa/init.lua
-- プロジェクト固有の値はここに集約する (マシン固有のツールチェーンは caa_env.bat 側)

require("caa").setup({
  env_script = [[D:\10_Develop\D_Digicore\CAA-SKILL\tools\nvim\caa_env.bat]],
  workspace = [[D:\10_Develop\D_Digicore\CAA-SKILL\sample\TestWS]],
  prereq = [[C:\CATIA\B32]],
})

return {
  { "folke/which-key.nvim", opts = { spec = { { "<leader>m", group = "CAA" } } } },
}
