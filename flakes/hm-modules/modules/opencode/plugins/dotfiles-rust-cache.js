// Dotfiles-owned OpenCode V2 plugin. This is independent of Home Manager's
// OpenCode module and remains necessary while the local dev-cache policy does.
// Plugin files load in lexical order, after dotfiles-direnv, so this assignment
// wins when a project's direnv environment sets CARGO_INCREMENTAL differently.
export default {
  id: "dotfiles-rust-cache",
  async setup(ctx) {
    await ctx.shell.hook("create.before", (event) => {
      event.env.CARGO_INCREMENTAL = "0"
    })
  },
}
