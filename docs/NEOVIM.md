# Neovim (`SUPER + C`)

[LazyVim](https://lazyvim.org) with a VS Code-like setup. Plugins download on the first start (`:Lazy` shows them; `:checkhealth` lists anything missing).

| | |
| --- | --- |
| Files & folders | `nvim .` or `nvim folder/` opens the tree; `<C-p>` / `<space>ff` find file, `<space>fr` recent, `<space>fp` projects, `<space>fd` open any folder under `~` |
| Tabs & panel | every open file is a tab (`<C-Tab>`, `<space>bd` closes); `<C-b>` toggles the project tree |
| Languages | JS/TS, Python, LaTeX (pdflatex via latexmk, `\ll` compile, `\lv` view in zathura; TeX itself: `./install.sh --with-tex`), HTML/CSS + emmet, QML (qmlls from Qt), bash (shellcheck/shfmt), Markdown (rendered), JSON/TOML; servers install themselves via Mason |
| Preview | images and PDFs open inside the editor (kitty graphics); CSV/TSV as an aligned table |
| Git | signs + blame in the gutter, `<space>gg` lazygit, `<space>gh` file history, `<space>gH` repo history, `<space>gD` diff view |
| pi ([pi.dev](https://pi.dev)) | `<space>ai` ask pi about the file / selection (it edits, Neovim reloads), `<space>aP` full pi session in a split. Needs `pi` installed and set up by you |
| Colors | follow the desktop theme live (`~/.local/state/kessel/theme/nvim.json`) |

Press `<space>` and wait: which-key lists everything.
