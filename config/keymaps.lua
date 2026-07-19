-- jjでノーマルモードへ
vim.keymap.set("i", "jj", "<Esc>", { desc = "Exit insert mode" })

-- Yで行末までヤンク
vim.keymap.set("n", "Y", "y$", { desc = "Yank to end of line" })

-- UでRedo
vim.keymap.set("n", "U", "<C-r>", { desc = "Redo" })

-- Mで括弧ジャンプ
vim.keymap.set("n", "M", "%", { desc = "M kakko" })

-- xをブラックホールレジスタへ
vim.keymap.set("n", "x", '"_d', { desc = "Delete without yank" })
vim.keymap.set("n", "X", '"_D', { desc = "Delete line tail without yank" })
vim.keymap.set("x", "x", '"_x', { desc = "Delete selection without yank" })
vim.keymap.set("o", "x", "d")

-- <leader>b~ で現在のバッファのパスをコピー
-- y:ファイル名/Y:フルパス/r:相対パス/l:ライン
local function copy_buffer(expr, message)
  local value = vim.fn.expand(expr)
  if value == "" then
    vim.notify("Current buffer has no file", vim.log.levels.WARN)
    return
  end
  vim.fn.setreg("+", value)
  vim.notify(message)
end

vim.keymap.set("n", "<leader>by", function()
  copy_buffer(vim.fn.expand("%:t"), "Copied file name")
end, { desc = "Copy file name" })

vim.keymap.set("n", "<leader>bY", function()
  copy_buffer(vim.fn.expand("%:p"), "Copied full path")
end, { desc = "Copy full path" })

vim.keymap.set("n", "<leader>br", function()
  copy_buffer(vim.fn.expand("%"), "Copied relative path")
end, { desc = "Copy relative path" })

vim.keymap.set("n", "<leader>bl", function()
  copy_buffer(string.format("%s:%d", vim.fn.expand("%"), vim.fn.line(".")), "Copied path:line")
end, { desc = "Copy path:line" })
