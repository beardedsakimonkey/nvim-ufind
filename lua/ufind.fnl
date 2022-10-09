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

(fn open [source ?config]
  "The entrypoint for opening a finder window.
  `source`: a sequential table of any type.
  `config`: an optional table containing:
    `display`: a function that converts an element of the `source` table into a string.
    `cb`: a function that's called when selecting an item to open.

  More formally:
    type source = array<'a>
    type config? = {
      cb?: ('edit' | 'split' | 'vsplit' | 'tabedit', 'a) => nil,
      display?: 'a => string,
    }

  Example:
    require'ufind'.open(['~/foo', '~/bar'])

    -- using a custom data structure
    require'ufind'.open([{path='/home/blah/foo', label='foo'}],
                        { display = function(item)
                            return item.label
                          end,
                          cb = function(cmd, item)
                            vim.cmd('edit ' .. item.path)
                          end })"
  (assert (= :table (type source)))
  (local config-defaults
         {:display #$1
          :cb (fn [cmd item]
                (vim.cmd (.. cmd " " (vim.fn.fnameescape item))))})
  (local config (vim.tbl_extend :force config-defaults (or ?config {})))
  (local orig-win (api.nvim_get_current_win))
  (local (input-buf result-buf) (create-bufs))
  (local (input-win result-win) (create-wins input-buf result-buf))
  (local auid (handle-vimresized input-win result-win))
  ;; The data backing what's shown in the result window.
  ;; Structure: { data: any, score: int, positions: array<int> }
  (var results (->> source (vim.tbl_map #{:data $1 :score 0 :positions []})))

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
    (cleanup)
    (config.cb cmd (. results row :data)))

  (fn use-hl-matches [ns results]
    (api.nvim_buf_clear_namespace result-buf ns 0 -1)
    (each [i result (ipairs results)]
      (each [_ pos (ipairs result.positions)]
        (api.nvim_buf_add_highlight result-buf ns :UfindMatch (- i 1) (- pos 1)
                                    pos))))

  (fn use-virt-text [ns text]
    (api.nvim_buf_clear_namespace input-buf ns 0 -1)
    (api.nvim_buf_set_extmark input-buf ns 0 -1
                              {:virt_text [[text :Comment]]
                               :virt_text_pos :right_align}))

  (fn get-query []
    (local [query] (api.nvim_buf_get_lines input-buf 0 1 true))
    ;; Trim prompt from the query
    (query:sub (+ 1 (length PROMPT))))

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

  (fn on-lines []
    (local fzy (require :ufind.fzy))
    ;; Reset cursor to top
    (set-cursor 1)
    ;; Run the fuzzy filter
    (local matches
           (fzy.filter (get-query) (vim.tbl_map #(config.display $1) source)))
    ;; Transform matches into `results`
    (set results
         (->> matches
              (vim.tbl_map (fn [[i positions score]]
                             {:data (. source i) : score : positions}))))
    ;; Sort results
    (table.sort results #(> $1.score $2.score))
    ;; Render results
    (api.nvim_buf_set_lines result-buf 0 -1 true
                            (vim.tbl_map #(config.display $1.data) results))
    ;; Render result count virtual text
    (use-virt-text virt-ns (.. (length results) " / " (length source)))
    ;; Highlight matched characters
    (use-hl-matches match-ns results))

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
