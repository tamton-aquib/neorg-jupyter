# Neorg Jupyter

A [neorg](https://github.com/nvim-neorg/neorg) module that allows integration with jupyter notebook inside a neorg file.<br />
Pretty bare-bones right now.

### Setup

Set this inside neorg's setup.
```lua
["external.jupyter"] = {}
```

### Configuration
Currently there are no configuration options

### Usage
Provides 3 options
- `:Neorg jupyter init` (to load up the kernel)
- `:Neorg jupyter generate filename.ipynb` (generate a neorg file from the provided notebook)
- `:Neorg jupyter run` (to run the code block)
