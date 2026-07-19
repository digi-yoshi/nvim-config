return {
  {
    "lewis6991/gitsigns.nvim",
    opts = function(_, opts)
      local on_attach = opts.on_attach

      opts.diff_opts = {
        internal = true,
        ignore_whitespace_change_at_eol = true,
      }

      -- 追加
      opts.signs = {
        add = { text = "+" },
        change = { text = "~" },
        delete = { text = "_" },
        topdelete = { text = "‾" },
        changedelete = { text = "~" },
        untracked = { text = "┆" },
      }

      opts.on_attach = function(bufnr)
        -- デフォルトを維持
        if on_attach then
          on_attach(bufnr)
        end

        -- 追加分だけ定義
        local gs = package.loaded.gitsigns

        local function map(mode, lhs, rhs, desc)
          vim.keymap.set(mode, lhs, rhs, {
            buffer = bufnr,
            desc = desc,
          })
        end

        map("n", "<leader>j", gs.next_hunk, "Next Hunk")
        map("n", "<leader>k", gs.prev_hunk, "Prev Hunk")
        map("n", "<leader>hp", gs.preview_hunk, "Preview Hunk")
      end
    end,
  },
}
