# nix-darwin configuration

My personal [nix-darwin](https://github.com/LnL7/nix-darwin) configuration for Apple Silicon macOS.

## Features

- **Organized module structure**: Split into `modules/<category>/<component>.nix` for better maintainability
- **Zsh configuration**: Managed via nix-darwin, with common plugins and custom functions
- **Tmux**: Vi key bindings, 3-pane workspace layout, fixed split direction
- **Elm development**: Project-level isolated environment via `direnv + flake`, no global compiler conflict
- **Custom dock icons**: Vendored `ryanccn/nix-darwin-custom-icons` module for easier maintenance
- **Common CLI tools**: Pre-configured daily-use cli tools

## Structure

```
.
├── flake.nix         # Flake entry point
├── flake.lock        # Flake lock file
├── modules/
│   ├── programs/     # Program-specific configurations
│   ├── shell/        # Shell (zsh) configuration and plugins
│   └── system/       # System-level configurations
└── README.md
```

## Usage

1. Install nix and nix-darwin following the [official guide](https://nix-darwin.github.io/nix-darwin/)
2. Clone this repository to `/etc/nix-darwin`
3. Run `sudo darwin-rebuild switch --flake .#dok4ever-mac`
4. Enjoy!

## Notes

- I use this configuration on **Apple Silicon macOS**, it may need adjustments for Intel chips
- This is my **personal configuration**, use it as reference at your own risk

## License

MIT
