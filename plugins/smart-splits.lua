return {
  {
    "mrjones2014/smart-splits.nvim",
    opts = {
      resize_mode = {
        hooks = {
          on_enter = function()
            vim.notify("Resize mode")
          end,
          on_leave = function()
            vim.notify("Normal mode")
          end,
        },
        resize_step = 10,
      },
    },
    keys = {
      {
        "<leader>wH",
        function()
          require("smart-splits").resize_left()
        end,
        desc = "Resize left",
      },
      {
        "<leader>wL",
        function()
          require("smart-splits").resize_right()
        end,
        desc = "Resize right",
      },
      {
        "<leader>wK",
        function()
          require("smart-splits").resize_up()
        end,
        desc = "Resize up",
      },
      {
        "<leader>wJ",
        function()
          require("smart-splits").resize_down()
        end,
        desc = "Resize down",
      },
    },
  },
}
