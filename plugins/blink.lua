return {
  {
    "saghen/blink.cmp",
    opts = {
      completion = {
        menu = {
          auto_show = false,
        },
        ghost_text = {
          enabled = false,
        },
      },

      keymap = {
        ["<C-j>"] = { "show", "show_documentation", "hide_documentation" },
      },
    },
  },
}
