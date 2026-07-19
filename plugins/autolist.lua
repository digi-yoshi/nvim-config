return {
  {
    "gaoDean/autolist.nvim",
    ft = { "markdown" },
    config = function()
      require("autolist").setup()

      vim.keymap.set("i", "<CR>", "<CR><Cmd>AutolistNewBullet<CR>", { noremap = true })

      vim.keymap.set("i", "<Tab>", "<Cmd>AutolistTab<CR>", { noremap = true })
      vim.keymap.set("i", "<S-Tab>", "<Cmd>AutolistShiftTab<CR>", { noremap = true })

      vim.keymap.set("n", "o", "o<Cmd>AutolistNewBullet<CR>", { noremap = true })
      vim.keymap.set("n", "O", "O<Cmd>AutolistNewBulletBefore<CR>", { noremap = true })
    end,
  },
}
