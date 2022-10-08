(local api vim.api)

(local PROMPT "> ")

(fn TIME [func]
  (fn [...]
    (local start (vim.loop.hrtime))
    (func ...)
    (local end (vim.loop.hrtime))
    (local diff-ms (/ 1000000 (- end start)))
    (print "Time: " diff-ms)))

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
  (local results-win {:relative :editor
                      ;; offset row by the input window's height
                      :row (+ input-height row)
                      : col
                      : width
                      :height (- height input-height)})
  (values input-win results-win))

(fn create-wins [input-buf results-buf]
  (local (input-win-layout results-win-layout) (get-win-layouts))
  (local input-win
         (api.nvim_open_win input-buf true
                            (vim.tbl_extend :force {:style :minimal}
                                            input-win-layout)))
  (local results-win
         (api.nvim_open_win results-buf false
                            (vim.tbl_extend :force
                                            {:style :minimal :focusable false}
                                            results-win-layout)))
  (tset vim.wo results-win :cursorline true)
  (tset vim.wo results-win :winhighlight "CursorLine:PmenuSel")
  (values input-win results-win))

(fn handle-vimresized [input-win results-win]
  (fn relayout []
    (local (input-win-layout results-win-layout) (get-win-layouts))
    (api.nvim_win_set_config input-win input-win-layout)
    (api.nvim_win_set_config results-win results-win-layout))

  (local auid (api.nvim_create_autocmd :VimResized {:callback relayout}))
  auid)

(fn create-bufs []
  (local input-buf (api.nvim_create_buf false true))
  (local results-buf (api.nvim_create_buf false true))
  (tset vim.bo input-buf :buftype :prompt)
  (vim.fn.prompt_setprompt input-buf PROMPT)
  (values input-buf results-buf))

(fn map [buf mode lhs rhs]
  (vim.keymap.set mode lhs rhs {:nowait true :silent true :buffer buf}))

(fn open [source display cb]
  "The entrypoint for opening a finder window.
  `source` can be either a sequential table of any type or a function returning such.
  `display` is a function that converts an element of `source` into a string.
  `cb` is a function that's called when selecting an item to open.

  More formally:
    type source = array<'a> | () => array<'a>
    type display = 'a => string
    type cmd = 'edit' | 'split' | 'vsplit' | 'tabedit'
    type cb = (cmd, 'a) => nil

  Example:
    require'ufind'.open(['~/foo', '~/bar'],
                        tostring,
                        function(cmd, item)
                          vim.cmd('edit ' .. item)
                        end)"
  (local orig-win (api.nvim_get_current_win))
  (local (input-buf results-buf) (create-bufs))
  (local (input-win results-win) (create-wins input-buf results-buf))
  (local auid (handle-vimresized input-win results-win))
  (local source-items (if (= :function (type source))
                          (source)
                          source))
  (assert (= :table (type source-items)))
  ;; The data backing what's shown in the results window.
  ;; Structure: { data: any, score: int, positions: array<int> }
  (var results (vim.tbl_map #{:data $1 :score 0 :positions []} source-items))

  (fn set-cursor [line]
    (api.nvim_win_set_cursor results-win [line 0]))

  (fn move-cursor [offset]
    (local [old-row _] (api.nvim_win_get_cursor results-win))
    (local lines (api.nvim_buf_line_count results-buf))
    (local new-row (-> old-row (+ offset) (math.min lines) (math.max 1)))
    (set-cursor new-row))

  (fn move-cursor-page [up? half?]
    (local {: height} (api.nvim_win_get_config results-win))
    (local offset (-> height (* (if up? -1 1)) (/ (if half? 2 1))))
    (move-cursor offset))

  (fn cleanup []
    (api.nvim_del_autocmd auid)
    (when (api.nvim_buf_is_valid input-buf)
      (api.nvim_buf_delete input-buf {}))
    (when (api.nvim_buf_is_valid results-buf)
      (api.nvim_buf_delete results-buf {}))
    (when (api.nvim_win_is_valid orig-win)
      (api.nvim_set_current_win orig-win)))

  (fn open-result [cmd]
    (local [row _] (api.nvim_win_get_cursor results-win))
    (cleanup)
    (cb cmd (. results row :data)))

  (fn use-virt-text [ns buf text]
    (api.nvim_buf_clear_namespace buf ns 0 -1)
    (api.nvim_buf_set_extmark buf ns 0 -1
                              {:virt_text [[text :Comment]]
                               :virt_text_pos :right_align}))

  (local match-ns (api.nvim_create_namespace :ufind/match))
  (local virt-ns (api.nvim_create_namespace :ufind/virt))

  (fn on-lines [_ buf]
    (local fzy (require :ufind.fzy))
    (api.nvim_buf_clear_namespace results-buf match-ns 0 -1)
    (set-cursor 1)
    (local [query] (api.nvim_buf_get_lines buf 0 1 true))
    ;; Trim prompt from the query
    (local query (query:sub (+ 1 (length PROMPT))))
    ;; Clear the previous `results`
    (set results [])
    ;; Run the fuzzy filter
    (local matches (fzy.filter query (vim.tbl_map #(display $1) source-items)))
    ;; Put the matched lines into `results`
    (each [_ [i positions score] (ipairs matches)]
      (table.insert results {:data (. source-items i) : score : positions}))
    ;; Sort results by score descending
    (table.sort results #(> $1.score $2.score))
    ;; Render result count virtual text
    (local virt-text (.. (length results) " / " (length source-items)))
    (use-virt-text virt-ns input-buf virt-text)
    ;; Set lines
    (api.nvim_buf_set_lines results-buf 0 -1 true
                            (vim.tbl_map #(display $1.data) results))
    ;; Highlight matched characters
    (each [i result (ipairs results)]
      (each [_ pos (ipairs result.positions)]
        (api.nvim_buf_add_highlight results-buf match-ns :UfindMatch (- i 1)
                                    (- pos 1) pos))))

  (map input-buf :i :<Esc> cleanup) ; can use <C-c> to exit insert mode
  (map input-buf :i :<CR> #(open-result :edit))
  (map input-buf :i :<C-l> #(open-result :vsplit))
  (map input-buf :i :<C-s> #(open-result :split))
  (map input-buf :i :<C-t> #(open-result :tabedit))
  (map input-buf :i :<C-j> #(move-cursor 1))
  (map input-buf :i :<C-k> #(move-cursor -1))
  (map input-buf :i :<Down> #(move-cursor 1))
  (map input-buf :i :<Up> #(move-cursor -1))
  (map input-buf :i :<C-u> #(move-cursor-page true true))
  (map input-buf :i :<C-d> #(move-cursor-page false true))
  (map input-buf :i :<PageUp> #(move-cursor-page true false))
  (map input-buf :i :<PageDown> #(move-cursor-page false false))
  (map input-buf :i :<Home> #(set-cursor 1))
  (map input-buf :i :<End> #(set-cursor (api.nvim_buf_line_count results-buf)))
  ;; `on_lines` can be called in various contexts wherein textlock could prevent
  ;; changing buffer contents and window layout. Use `schedule` to defer such
  ;; operations to the main loop.
  (local on_lines (vim.schedule_wrap (TIME on-lines)))
  ;; NOTE: `on_lines` gets called immediately because of setting the prompt
  (assert (api.nvim_buf_attach input-buf false {: on_lines}))
  (api.nvim_create_autocmd :BufLeave {:buffer input-buf :callback cleanup})
  (vim.cmd :startinsert))

{: open}
