# Tac 0.3.0

Smarter screen text selection and a refreshed window.

- Copy Text from Screen now recognizes text with Apple's on-device Vision framework.
- The pointer becomes an I-beam near text, and a selection can start just beside a word.
- Dragging selects whole words and stays in the column you start in, so sidebars at the same height are left out.
- Double-click copies a single word. Releasing the mouse copies, shows a "Text copied" chip and returns to your app.
- Change the Copy Text from Screen shortcut in Utilities. The default stays ⌃⇧⌘T.
- Fixed the overlay not taking keyboard focus on macOS 14 and later, which kept the I-beam and Esc from working.
- The window follows a System Settings–style design with page headers, grouped rows, back and forward navigation and a status summary.
