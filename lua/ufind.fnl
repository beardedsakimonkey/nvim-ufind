(local api vim.api)

(local PROMPT "> ")

(fn get-win-layouts []
  ;; Size of the window
  (local height (-> vim.go.lines (* 0.8) (math.floor)))
  (local width (-> vim.go.columns (* 0.7) (math.floor)))
  ;; Position of the window
  (local row (-> vim.go.lines (- height) (/ 2) (math.ceil)))
  (local col (-> vim.go.columns (- width) (/ 2) (math.ceil)))
  ;; Height of the input window
  (local input-height 1)
  (local input-win {:relative :editor : row : col : width :height 1})
  (local result-win {:relative :editor
                     ;; offset row by the input window's height
                     :row (+ input-height row)
                     : col
                     : width
                     :height (- height input-height)})
  (values input-win result-win))

(fn create-wins [input-buf result-buf]
  (local (input-win-layout result-win-layout) (get-win-layouts))
  (local input-win
         (api.nvim_open_win input-buf true
                            (vim.tbl_extend :force {:style :minimal}
                                            input-win-layout)))
  (local result-win
         (api.nvim_open_win result-buf false
                            (vim.tbl_extend :force
                                            {:style :minimal :focusable false}
                                            result-win-layout)))
  (tset vim.wo result-win :cursorline true)
  (tset vim.wo result-win :winhighlight "CursorLine:PmenuSel")
  (values input-win result-win))

(fn handle-vimresized [input-win result-win]
  (fn relayout []
    (local (input-win-layout result-win-layout) (get-win-layouts))
    (api.nvim_win_set_config input-win input-win-layout)
    ;; NOTE: This disables 'cursorline' due to style = 'minimal' window config
    (api.nvim_win_set_config result-win result-win-layout)
    (tset vim.wo result-win :cursorline true))

  (local auid (api.nvim_create_autocmd :VimResized {:callback relayout}))
  auid)

(fn create-bufs []
  (local input-buf (api.nvim_create_buf false true))
  (local result-buf (api.nvim_create_buf false true))
  (tset vim.bo input-buf :buftype :prompt)
  (vim.fn.prompt_setprompt input-buf PROMPT)
  (values input-buf result-buf))

(local config-defaults
       {:get-display #$1
        :get-value #$1
        :on-complete (fn [cmd item]
                       (vim.cmd (.. cmd " " (vim.fn.fnameescape item))))})

(fn open [items ?config]
  "The entrypoint for opening a finder window.
  `items`: a sequential table of any type.
  `config`: an optional table containing:
    `get-display`: a function that converts an item to a string to be displayed in the results window.
    `get-value`: a function that converts an item to a string to be passed to the fuzzy filterer.
    `on-complete`: a function that's called when selecting an item to open.

  More formally:
    type items = array<'item>
    type config? = {
      get-display?: 'item => string,
      get-value?: 'item => string,
      on-complete?: ('edit' | 'split' | 'vsplit' | 'tabedit', 'item) => nil,
    }

  Example:
    require'ufind'.open(['~/foo', '~/bar'])

    -- using a custom data structure
    require'ufind'.open([{path='/home/blah/foo', label='foo'}],
                        { get-display = function(item)
                            return item.label
                          end,
                          on-complete = function(cmd, item)
                            vim.cmd('edit ' .. item.path)
                          end })"
  (assert (= :table (type items)))
  (local config (vim.tbl_extend :force {} config-defaults (or ?config {})))
  (local orig-win (api.nvim_get_current_win))
  (local (input-buf result-buf) (create-bufs))
  (local (input-win result-win) (create-wins input-buf result-buf))
  (local auid (handle-vimresized input-win result-win))
  ;; Mapping from match index (essentially the line number of the selected
  ;; result) to item index (the index of the corresponding item in  `items`).
  ;; This is needed by `open-result` to pass the selected item to `on-complete`.
  (var match-to-item {})

  (fn set-cursor [line]
    (api.nvim_win_set_cursor result-win [line 0]))

  (fn move-cursor [offset]
    (local [old-row _] (api.nvim_win_get_cursor result-win))
    (local lines (api.nvim_buf_line_count result-buf))
    (local new-row (-> old-row (+ offset) (math.min lines) (math.max 1)))
    (set-cursor new-row))

  (fn move-cursor-page [up? half?]
    (local {: height} (api.nvim_win_get_config result-win))
    (local offset (-> height (* (if up? -1 1)) (/ (if half? 2 1))))
    (move-cursor offset))

  (fn cleanup []
    (api.nvim_del_autocmd auid)
    (if (api.nvim_buf_is_valid input-buf) (api.nvim_buf_delete input-buf {}))
    (if (api.nvim_buf_is_valid result-buf) (api.nvim_buf_delete result-buf {}))
    (if (api.nvim_win_is_valid orig-win) (api.nvim_set_current_win orig-win)))

  (fn open-result [cmd]
    (local [row _] (api.nvim_win_get_cursor result-win))
    (local item-idx (. match-to-item row))
    (local item (. items item-idx))
    (cleanup)
    (config.on-complete cmd item))

  (fn keymap [mode lhs rhs]
    (vim.keymap.set mode lhs rhs {:nowait true :silent true :buffer input-buf}))

  (keymap [:i :n] :<Esc> cleanup) ; can use <C-c> to exit insert mode
  (keymap :i :<CR> #(open-result :edit))
  (keymap :i :<C-l> #(open-result :vsplit))
  (keymap :i :<C-s> #(open-result :split))
  (keymap :i :<C-t> #(open-result :tabedit))
  (keymap :i :<C-j> #(move-cursor 1))
  (keymap :i :<C-k> #(move-cursor -1))
  (keymap :i :<Down> #(move-cursor 1))
  (keymap :i :<Up> #(move-cursor -1))
  (keymap :i :<C-u> #(move-cursor-page true true))
  (keymap :i :<C-d> #(move-cursor-page false true))
  (keymap :i :<PageUp> #(move-cursor-page true false))
  (keymap :i :<PageDown> #(move-cursor-page false false))
  (keymap :i :<Home> #(set-cursor 1))
  (keymap :i :<End> #(set-cursor (api.nvim_buf_line_count result-buf)))
  ;; Namespaces
  (local match-ns (api.nvim_create_namespace :ufind/match))
  (local virt-ns (api.nvim_create_namespace :ufind/virt))

  (fn use-hl-matches [matches]
    (api.nvim_buf_clear_namespace result-buf match-ns 0 -1)
    (each [i [_ positions _] (ipairs matches)]
      (each [_ pos (ipairs positions)]
        (api.nvim_buf_add_highlight result-buf match-ns :UfindMatch (- i 1)
                                    (- pos 1) pos))))

  (fn use-virt-text [text]
    (api.nvim_buf_clear_namespace input-buf virt-ns 0 -1)
    (api.nvim_buf_set_extmark input-buf virt-ns 0 -1
                              {:virt_text [[text :Comment]]
                               :virt_text_pos :right_align}))

  (fn get-query []
    (local [query] (api.nvim_buf_get_lines input-buf 0 1 true))
    ;; Trim prompt from the query
    (query:sub (+ 1 (length PROMPT))))

  (fn on-lines []
    (local fzy (require :ufind.fzy))
    ;; Reset cursor to top
    (set-cursor 1)
    ;; Run the fuzzy filter
    (local matches
           (fzy.filter (get-query) (vim.tbl_map #(config.get-value $1) items)))
    ;; Sort matches
    (table.sort matches (fn [[_ _ score-a] [_ _ score-b]]
                          (> score-a score-b)))
    ;; Render matches
    (api.nvim_buf_set_lines result-buf 0 -1 true
                            (vim.tbl_map (fn [[i]]
                                           (config.get-display (. items i)))
                                         matches))
    ;; Render result count virtual text
    (use-virt-text (.. (length matches) " / " (length items)))
    ;; Highlight matched characters
    (use-hl-matches matches)
    ;; Update match index to item index mapping
    (set match-to-item (collect [match-idx [item-idx _ _] (ipairs matches)]
                         match-idx
                         item-idx)))

  ;; `on_lines` can be called in various contexts wherein textlock could prevent
  ;; changing buffer contents and window layout. Use `schedule` to defer such
  ;; operations to the main loop.
  (local on_lines (vim.schedule_wrap on-lines))
  ;; NOTE: `on_lines` gets called immediately because of setting the prompt
  (assert (api.nvim_buf_attach input-buf false {: on_lines}))
  ;; TODO: make this a better UX
  (api.nvim_create_autocmd :BufLeave {:buffer input-buf :callback cleanup})
  (vim.cmd :startinsert))

{: open}
