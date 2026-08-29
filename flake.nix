{
  description = "dok4ever-mac nix-darwin configuration";

  inputs = {
    # Pin to stable release branches (2026-08, per nixos-and-flakes.thiscute.world
    # best practices: avoid floating master/unstable inputs).
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nix-darwin.url = "github:nix-darwin/nix-darwin/nix-darwin-26.05";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
    # atuin needs >= 18.16 (2026-07-09 "shell" migration); stable 26.05 only has 18.15.2.
    # Pin to rev 6f6fca05 = atuin 18.17.1 (last version before 18.18's
    # "duplicate column: shell" migration bug on an already-migrated db).
    # 18.17.1 is patched for search bug #3908 in modules/overlays/default.nix.
    unstable.url = "github:NixOS/nixpkgs/6f6fca055bb8d39ccd3e3be1e27d8b58b9a442d1";

    # herdr (agent multiplexer, 0.8.2) is not in 26.05 stable, and the
    # atuin-pinned `unstable` rev above only has 0.7.5. Track the rolling
    # nixos-unstable channel (locked in flake.lock, reproducible) for 0.8.2.
    # Separate input so atuin's pinned rev stays untouched.
    nixos-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

    # fetch (animated 3D fetch tool) -- https://github.com/areofyl/fetch
    # Pinned to rev 5297ad4 (HEAD as of 2026-08-21). Upstream flake uses
    # nixos-unstable; follow our nixpkgs to avoid pulling a second copy.
    areofyl-fetch.url = "github:areofyl/fetch/5297ad46acf2afb676ddc56aa8f278bd591fb9e6";
    areofyl-fetch.inputs.nixpkgs.follows = "nixpkgs";

    # AI coding agents (claude-code, gemini-cli, qwen-code, ...) from
    # numtide/llm-agents.nix. Built against its OWN pinned nixpkgs-unstable --
    # deliberately NOT `follows = "nixpkgs"`: README warns that following a
    # stable branch (our nixos-26.05) breaks eventually. Costs a second
    # nixpkgs eval but ships the CI-tested combo + prebuilt binaries
    # (when the numtide cache is trusted -- see modules/system/nix.nix).
    llm-agents.url = "github:numtide/llm-agents.nix";
  };

  outputs = inputs @ {
    self,
    nix-darwin,
    nixpkgs,
    unstable,
    nixos-unstable,
    areofyl-fetch,
    llm-agents,
  }: {
    # Build darwin flake using:
    # $ darwin-rebuild switch --flake .#dok4ever-mac
    darwinConfigurations."dok4ever-mac" = nix-darwin.lib.darwinSystem {
      # Pass `inputs` to all modules so they can access overlay/input attrs.
      specialArgs = {
        # Only expose what modules actually consume, not the whole input set:
        #   - unstable  → overlays (atuin 18.17.1)
        #   - areofyl-fetch → programs/fetch.nix
        #   - llm-agents → system/packages.nix (AI coding agents)
        inherit unstable nixos-unstable;
        areofyl-fetch = inputs.areofyl-fetch;
        llm-agents = inputs.llm-agents;
      };

      modules = [
        # All sub-modules are aggregated in modules/default.nix
        # (overlays → system → shell → programs → fixes). The custom-icons
        # module lives at modules/system/custom-icons.nix (vendored from
        # ryanccn/nix-darwin-custom-icons, rev ad3e8cf).
        ./modules

        # Set Git commit hash for darwin-version (needs `self`, so lives here).
        {system.configurationRevision = self.rev or self.dirtyRev or null;}
      ];
    };

    # ── Project templates ───────────────────────────────────────────────
    # Scaffold a flake-based devShell + direnv into a new project dir:
    #   $ cd ~/dev/myapp && nix flake init -t /etc/nix-darwin#python
    #   $ direnv allow
    # Or use the `nt` interactive (fzf) selector in modules/shell/functions.nix.
    # NOTE: template files must be `git add`-ed in this repo before
    # `nix flake init -t` can see them (git flakes only expose tracked files).
    templates = {
      python = {
        path = ./templates/python;
        description = "Python + uv + ruff devShell";
      };
      node = {
        path = ./templates/node;
        description = "Node.js + pnpm devShell";
      };
      go = {
        path = ./templates/go;
        description = "Go + gopls devShell";
      };
      rust = {
        path = ./templates/rust;
        description = "Rust toolchain devShell";
      };
      elm = {
        path = ./templates/elm;
        description = "Elm 0.19 compiler + tooling devShell";
      };
    };
  };
}
